defmodule Slidething.Agent.Orchestrator do
  @moduledoc """
  Pure code harness for plan-driven agent execution.

  The orchestrator:
  1. Calls the Planner LLM once to get a GeneratedPlan (no tool calls)
  2. Creates book + pages deterministically from the plan
  3. Executes phases in dependency order via PlanExecutor
  4. Parallelizes automatically based on phase scope (per_page, per_element)
  5. Runs validator phases inline and stores issues in state
  6. Re-runs repair phases if condition (e.g., has_layout_issues) is true
  7. Broadcasts events for monitoring and UI updates
  8. Never blocks on IO (all async via Task.Supervisor + handle_info)
  """

  use GenServer
  require Logger

  alias Slidething.Agent.{
    GeneratedPlan,
    InstructionBuilder,
    Phase,
    PlanContext,
    PlanExecutor,
    PlanPatcher,
    PlanValidator,
    SubagentTask
  }
  alias Slidething.Agent.GenServer, as: AgentGenServer

  @default_format_id "format-web"
  @max_coordinator_rounds 3

  defstruct [
    # Identity
    :run_id,
    :prompt,
    :book_id,
    :target_type,
    :target_id,
    # Status
    :status,
    :started_at,
    :completed_at,
    # Plan execution
    :generated_plan,
    :page_ids,
    # Phase tracking (MapSets of phase names)
    completed_phases: nil,
    running_phases: nil,
    # Pending agent pids → {phase_name, scope}
    pending_agents: %{},
    # LLM task tracking: Task ref → {:planner | :coordinator, phase_name}
    pending_llm_tasks: %{},
    # Outputs from planner/coordinator phases (passed as context to downstream)
    phase_context: %{},
    # Issues from validator phases
    validation_issues: %{},
    # Retry counts per phase
    retry_counts: %{},
    # How many coordinator rounds have applied patches (guards against runaway loops)
    coordinator_rounds: 0
  ]

  # Client API

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(run_id))
  end

  def via_tuple(run_id) do
    {:via, Registry, {Slidething.RunRegistry, run_id}}
  end

  def start_run(pid, prompt, book_id) do
    GenServer.call(pid, {:start_run, prompt, book_id, nil, nil})
  end

  def start_run(pid, prompt, book_id, target_type, target_id) do
    GenServer.call(pid, {:start_run, prompt, book_id, target_type, target_id})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      run_id: Keyword.fetch!(opts, :run_id),
      prompt: nil,
      book_id: nil,
      target_type: Keyword.get(opts, :target_type),
      target_id: Keyword.get(opts, :target_id),
      status: :idle,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      generated_plan: nil,
      page_ids: [],
      completed_phases: MapSet.new(),
      running_phases: MapSet.new(),
      pending_agents: %{},
      pending_llm_tasks: %{},
      phase_context: %{},
      validation_issues: %{},
      retry_counts: %{},
      coordinator_rounds: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_run, prompt, book_id, target_type, target_id}, _from, state) do
    Logger.info("[Orchestrator] Starting run #{state.run_id}")

    new_state = %{state
      | prompt: prompt,
        book_id: book_id,
        target_type: target_type,
        target_id: target_id,
        status: :planning
    }

    broadcast_event(new_state, :started, %{prompt: prompt, book_id: book_id})
    ref = call_planner(new_state)
    new_state = %{new_state | pending_llm_tasks: Map.put(new_state.pending_llm_tasks, ref, {:planner, :initial_planning})}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ── LLM task results (planner + coordinator) ──────────────────────────────

  @impl true
  def handle_info({ref, {:final_response, json}}, state) do
    case Map.pop(state.pending_llm_tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {{:planner, phase_name}, pending} ->
        Process.demonitor(ref, [:flush])
        Logger.info("[Orchestrator] Planner step '#{phase_name}' completed")
        handle_planner_result(%{state | pending_llm_tasks: pending}, phase_name, json)

      {{:coordinator, phase_name}, pending} ->
        Process.demonitor(ref, [:flush])
        Logger.info("[Orchestrator] Coordinator step '#{phase_name}' completed")
        handle_coordinator_result(%{state | pending_llm_tasks: pending}, phase_name, json)
    end
  end

  def handle_info({:agent_done, _agent_pid, _result}, %{status: :failed} = state) do
    Logger.warning("[Orchestrator] Ignoring agent_done — run already failed")
    {:noreply, state}
  end

  @impl true
  def handle_info({:agent_done, agent_pid, _result}, state) do
    case Map.pop(state.pending_agents, agent_pid) do
      {nil, _} ->
        {:noreply, state}

      {{phase_name, _scope}, pending_agents} ->
        new_state = %{state | pending_agents: pending_agents}

        if no_pending_agents_for_phase?(new_state, phase_name) do
          Logger.info("[Orchestrator] Phase '#{phase_name}' all agents done")

          finished = %{new_state
            | completed_phases: MapSet.put(new_state.completed_phases, phase_name),
              running_phases: MapSet.delete(new_state.running_phases, phase_name)
          }

          broadcast_event(finished, :phase_completed, %{phase: phase_name})
          schedule_next_phases(finished)
        else
          {:noreply, new_state}
        end
    end
  end

  @impl true
  def handle_info({:agent_failed, agent_pid, reason}, state) do
    case Map.pop(state.pending_agents, agent_pid) do
      {nil, _} ->
        {:noreply, state}

      {{phase_name, _scope}, pending_agents} ->
        Logger.error("[Orchestrator] Agent for phase '#{phase_name}' failed: #{inspect(reason)}")
        new_state = %{state | pending_agents: pending_agents}
        handle_phase_failure(new_state, phase_name, reason)
    end
  end

  @impl true
  def handle_info({:phase_all_failed, phase_name}, state) do
    handle_phase_failure(state, phase_name, "all agent starts failed")
  end

  # DOWN from planner/coordinator Task crash
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.pending_llm_tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_step_type, phase_name}, pending} ->
        Logger.error("[Orchestrator] LLM task '#{phase_name}' crashed: #{inspect(reason)}")
        fail_run(%{state | pending_llm_tasks: pending}, "'#{phase_name}' crashed: #{inspect(reason)}")
    end
  end

  # Initial planner result (status: :planning)
  defp handle_planner_result(%{status: :planning} = state, _phase_name, plan_json) do
    case parse_and_validate_plan(plan_json) do
      {:ok, plan} ->
        case create_book_and_pages(plan, state) do
          {:ok, book_id, page_ids} ->
            new_state = %{state
              | generated_plan: plan,
                book_id: book_id,
                page_ids: page_ids,
                status: :executing,
                completed_phases: MapSet.new(),
                running_phases: MapSet.new()
            }

            broadcast_event(new_state, :planning_complete, %{
              book_id: book_id,
              page_count: length(page_ids),
              phase_count: length(plan.phases)
            })

            schedule_next_phases(new_state)

          {:error, reason} ->
            fail_run(state, "Failed to create book: #{inspect(reason)}")
        end

      {:error, reason} ->
        fail_run(state, "Invalid plan from planner: #{reason}")
    end
  end

  # Mid-run planner step result (status: :executing)
  defp handle_planner_result(%{status: :executing} = state, phase_name, plan_json) do
    ctx = %PlanContext{
      phase_name: phase_name,
      scope: :book,
      data: parse_json_loosely(plan_json)
    }

    new_state = %{state
      | phase_context: Map.put(state.phase_context, phase_name, ctx),
        completed_phases: MapSet.put(state.completed_phases, phase_name),
        running_phases: MapSet.delete(state.running_phases, phase_name)
    }

    broadcast_event(new_state, :phase_completed, %{phase: phase_name})
    schedule_next_phases(new_state)
  end

  defp handle_planner_result(state, phase_name, _plan_json) do
    Logger.warning("[Orchestrator] Unexpected planner result in status #{state.status} for phase #{phase_name}")
    {:noreply, state}
  end

  # ── Coordinator result ─────────────────────────────────────────────────────

  defp handle_coordinator_result(state, phase_name, json_text) do
    parsed = parse_json_loosely(json_text)

    # Store the "context" portion as phase context for downstream phases
    ctx_data = Map.get(parsed, "context", parsed)
    ctx = %PlanContext{phase_name: phase_name, scope: :book, data: ctx_data}

    state = %{state
      | phase_context: Map.put(state.phase_context, phase_name, ctx),
        completed_phases: MapSet.put(state.completed_phases, phase_name),
        running_phases: MapSet.delete(state.running_phases, phase_name)
    }

    broadcast_event(state, :phase_completed, %{phase: phase_name})

    # Apply plan_patches if present
    patches = case Map.get(parsed, "plan_patches") do
      list when is_list(list) -> list
      _ -> []
    end

    state = case apply_plan_patches(state, phase_name, patches) do
      {:ok, new_state} -> new_state
      {:error, reason} ->
        Logger.warning("[Orchestrator] Patches from '#{phase_name}' rejected: #{reason}")
        state
    end

    schedule_next_phases(state)
  end

  defp apply_plan_patches(state, _phase_name, []), do: {:ok, state}

  defp apply_plan_patches(state, phase_name, patches) do
    if state.coordinator_rounds >= @max_coordinator_rounds do
      Logger.warning("[Orchestrator] Max coordinator rounds (#{@max_coordinator_rounds}) reached — ignoring #{length(patches)} patch(es) from '#{phase_name}'")
      {:ok, state}
    else
      case PlanPatcher.apply(state.generated_plan.phases, patches, state.completed_phases) do
        {:ok, new_phases} ->
          try do
            :ok = PlanValidator.validate_plan!(new_phases)
            new_plan = %{state.generated_plan | phases: new_phases}
            new_state = %{state | generated_plan: new_plan, coordinator_rounds: state.coordinator_rounds + 1}
            Logger.info("[Orchestrator] Applied #{length(patches)} patch(es) from '#{phase_name}' (coordinator round #{new_state.coordinator_rounds})")
            broadcast_event(new_state, :plan_patched, %{phase: phase_name, patch_count: length(patches), round: new_state.coordinator_rounds})
            {:ok, new_state}
          rescue
            e -> {:error, "patched plan failed validation: #{Exception.message(e)}"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ── Phase scheduling ───────────────────────────────────────────────────────

  defp schedule_next_phases(state) do
    phases = state.generated_plan.phases
    ready = PlanExecutor.find_ready_phases(phases, state.completed_phases, state.running_phases, state)

    cond do
      ready != [] ->
        new_state = Enum.reduce(ready, state, &execute_phase(&2, &1))
        # Synchronous phases (validator) complete immediately — re-check in case more phases are ready
        if all_sync?(ready) do
          schedule_next_phases(new_state)
        else
          {:noreply, new_state}
        end

      PlanExecutor.all_phases_complete?(phases, state.completed_phases, state) ->
        complete_run(state)

      true ->
        # Waiting for in-flight agents/planner tasks
        {:noreply, state}
    end
  end

  defp all_sync?(phases), do: Enum.all?(phases, &(&1.step_type == :validator))

  defp execute_phase(state, %Phase{step_type: :planner} = phase) do
    Logger.info("[Orchestrator] Starting planner step '#{phase.name}'")
    instruction = InstructionBuilder.build_planner(
      phase, :book, state.prompt, state.phase_context, state.book_id
    )

    planner_spec = Slidething.Agent.Config.agent_spec(:planner)

    task = Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
      Slidething.LLM.Client.complete_json(planner_spec, [
        %Slidething.Agent.Message{role: :system, content: planner_spec.system_prompt},
        %Slidething.Agent.Message{role: :user, content: instruction}
      ])
    end)

    %{state
      | running_phases: MapSet.put(state.running_phases, phase.name),
        pending_llm_tasks: Map.put(state.pending_llm_tasks, task.ref, {:planner, phase.name})
    }
  end

  defp execute_phase(state, %Phase{step_type: :coordinator} = phase) do
    Logger.info("[Orchestrator] Starting coordinator step '#{phase.name}'")
    broadcast_event(state, :phase_started, %{phase: phase.name, step_type: :coordinator})

    instruction = InstructionBuilder.build_coordinator(
      phase, state.prompt, state.phase_context, state.book_id, state.page_ids
    )

    coordinator_spec = Slidething.Agent.Config.agent_spec(:coordinator)

    task = Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
      Slidething.LLM.Client.complete_json(coordinator_spec, [
        %Slidething.Agent.Message{role: :system, content: coordinator_spec.system_prompt},
        %Slidething.Agent.Message{role: :user, content: instruction}
      ])
    end)

    %{state
      | running_phases: MapSet.put(state.running_phases, phase.name),
        pending_llm_tasks: Map.put(state.pending_llm_tasks, task.ref, {:coordinator, phase.name})
    }
  end

  defp execute_phase(state, %Phase{step_type: :validator} = phase) do
    Logger.info("[Orchestrator] Running validator phase '#{phase.name}'")
    broadcast_event(state, :phase_started, %{phase: phase.name, step_type: :validator})

    page_ids = scoped_page_ids(phase.scope, state)
    issues = Enum.flat_map(page_ids, &Slidething.Validator.Layout.validate(&1, @default_format_id))
    issue_maps = Enum.map(issues, &issue_to_map/1)

    if issue_maps != [] do
      broadcast_event(state, :validation_issues, %{phase: phase.name, issues: issue_maps})
    end

    new_state = %{state
      | validation_issues: Map.put(state.validation_issues, phase.name, issue_maps),
        completed_phases: MapSet.put(state.completed_phases, phase.name),
        running_phases: MapSet.delete(state.running_phases, phase.name)
    }
    broadcast_event(new_state, :phase_completed, %{phase: phase.name})
    new_state
  end

  defp execute_phase(state, %Phase{step_type: :agent} = phase) do
    Logger.info("[Orchestrator] Starting agent phase '#{phase.name}' (scope: #{phase.scope})")
    broadcast_event(state, :phase_started, %{phase: phase.name, scope: phase.scope})

    tasks = build_tasks_for_phase(phase, state)
    agent_spec = Slidething.Agent.Config.agent_spec(phase.agent_type)

    pending =
      Enum.reduce(tasks, state.pending_agents, fn task, acc ->
        case start_agent(state.run_id, task.agent, task.scope, agent_spec) do
          {:ok, pid} ->
            context = %{scope: AgentGenServer.scope_to_json(task.scope), task_count: length(tasks)}
            AgentGenServer.start_task(pid, task.instruction, context)
            Map.put(acc, pid, {phase.name, task.scope})

          {:error, reason} ->
            Logger.error("[Orchestrator] Failed to start agent for phase '#{phase.name}': #{inspect(reason)}")
            acc
        end
      end)

    started_count = map_size(pending) - map_size(state.pending_agents)

    cond do
      tasks == [] ->
        # No tasks for this phase (e.g., per_element with no elements) — mark complete
        Logger.info("[Orchestrator] Phase '#{phase.name}' has no tasks — skipping")
        %{state
          | completed_phases: MapSet.put(state.completed_phases, phase.name)
        }

      started_count == 0 ->
        # All starts failed
        Logger.error("[Orchestrator] All agent starts failed for phase '#{phase.name}'")
        send(self(), {:phase_all_failed, phase.name})
        state

      true ->
        %{state
          | pending_agents: pending,
            running_phases: MapSet.put(state.running_phases, phase.name)
        }
    end
  end

  # ── Task building ──────────────────────────────────────────────────────────

  defp build_tasks_for_phase(%Phase{scope: :book} = phase, state) do
    [%SubagentTask{
      agent: phase.agent_type,
      scope: :book,
      phase_name: phase.name,
      instruction: InstructionBuilder.build(phase, :book, state.prompt, state.phase_context, state.book_id)
    }]
  end

  defp build_tasks_for_phase(%Phase{scope: :per_page} = phase, state) do
    page_ids = scoped_page_ids(:per_page, state)
    Enum.map(page_ids, fn page_id ->
      scope = {:page, page_id}
      %SubagentTask{
        agent: phase.agent_type,
        scope: scope,
        phase_name: phase.name,
        instruction: build_agent_instruction(phase, scope, state)
      }
    end)
  end

  defp build_tasks_for_phase(%Phase{scope: :per_element} = phase, state) do
    page_ids = scoped_page_ids(:per_page, state)

    Enum.flat_map(page_ids, fn page_id ->
      layout = fetch_layout(page_id)
      elements_by_id = page_id |> Slidething.Element.list() |> Map.new(&{&1.id, &1})

      page_id
      |> media_elements_for_page(layout, elements_by_id)
      |> Enum.map(fn {element, aspect} ->
        scope = {:element, element.id}
        content = get_in(element, [:latest_version, :content]) || get_in(element, [Access.key(:latest_version, %{}), :content]) || ""
        instruction =
          "Generate an image for element #{element.id} (aspect ratio #{aspect}). " <>
          "Description: #{content}. " <>
          "Call generate_image with prompt and aspect_ratio=\"#{aspect}\", " <>
          "then store_asset with the returned asset_path."

        %SubagentTask{
          agent: phase.agent_type,
          scope: scope,
          phase_name: phase.name,
          instruction: instruction
        }
      end)
    end)
  end

  defp build_agent_instruction(phase, {:page, page_id} = scope, state) do
    base = InstructionBuilder.build(phase, scope, state.prompt, state.phase_context, state.book_id)

    # For layout, inject element data and format note inline to avoid extra tool calls
    if phase.agent_type == :layout do
      format = Slidething.Book.get_format(@default_format_id)
      format_note = if format do
        "Format: #{format.name}, #{format.width}#{format.unit} × #{format.height}#{format.unit}, " <>
        "safe_margin=#{format.safe_margin_mm}mm.\n"
      else
        ""
      end

      elements = Slidething.Element.list(page_id)
      elements_note = elements
        |> Enum.map(fn e ->
          content = get_in(e, [:latest_version, :content]) || "(no content)"
          "  {element_id: #{e.id}, type: #{e.element_type}, content: #{inspect(String.slice(to_string(content), 0, 80))}}"
        end)
        |> Enum.join("\n")

      base <> "\n\n" <> format_note <>
        "Elements on page:\n#{elements_note}\n" <>
        "Call propose_layout with page_id=#{page_id}, format_id=\"#{@default_format_id}\", " <>
        "x/y/width/height as fractions in 0..1. Do NOT call get_page_elements or get_format."
    else
      base
    end
  end

  # ── Phase failure & retry ──────────────────────────────────────────────────

  defp handle_phase_failure(state, phase_name, reason) do
    phase = find_phase(state, phase_name)
    retry_count = Map.get(state.retry_counts, phase_name, 0)
    max_retries = (phase && phase.max_retries) || 2

    if retry_count < max_retries do
      Logger.warning("[Orchestrator] Phase '#{phase_name}' failed, retrying (#{retry_count + 1}/#{max_retries})")

      new_state = %{state
        | retry_counts: Map.put(state.retry_counts, phase_name, retry_count + 1),
          running_phases: MapSet.delete(state.running_phases, phase_name)
      }

      if phase do
        {:noreply, execute_phase(new_state, phase)}
      else
        fail_run(new_state, "Phase '#{phase_name}' failed and not found for retry")
      end
    else
      fail_run(state, "Phase '#{phase_name}' failed after #{retry_count} retries: #{inspect(reason)}")
    end
  end

  # ── Book + page creation ───────────────────────────────────────────────────

  defp create_book_and_pages(plan, state) do
    if state.book_id do
      if state.target_type && state.target_id do
        # Targeting a specific existing page — use it as-is, no new pages
        page_ids = filter_page_ids([state.target_id], state)
        {:ok, state.book_id, page_ids}
      else
        # Adding pages to an existing book — create new pages per the plan
        count = if plan.page_specs, do: length(plan.page_specs), else: 1
        {:ok, new_page_ids} = Slidething.Book.create_pages(state.book_id, count)
        {:ok, state.book_id, new_page_ids}
      end
    else
      with book_struct = plan.book_structure || %{title: "Untitled", metadata: %{}},
           {:ok, %{book_id: book_id}} <- Slidething.Book.create(book_struct.title, book_struct.metadata),
           _ <- Slidething.Book.add_format(book_id, @default_format_id),
           {:ok, page_ids} <- create_pages(book_id, plan.page_specs) do
        {:ok, book_id, page_ids}
      end
    end
  end

  defp create_pages(book_id, nil) do
    Slidething.Book.create_pages(book_id, 1)
  end

  defp create_pages(book_id, page_specs) when is_list(page_specs) do
    entries = Enum.map(page_specs, fn p ->
      %{position: p.position, metadata: p.metadata || %{}}
    end)
    Slidething.Book.create_pages(book_id, entries)
  end

  defp filter_page_ids(all_page_ids, %{target_type: "page", target_id: page_id}) when not is_nil(page_id) do
    Enum.filter(all_page_ids, &(&1 == page_id))
  end

  defp filter_page_ids(all_page_ids, _state), do: all_page_ids

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp scoped_page_ids(:per_page, state), do: state.page_ids
  defp scoped_page_ids(:book, _state), do: []
  defp scoped_page_ids(:per_element, state), do: state.page_ids

  defp no_pending_agents_for_phase?(state, phase_name) do
    not Enum.any?(state.pending_agents, fn {_pid, {pname, _}} -> pname == phase_name end)
  end

  defp find_phase(state, phase_name) do
    state.generated_plan && Enum.find(state.generated_plan.phases, &(&1.name == phase_name))
  end

  defp media_elements_for_page(_page_id, nil, elements_by_id) do
    elements_by_id
    |> Map.values()
    |> Enum.filter(&image_needs_asset?/1)
    |> Enum.map(&{&1, "1:1"})
  end

  defp media_elements_for_page(_page_id, layout, elements_by_id) do
    Enum.flat_map(layout.element_layouts, fn entry ->
      element_id = entry["element_id"] || entry[:element_id]
      element = Map.get(elements_by_id, element_id)

      cond do
        is_nil(element) -> []
        not image_needs_asset?(element) -> []
        true -> [{element, aspect_from_layout(entry)}]
      end
    end)
  end

  defp image_needs_asset?(element) do
    element.element_type == "image" and
      (is_nil(element.latest_version) or is_nil(element.latest_version.asset_path))
  end

  defp aspect_from_layout(entry) do
    width = entry["width"] || entry[:width]
    height = entry["height"] || entry[:height]

    if is_number(width) and is_number(height) and height > 0 do
      Slidething.Image.Provider.snap_aspect(width / height)
    else
      "1:1"
    end
  end

  defp fetch_layout(page_id) do
    case Slidething.Layout.get_latest(page_id, @default_format_id) do
      {:ok, layout} -> layout
      _ -> nil
    end
  end

  defp start_agent(run_id, agent_type, scope, spec) do
    opts = [
      run_id: run_id,
      agent_type: agent_type,
      scope: scope,
      orchestrator_pid: self(),
      agent_spec: spec
    ]

    DynamicSupervisor.start_child(Slidething.RunSupervisor, {AgentGenServer, opts})
  end

  defp issue_to_map(issue) do
    %{
      severity: issue.severity,
      source: issue.source,
      target_id: issue.target_id,
      rule: issue.rule,
      message: issue.message,
      measured_value: issue.measured_value,
      expected_value: issue.expected_value
    }
  end

  # ── Plan parsing ───────────────────────────────────────────────────────────

  defp call_planner(state) do
    planner_spec = Slidething.Agent.Config.agent_spec(:planner)
    instruction = build_initial_planner_prompt(state)

    task = Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
      Slidething.LLM.Client.complete_json(planner_spec, [
        %Slidething.Agent.Message{role: :system, content: planner_spec.system_prompt},
        %Slidething.Agent.Message{role: :user, content: instruction}
      ])
    end)

    broadcast_event(state, :phase_started, %{phase: :initial_planning})
    task.ref
  end

  defp build_initial_planner_prompt(state) do
    parts = ["User request: #{state.prompt}"]

    parts = if state.book_id do
      case Slidething.Book.get(state.book_id) do
        {:ok, book} ->
          book_info = "Existing book:\n  id: #{state.book_id}\n  title: #{book.title}"
          parts ++ [book_info]
        _ ->
          parts
      end
    else
      parts
    end

    parts = case state.target_type do
      "page" when not is_nil(state.target_id) ->
        parts ++ ["Target page: #{state.target_id}"]
      "element" when not is_nil(state.target_id) ->
        parts ++ ["Target element: #{state.target_id}"]
      _ ->
        parts
    end

    Enum.join(parts, "\n\n")
  end

  defp parse_and_validate_plan(json_text) do
    try do
      with {:ok, map} <- parse_json_loosely_result(json_text),
           plan = GeneratedPlan.from_map(map),
           :ok <- PlanValidator.validate_plan!(plan.phases) do
        {:ok, plan}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp parse_json_loosely(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, decoded} -> decoded
      _ ->
        case Regex.run(~r/```(?:json)?\s*\n(.*?)\n```/s, text) do
          [_, captured] ->
            case Jason.decode(String.trim(captured)) do
              {:ok, decoded} -> decoded
              _ -> %{"raw" => text}
            end
          nil -> %{"raw" => text}
        end
    end
  end

  defp parse_json_loosely(other), do: other

  defp parse_json_loosely_result(text) do
    case Jason.decode(text) do
      {:ok, _} = ok -> ok
      _ ->
        case Regex.run(~r/```(?:json)?\s*\n(.*?)\n```/s, text) do
          [_, captured] -> Jason.decode(String.trim(captured))
          nil -> {:error, :no_json_found}
        end
    end
  end

  # ── Run completion / failure ───────────────────────────────────────────────

  defp complete_run(state) do
    Logger.info("[Orchestrator] Run #{state.run_id} completed")

    new_state = %{state | status: :done, completed_at: DateTime.utc_now()}
    Slidething.Prompt.complete(state.run_id, "completed #{length(state.page_ids)} page(s)")

    broadcast_event(new_state, :completed, %{
      duration_ms: DateTime.diff(new_state.completed_at, state.started_at, :millisecond),
      pages: length(state.page_ids)
    })

    {:noreply, new_state}
  end

  defp fail_run(state, reason) do
    Logger.error("[Orchestrator] Run #{state.run_id} failed: #{reason}")

    new_state = %{state | status: :failed, completed_at: DateTime.utc_now()}
    Slidething.Prompt.fail(state.run_id, reason)
    broadcast_event(new_state, :failed, %{reason: reason})

    {:noreply, new_state}
  end

  # ── Event broadcasting ─────────────────────────────────────────────────────

  defp broadcast_event(state, event_type, data) do
    event = %{
      run_id: state.run_id,
      event: event_type,
      status: state.status,
      data: data,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Slidething.PubSub, "events:#{state.run_id}", {:run_event, event})
  end
end
