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
    Message,
    Phase,
    PlanContext,
    PlanExecutor,
    PlanPatcher,
    PlanValidator,
    SubagentTask,
    ToolCall
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
    page_index_map: %{},
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
      page_index_map: %{},
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

    new_state = %{
      state
      | prompt: prompt,
        book_id: book_id,
        target_type: target_type,
        target_id: target_id,
        status: :planning
    }

    broadcast_event(new_state, :started, %{prompt: prompt, book_id: book_id})
    ref = call_planner(new_state)

    new_state = %{
      new_state
      | pending_llm_tasks:
          Map.put(new_state.pending_llm_tasks, ref, {:planner, :initial_planning})
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ── LLM task results (planner + coordinator) ──────────────────────────────

  @impl true
  def handle_info({ref, {:error, reason}}, state) do
    case Map.pop(state.pending_llm_tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {{:media, phase_name, _page_id, _op, _element_id, _prompt}, pending} ->
        Process.demonitor(ref, [:flush])
        Logger.error("[Orchestrator] Media phase '#{phase_name}' failed: #{inspect(reason)}")

        finished = %{
          state
          | pending_llm_tasks: pending,
            completed_phases: MapSet.put(state.completed_phases, phase_name),
            running_phases: MapSet.delete(state.running_phases, phase_name)
        }

        schedule_next_phases(finished)

      {_task, pending} ->
        Process.demonitor(ref, [:flush])
        Logger.error("[Orchestrator] LLM task failed: #{inspect(reason)}")
        fail_run(%{state | pending_llm_tasks: pending}, reason)
    end
  end

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

      {{:content, phase_name, page_id, op, element_type, element_id}, pending} ->
        Process.demonitor(ref, [:flush])
        Logger.info("[Orchestrator] Content phase '#{phase_name}' completed")

        if op == "update" and element_id do
          Slidething.Element.update(element_id, json)
        else
          Slidething.Element.create(page_id, element_type, json)
        end

        finished = %{
          state
          | pending_llm_tasks: pending,
            completed_phases: MapSet.put(state.completed_phases, phase_name),
            running_phases: MapSet.delete(state.running_phases, phase_name)
        }

        broadcast_event(finished, :phase_completed, %{phase: phase_name})
        schedule_next_phases(finished)
    end
  end

  def handle_info({ref, {:ok, asset_path}}, state) when is_binary(asset_path) do
    case Map.pop(state.pending_llm_tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {{:media, phase_name, page_id, op, element_id, final_prompt}, pending} ->
        Process.demonitor(ref, [:flush])
        Logger.info("[Orchestrator] Media phase '#{phase_name}' completed")

        if op == "update" and element_id do
          Slidething.Element.update(element_id, nil, asset_path: asset_path, prompt: final_prompt)
        else
          Slidething.Element.create(page_id, "image", final_prompt, asset_path: asset_path)
        end

        finished = %{
          state
          | pending_llm_tasks: pending,
            completed_phases: MapSet.put(state.completed_phases, phase_name),
            running_phases: MapSet.delete(state.running_phases, phase_name)
        }

        broadcast_event(finished, :phase_completed, %{phase: phase_name})
        schedule_next_phases(finished)
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

          finished = %{
            new_state
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

        fail_run(
          %{state | pending_llm_tasks: pending},
          "'#{phase_name}' crashed: #{inspect(reason)}"
        )
    end
  end

  # Initial planner result (status: :planning)
  defp handle_planner_result(%{status: :planning} = state, _phase_name, plan_json) do
    Logger.debug("[Planner] Emit result: #{inspect(plan_json, limit: 5000)}")

    case parse_and_validate_plan(plan_json) do
      {:ok, plan} ->
        Logger.debug("[Planner] Phases: #{inspect(Enum.map(plan.phases, & &1.name))}")

        case ensure_book(state) do
          {:ok, book_id} ->
            context_map =
              cond do
                is_map(plan.context) ->
                  plan.context

                is_binary(plan.context) ->
                  case Jason.decode(plan.context) do
                    {:ok, map} when is_map(map) -> map
                    _ -> %{}
                  end

                true ->
                  %{}
              end

            case context_map["book_title"] do
              title when is_binary(title) and title != "" ->
                Slidething.Book.update_title(book_id, title)

              _ ->
                :ok
            end

            new_state = %{
              state
              | generated_plan: plan,
                book_id: book_id,
                page_index_map: %{},
                status: :executing,
                completed_phases: MapSet.new(),
                running_phases: MapSet.new()
            }

            broadcast_event(new_state, :planning_complete, %{
              book_id: book_id,
              phase_count: length(plan.phases)
            })

            schedule_next_phases(new_state)

          {:error, reason} ->
            fail_run(state, "Failed to create book: #{inspect(reason)}")
        end

      {:error, reason} ->
        fail_run(state, "Invalid plan from planner: #{inspect(reason)}")
    end
  end

  # Mid-run planner step result (status: :executing)
  defp handle_planner_result(%{status: :executing} = state, phase_name, plan_json) do
    ctx = %PlanContext{
      phase_name: phase_name,
      scope: :book,
      data: parse_json_loosely(plan_json)
    }

    new_state = %{
      state
      | phase_context: Map.put(state.phase_context, phase_name, ctx),
        completed_phases: MapSet.put(state.completed_phases, phase_name),
        running_phases: MapSet.delete(state.running_phases, phase_name)
    }

    broadcast_event(new_state, :phase_completed, %{phase: phase_name})
    schedule_next_phases(new_state)
  end

  defp handle_planner_result(state, phase_name, _plan_json) do
    Logger.warning(
      "[Orchestrator] Unexpected planner result in status #{state.status} for phase #{phase_name}"
    )

    {:noreply, state}
  end

  # ── Coordinator result ─────────────────────────────────────────────────────

  defp handle_coordinator_result(state, phase_name, json_text) do
    parsed = parse_json_loosely(json_text)

    # Store the "context" portion as phase context for downstream phases
    ctx_data = Map.get(parsed, "context", parsed)
    ctx = %PlanContext{phase_name: phase_name, scope: :book, data: ctx_data}

    state = %{
      state
      | phase_context: Map.put(state.phase_context, phase_name, ctx),
        completed_phases: MapSet.put(state.completed_phases, phase_name),
        running_phases: MapSet.delete(state.running_phases, phase_name)
    }

    broadcast_event(state, :phase_completed, %{phase: phase_name})

    # Apply plan_patches if present
    patches =
      case Map.get(parsed, "plan_patches") do
        list when is_list(list) -> list
        _ -> []
      end

    state =
      case apply_plan_patches(state, phase_name, patches) do
        {:ok, new_state} ->
          new_state

        {:error, reason} ->
          Logger.warning("[Orchestrator] Patches from '#{phase_name}' rejected: #{reason}")
          state
      end

    schedule_next_phases(state)
  end

  defp apply_plan_patches(state, _phase_name, []), do: {:ok, state}

  defp apply_plan_patches(state, phase_name, patches) do
    if state.coordinator_rounds >= @max_coordinator_rounds do
      Logger.warning(
        "[Orchestrator] Max coordinator rounds (#{@max_coordinator_rounds}) reached — ignoring #{length(patches)} patch(es) from '#{phase_name}'"
      )

      {:ok, state}
    else
      case PlanPatcher.apply(state.generated_plan.phases, patches, state.completed_phases) do
        {:ok, new_phases} ->
          try do
            :ok = PlanValidator.validate_plan!(new_phases)
            new_plan = %{state.generated_plan | phases: new_phases}

            new_state = %{
              state
              | generated_plan: new_plan,
                coordinator_rounds: state.coordinator_rounds + 1
            }

            Logger.info(
              "[Orchestrator] Applied #{length(patches)} patch(es) from '#{phase_name}' (coordinator round #{new_state.coordinator_rounds})"
            )

            broadcast_event(new_state, :plan_patched, %{
              phase: phase_name,
              patch_count: length(patches),
              round: new_state.coordinator_rounds
            })

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

    ready =
      PlanExecutor.find_ready_phases(phases, state.completed_phases, state.running_phases, state)

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

  defp all_sync?(phases) do
    Enum.all?(phases, fn p -> p.step_type == :validator end)
  end

  defp execute_phase(state, %Phase{step_type: :planner} = phase) do
    Logger.info("[Orchestrator] Starting planner step '#{phase.name}'")

    instruction =
      InstructionBuilder.build_planner(
        phase,
        :book,
        state.prompt,
        state.phase_context,
        state.book_id
      )

    planner_spec = Slidething.Agent.Config.agent_spec(:planner)

    task =
      Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
        run_planner_step_loop(planner_spec, [
          %Message{role: :system, content: planner_spec.system_prompt},
          %Message{role: :user, content: instruction}
        ])
      end)

    %{
      state
      | running_phases: MapSet.put(state.running_phases, phase.name),
        pending_llm_tasks: Map.put(state.pending_llm_tasks, task.ref, {:planner, phase.name})
    }
  end

  defp execute_phase(state, %Phase{step_type: :coordinator} = phase) do
    Logger.info("[Orchestrator] Starting coordinator step '#{phase.name}'")
    broadcast_event(state, :phase_started, %{phase: phase.name, step_type: :coordinator})

    instruction =
      InstructionBuilder.build_coordinator(
        phase,
        state.prompt,
        state.phase_context,
        state.book_id,
        scoped_page_ids(:per_page, state)
      )

    coordinator_spec = Slidething.Agent.Config.agent_spec(:coordinator)

    task =
      Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
        Slidething.LLM.Client.complete_json(coordinator_spec, [
          %Slidething.Agent.Message{role: :system, content: coordinator_spec.system_prompt},
          %Slidething.Agent.Message{role: :user, content: instruction}
        ])
      end)

    %{
      state
      | running_phases: MapSet.put(state.running_phases, phase.name),
        pending_llm_tasks: Map.put(state.pending_llm_tasks, task.ref, {:coordinator, phase.name})
    }
  end

  defp execute_phase(state, %Phase{step_type: :validator} = phase) do
    Logger.info("[Orchestrator] Running validator phase '#{phase.name}'")
    broadcast_event(state, :phase_started, %{phase: phase.name, step_type: :validator})

    page_ids = scoped_page_ids(phase.scope, state)

    issues =
      Enum.flat_map(page_ids, &Slidething.Validator.Layout.validate(&1, @default_format_id))

    issue_maps = Enum.map(issues, &issue_to_map/1)

    if issue_maps != [] do
      broadcast_event(state, :validation_issues, %{phase: phase.name, issues: issue_maps})
    end

    new_state = %{
      state
      | validation_issues: Map.put(state.validation_issues, phase.name, issue_maps),
        completed_phases: MapSet.put(state.completed_phases, phase.name),
        running_phases: MapSet.delete(state.running_phases, phase.name)
    }

    broadcast_event(new_state, :phase_completed, %{phase: phase.name})
    new_state
  end

  defp execute_phase(state, %Phase{step_type: :agent, agent_type: :content} = phase) do
    Logger.info("[Orchestrator] Starting content phase '#{phase.name}'")
    broadcast_event(state, :phase_started, %{phase: phase.name, step_type: :content})

    config = phase.config || %{}
    op = config["op"] || "create"
    element_type = config["element_type"] || "text"
    element_id = config["element_id"]

    {page_id, new_state} = resolve_and_register_page(phase, state)

    instruction = build_agent_instruction(phase, {:page, page_id}, new_state)
    spec = Slidething.Agent.Config.agent_spec(:content)

    task =
      Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
        Slidething.LLM.Client.complete_json(spec, [
          %Message{role: :system, content: spec.system_prompt},
          %Message{role: :user, content: instruction}
        ])
      end)

    %{
      new_state
      | running_phases: MapSet.put(new_state.running_phases, phase.name),
        pending_llm_tasks:
          Map.put(
            new_state.pending_llm_tasks,
            task.ref,
            {:content, phase.name, page_id, op, element_type, element_id}
          )
    }
  end

  defp execute_phase(state, %Phase{step_type: :agent, agent_type: :media} = phase) do
    Logger.info("[Orchestrator] Starting media phase '#{phase.name}'")
    broadcast_event(state, :phase_started, %{phase: phase.name, step_type: :media})

    config = phase.config || %{}
    op = config["op"] || "create"
    element_id = config["element_id"]
    aspect_ratio = config["aspect_ratio"] || "1:1"
    prompt_prefix = config["image_prompt"]

    {page_id, new_state} = resolve_and_register_page(phase, state)

    elements = Slidething.Element.list(page_id)
    derived_subject = derive_image_subject(elements)

    final_prompt =
      [prompt_prefix, derived_subject]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" — ")

    final_prompt = if final_prompt == "", do: "Illustration", else: final_prompt

    spec = Slidething.Agent.Config.agent_spec(:media)
    provider = (spec && spec.image_provider) || "mock"
    model = (spec && spec.image_model) || "mock-image-model"

    task =
      Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
        Slidething.Image.Client.generate(provider, model, final_prompt, aspect_ratio)
      end)

    %{
      new_state
      | running_phases: MapSet.put(new_state.running_phases, phase.name),
        pending_llm_tasks:
          Map.put(
            new_state.pending_llm_tasks,
            task.ref,
            {:media, phase.name, page_id, op, element_id, final_prompt}
          )
    }
  end

  defp execute_phase(state, %Phase{step_type: :agent} = phase) do
    Logger.info("[Orchestrator] Starting agent phase '#{phase.name}' (scope: #{phase.scope})")
    broadcast_event(state, :phase_started, %{phase: phase.name, scope: phase.scope})

    tasks = build_tasks_for_phase(phase, state)
    agent_spec = Slidething.Agent.Config.agent_spec(phase.agent_type)

    pending =
      Enum.reduce(tasks, state.pending_agents, fn task, acc ->
        case start_agent(state.run_id, phase.name, task.agent, task.scope, agent_spec) do
          {:ok, pid} ->
            context = %{
              scope: AgentGenServer.scope_to_json(task.scope),
              task_count: length(tasks)
            }

            AgentGenServer.start_task(pid, task.instruction, context)
            Map.put(acc, pid, {phase.name, task.scope})

          {:error, reason} ->
            Logger.error(
              "[Orchestrator] Failed to start agent for phase '#{phase.name}': #{inspect(reason)}"
            )

            acc
        end
      end)

    started_count = map_size(pending) - map_size(state.pending_agents)

    cond do
      tasks == [] ->
        # No tasks for this phase (e.g., per_element with no elements) — mark complete
        Logger.info("[Orchestrator] Phase '#{phase.name}' has no tasks — skipping")
        %{state | completed_phases: MapSet.put(state.completed_phases, phase.name)}

      started_count == 0 ->
        # All starts failed
        Logger.error("[Orchestrator] All agent starts failed for phase '#{phase.name}'")
        send(self(), {:phase_all_failed, phase.name})
        state

      true ->
        %{
          state
          | pending_agents: pending,
            running_phases: MapSet.put(state.running_phases, phase.name)
        }
    end
  end

  # ── Task building ──────────────────────────────────────────────────────────

  defp build_tasks_for_phase(%Phase{scope: :book} = phase, state) do
    [
      %SubagentTask{
        agent: phase.agent_type,
        scope: :book,
        phase_name: phase.name,
        instruction:
          InstructionBuilder.build(phase, :book, state.prompt, state.phase_context, state.book_id)
      }
    ]
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

  defp build_agent_instruction(phase, {:page, page_id} = scope, state) do
    base =
      InstructionBuilder.build(phase, scope, state.prompt, state.phase_context, state.book_id)

    # For layout, inject element data and format note inline to avoid extra tool calls
    if phase.agent_type == :layout do
      format = Slidething.Book.get_format(@default_format_id)

      format_note =
        if format do
          "Format: #{format.name}, #{format.width}#{format.unit} × #{format.height}#{format.unit}, " <>
            "safe_margin=#{format.safe_margin_mm}mm.\n"
        else
          ""
        end

      elements = Slidething.Element.list(page_id)

      elements_note =
        elements
        |> Enum.map(fn e ->
          content = e[:content] || e["content"] || "(no content)"

          "  {element_id: #{e.id}, type: #{e.element_type}, content: #{inspect(String.slice(to_string(content), 0, 80))}}"
        end)
        |> Enum.join("\n")

      base <>
        "\n\n" <>
        format_note <>
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
      Logger.warning(
        "[Orchestrator] Phase '#{phase_name}' failed, retrying (#{retry_count + 1}/#{max_retries})"
      )

      new_state = %{
        state
        | retry_counts: Map.put(state.retry_counts, phase_name, retry_count + 1),
          running_phases: MapSet.delete(state.running_phases, phase_name)
      }

      if phase do
        {:noreply, execute_phase(new_state, phase)}
      else
        fail_run(new_state, "Phase '#{phase_name}' failed and not found for retry")
      end
    else
      fail_run(
        state,
        "Phase '#{phase_name}' failed after #{retry_count} retries: #{inspect(reason)}"
      )
    end
  end

  # ── Book creation ──────────────────────────────────────────────────────────

  defp ensure_book(%{book_id: nil}) do
    with {:ok, %{book_id: book_id}} <- Slidething.Book.create("Untitled", %{}),
         _ <- Slidething.Book.add_format(book_id, @default_format_id) do
      {:ok, book_id}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp ensure_book(%{book_id: book_id}), do: {:ok, book_id}

  # ── Per-phase lazy page resolution ────────────────────────────────────────

  defp resolve_and_register_page(phase, state) do
    config = phase.config || %{}

    cond do
      page_id = config["page_id"] ->
        if page_id in Map.values(state.page_index_map) do
          {page_id, state}
        else
          idx = map_size(state.page_index_map)
          {page_id, %{state | page_index_map: Map.put(state.page_index_map, idx, page_id)}}
        end

      (idx = config["page_index"]) != nil ->
        case Map.get(state.page_index_map, idx) do
          nil ->
            {:ok, [page_id]} =
              Slidething.Book.create_pages(state.book_id, [
                %{position: idx + 1, metadata: %{}}
              ])

            new_state = %{state | page_index_map: Map.put(state.page_index_map, idx, page_id)}
            {page_id, new_state}

          page_id ->
            {page_id, state}
        end

      true ->
        Logger.warning(
          "[Orchestrator] Phase '#{phase.name}' has no page_index or page_id in config"
        )

        idx = map_size(state.page_index_map)

        {:ok, [page_id]} =
          Slidething.Book.create_pages(state.book_id, [%{position: idx + 1, metadata: %{}}])

        new_state = %{state | page_index_map: Map.put(state.page_index_map, idx, page_id)}
        {page_id, new_state}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp scoped_page_ids(:per_page, state) do
    state.page_index_map |> Map.to_list() |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
  end

  defp scoped_page_ids(:book, _state), do: []

  defp no_pending_agents_for_phase?(state, phase_name) do
    not Enum.any?(state.pending_agents, fn {_pid, {pname, _}} -> pname == phase_name end)
  end

  defp find_phase(state, phase_name) do
    state.generated_plan && Enum.find(state.generated_plan.phases, &(&1.name == phase_name))
  end

  defp start_agent(run_id, phase_name, agent_type, scope, spec) do
    opts = [
      run_id: run_id,
      phase_name: phase_name,
      agent_type: agent_type,
      scope: scope,
      orchestrator_pid: self(),
      agent_spec: spec
    ]

    DynamicSupervisor.start_child(Slidething.RunSupervisor, {AgentGenServer, opts})
  end

  defp derive_image_subject(elements) do
    title = find_text_content(elements, "title")
    body = find_text_content(elements, "text")

    cond do
      title && body -> "#{title} — #{body}"
      title -> title
      body -> body
      true -> nil
    end
  end

  defp find_text_content(elements, type) do
    case Enum.find(elements, &(&1.element_type == type)) do
      nil ->
        nil

      el ->
        content = el[:content] || el["content"]
        if content && content != "", do: String.slice(to_string(content), 0, 200), else: nil
    end
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
    task =
      Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
        run_planner_phases(state)
      end)

    broadcast_event(state, :phase_started, %{phase: :initial_planning})
    task.ref
  end

  defp run_planner_phases(state) do
    mode = planner_mode(state)
    static_context = build_static_context(state)

    # Phase A: Decide — check if context gathering is needed
    needs_context =
      if is_nil(state.book_id) do
        false
      else
        run_decide_phase(static_context)
      end

    Logger.debug("[Planner] Phase A (decide): needs_context=#{needs_context}")

    # Phase B: Gather — collect detailed context if needed
    gathered_context =
      if needs_context do
        run_gather_phase(mode, static_context)
      else
        ""
      end

    Logger.debug("[Planner] Phase B (gather): completed")

    # Phase C: Condense — compress large gathered context before emit
    gathered_context = condense_context(gathered_context)

    # Phase D: Emit — generate the plan using submit_plan
    emit_prompt = build_emit_prompt(static_context, gathered_context)
    run_emit_phase(mode, emit_prompt)
  end

  defp build_static_context(state) do
    parts = ["User request: #{state.prompt}"]

    parts =
      if state.book_id do
        case Slidething.Book.get(state.book_id) do
          {:ok, book} ->
            meta = book.metadata || %{}
            theme = meta["theme"] || meta[:theme]
            audience = meta["target_audience"] || meta[:target_audience]
            lines = ["Existing book:", "  id: #{state.book_id}", "  title: #{book.title}"]
            lines = if theme, do: lines ++ ["  theme: #{theme}"], else: lines
            lines = if audience, do: lines ++ ["  target_audience: #{audience}"], else: lines
            parts ++ [Enum.join(lines, "\n")]

          _ ->
            parts
        end
      else
        parts
      end

    parts =
      case state.target_type do
        "page" when not is_nil(state.target_id) ->
          page_id = state.target_id
          elements = Slidething.Element.list(page_id)

          elements_text =
            if elements == [] do
              "  (no elements yet)"
            else
              Enum.map_join(elements, "\n", fn el ->
                content = el[:content] || el["content"] || "(no content)"
                "  [#{el.element_type}] #{el.id}: #{String.slice(to_string(content), 0, 100)}"
              end)
            end

          parts ++ ["Target page: #{page_id}\nExisting elements:\n#{elements_text}"]

        "element" when not is_nil(state.target_id) ->
          element_info =
            case Slidething.Element.get(state.target_id) do
              {:ok, el} -> "Target element: #{state.target_id} (type: #{el.element_type})"
              _ -> "Target element: #{state.target_id}"
            end

          parts ++ [element_info]

        _ ->
          parts
      end

    Enum.join(parts, "\n\n")
  end

  defp run_decide_phase(static_context) do
    spec = Slidething.Agent.Config.agent_spec(:planner_decide)

    case Slidething.LLM.Client.complete_json(spec, [
           %Message{role: :system, content: spec.system_prompt},
           %Message{role: :user, content: static_context}
         ]) do
      {:final_response, text} ->
        case Jason.decode(text) do
          {:ok, %{"needs_context" => v}} when is_boolean(v) -> v
          _ -> true
        end

      _ ->
        true
    end
  end

  defp run_gather_phase(mode, static_context) do
    base_spec = Slidething.Agent.Config.agent_spec(:planner_gather)
    spec = %{base_spec | tools: gather_tools_for_mode(mode)}

    messages = [
      %Message{role: :system, content: spec.system_prompt},
      %Message{role: :user, content: static_context}
    ]

    case run_gather_loop(spec, messages) do
      {:final_response, summary_text} -> summary_text
      {:error, _reason} -> ""
      _ -> ""
    end
  end

  defp run_gather_loop(spec, messages) do
    case Slidething.LLM.Client.complete_json(spec, messages) do
      {:final_response, text} ->
        {:final_response, text}

      {:tool_requests, calls} ->
        results =
          Enum.map(calls, fn %ToolCall{call_id: id, tool: t, args: a} ->
            %{Slidething.Tool.Registry.execute(t, a) | call_id: id}
          end)

        assistant_msg = %Message{role: :assistant, content: "", tool_calls: calls}
        tool_msg = %Message{role: :tool, tool_results: results}
        run_gather_loop(spec, messages ++ [assistant_msg, tool_msg])

      {:error, _} = err ->
        err
    end
  end

  defp build_emit_prompt(static_context, gathered_context) do
    parts = [static_context]

    parts =
      if gathered_context != "",
        do: parts ++ ["\nGathered context:\n" <> gathered_context],
        else: parts

    Enum.join(parts, "\n\n")
  end

  defp condense_context(text) when byte_size(text) <= 3000, do: text

  defp condense_context(text) do
    Logger.info("[Planner] Condensing context (#{byte_size(text)} bytes)")

    spec = Slidething.Agent.Config.agent_spec(:planner_summarize)

    case Slidething.LLM.Client.complete_json(spec, [
           %Message{role: :system, content: spec.system_prompt},
           %Message{role: :user, content: text}
         ]) do
      {:final_response, summary} when is_binary(summary) and byte_size(summary) > 0 ->
        Logger.info("[Planner] Context condensed to #{byte_size(summary)} bytes")
        summary

      _ ->
        text
    end
  end

  defp planner_mode(%{book_id: nil}), do: :create_book
  defp planner_mode(%{target_type: "page", target_id: t}) when not is_nil(t), do: :edit_page
  defp planner_mode(%{target_type: "element", target_id: t}) when not is_nil(t), do: :edit_element
  defp planner_mode(_), do: :edit_book

  defp gather_tools_for_mode(:edit_element), do: [:get_element, :get_recent_prompts]
  defp gather_tools_for_mode(_), do: [:get_outline, :get_page_elements, :get_recent_prompts]

  defp emit_scope_constraint(:edit_page) do
    "\n\nSCOPE CONSTRAINT: This run targets a specific page. For content and media phases, use scope \"book\" with \"page_id\" in config pointing to the target page. For layout and validator phases, use scope \"per_page\"."
  end

  defp emit_scope_constraint(:edit_element) do
    "\n\nSCOPE CONSTRAINT: This run targets a specific element. For content and media phases, use scope \"book\" with \"page_id\" and \"element_id\" in config. For layout and validator phases, use scope \"per_page\"."
  end

  defp emit_scope_constraint(_), do: ""

  defp run_emit_phase(mode, emit_prompt) do
    spec = Slidething.Agent.Config.agent_spec(:planner_emit)
    system_prompt = spec.system_prompt <> emit_scope_constraint(mode)

    messages = [
      %Message{role: :system, content: system_prompt},
      %Message{role: :user, content: emit_prompt}
    ]

    case do_emit_call(spec, messages) do
      {:final_response, plan} when is_map(plan) ->
        {:final_response, plan}

      {:final_response, text} when is_binary(text) ->
        Logger.debug("[Planner] Emit returned text, retrying with tool nudge")

        retry_messages =
          messages ++
            [
              %Message{role: :assistant, content: text},
              %Message{
                role: :user,
                content:
                  "You must call the submit_plan tool. Do not write text — call submit_plan now with your execution plan."
              }
            ]

        case do_emit_call(spec, retry_messages) do
          {:final_response, plan} when is_map(plan) ->
            {:final_response, plan}

          {:final_response, text2} when is_binary(text2) ->
            {:error,
             "emit phase returned text instead of submit_plan: #{String.slice(text2, 0, 100)}"}

          other ->
            other
        end

      other ->
        other
    end
  end

  defp do_emit_call(spec, messages) do
    case Slidething.LLM.Client.complete_json(spec, messages) do
      {:tool_requests, calls} ->
        Enum.each(calls, fn %ToolCall{tool: t, args: a} ->
          Logger.debug("[Planner] Emit tool call: #{t} args=#{inspect(a, limit: 3000)}")
        end)

        results =
          Enum.map(calls, fn %ToolCall{call_id: id, tool: t, args: a} ->
            %{Slidething.Tool.Registry.execute(t, a) | call_id: id}
          end)

        case Enum.find(results, &(&1.tool == :submit_plan)) do
          %{success: true, data: plan_data} ->
            {:final_response, plan_data}

          %{success: false, error: error} ->
            {:error, "submit_plan failed: #{error}"}

          nil ->
            {:error, "emit phase did not call submit_plan"}
        end

      {:final_response, text} ->
        {:final_response, text}

      {:error, _} = err ->
        err
    end
  end

  # Mid-execution planner step loop (for coordinator/repair phases)
  defp run_planner_step_loop(spec, messages) do
    case Slidething.LLM.Client.complete_json(spec, messages) do
      {:final_response, json} ->
        {:final_response, json}

      {:tool_requests, calls} ->
        results =
          Enum.map(calls, fn %ToolCall{call_id: id, tool: t, args: a} ->
            %{Slidething.Tool.Registry.execute(t, a) | call_id: id}
          end)

        case Enum.find(results, &(&1.tool == :submit_plan)) do
          %{success: true, data: plan_data} ->
            {:final_response, plan_data}

          nil ->
            assistant_msg = %Message{role: :assistant, content: "", tool_calls: calls}
            tool_msg = %Message{role: :tool, tool_results: results}
            run_planner_step_loop(spec, messages ++ [assistant_msg, tool_msg])

          %{success: false, error: error} ->
            {:error, "submit_plan failed: #{error}"}
        end

      {:error, _} = err ->
        err
    end
  end

  defp parse_and_validate_plan(plan_data) when is_map(plan_data) do
    try do
      with plan = GeneratedPlan.from_map(plan_data),
           :ok <- PlanValidator.validate_plan!(plan.phases) do
        {:ok, plan}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp parse_and_validate_plan(json_text) when is_binary(json_text) do
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

  defp parse_and_validate_plan(other) do
    {:error, "Invalid plan data: #{inspect(other)}"}
  end

  defp parse_json_loosely(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, decoded} -> decoded
      _ -> %{"raw" => text}
    end
  end

  defp parse_json_loosely(other), do: other

  defp parse_json_loosely_result(text) when is_binary(text) do
    Jason.decode(text)
  end

  # ── Run completion / failure ───────────────────────────────────────────────

  defp complete_run(state) do
    Logger.info("[Orchestrator] Run #{state.run_id} completed")

    page_ids = scoped_page_ids(:per_page, state)
    page_count = length(page_ids)

    issues =
      Enum.flat_map(page_ids, &Slidething.Validator.Layout.validate(&1, @default_format_id))

    state =
      if issues != [] do
        broadcast_event(state, :validation_issues, %{
          phase: "auto_layout_validation",
          issues: Enum.map(issues, &issue_to_map/1)
        })

        %{
          state
          | validation_issues: Map.put(state.validation_issues, "auto_layout_validation", issues)
        }
      else
        state
      end

    new_state = %{state | status: :done, completed_at: DateTime.utc_now()}
    Slidething.Prompt.complete(state.run_id, "completed #{page_count} page(s)")

    broadcast_event(new_state, :completed, %{
      duration_ms: DateTime.diff(new_state.completed_at, state.started_at, :millisecond),
      pages: page_count
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
