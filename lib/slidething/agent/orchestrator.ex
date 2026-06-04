defmodule Slidething.Agent.Orchestrator do
  @moduledoc """
  Coordinates a single agent run through multiple phases.

  The orchestrator:
  - Manages the state machine (planning → executing → validating → done)
  - Starts agent processes as needed
  - Collects results from agents
  - Applies patches deterministically
  - Broadcasts events for monitoring
  - Never blocks on IO (all async)
  """

  use GenServer
  require Logger

  alias Slidething.Agent.{RunPlan, SubagentTask}
  alias Slidething.Agent.GenServer, as: AgentGenServer

  @default_format_id "format-web"

  defstruct [
    :run_id,
    :book_id,
    :prompt,
    :target_type,
    :target_id,
    :status,
    :phase,
    :plan,
    :pending_agents,
    :agent_results,
    :validation_issues,
    :repair_count,
    :max_repairs,
    :started_at,
    :completed_at
  ]

  @type t :: %__MODULE__{
          run_id: String.t(),
          book_id: String.t() | nil,
          prompt: String.t(),
          target_type: String.t() | nil,
          target_id: String.t() | nil,
          status: :idle | :planning | :executing | :validating | :repairing | :done | :failed,
          phase: :planner | :research | :content | :media | :layout | nil,
          plan: RunPlan.t() | nil,
          pending_agents: %{pid() => SubagentTask.t()},
          agent_results: %{pid() => term()},
          validation_issues: [ValidationIssue.t()],
          repair_count: integer(),
          max_repairs: integer(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }

  # Client API

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = via_tuple(run_id)
    GenServer.start_link(__MODULE__, opts, name: name)
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
      book_id: nil,
      prompt: nil,
      target_type: Keyword.get(opts, :target_type),
      target_id: Keyword.get(opts, :target_id),
      status: :idle,
      phase: nil,
      plan: nil,
      pending_agents: %{},
      agent_results: %{},
      validation_issues: [],
      repair_count: 0,
      max_repairs: 3,
      started_at: DateTime.utc_now(),
      completed_at: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_run, prompt, book_id, target_type, target_id}, _from, state) do
    Logger.info("[Orchestrator] Starting run: #{state.run_id}")

    new_state = %{
      state
      | prompt: prompt,
        book_id: book_id,
        target_type: target_type,
        target_id: target_id,
        status: :planning,
        phase: :planner
    }

    broadcast_event(new_state, :started, %{prompt: prompt, book_id: book_id})

    start_planner(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:agent_done, agent_pid, _result}, %{status: :failed} = state) do
    Logger.warning("[Orchestrator] Ignoring agent_done from #{inspect(agent_pid)} - orchestrator already failed")
    {:noreply, state}
  end

  @impl true
  def handle_info({:agent_done, agent_pid, result}, state) do
    Logger.info("[Orchestrator] Agent completed: #{inspect(agent_pid)}")

    new_state = collect_agent_result(state, agent_pid, result)

    if all_agents_done?(new_state) do
      new_state = process_phase_results(new_state)
      {:noreply, new_state}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:agent_failed, agent_pid, reason}, state) do
    Logger.error("[Orchestrator] Agent failed: #{inspect(agent_pid)} - #{inspect(reason)}")

    new_state = %{state | status: :failed, completed_at: DateTime.utc_now()}
    Slidething.Prompt.fail(state.run_id, reason)
    broadcast_event(new_state, :failed, %{reason: inspect(reason), agent: inspect(agent_pid)})

    {:noreply, new_state}
  end

  # Private functions — Phase processing

  defp process_phase_results(%{phase: :planner} = state) do
    results = Map.values(state.agent_results)

    case results do
      [{:final, plan_text} | _] ->
        Logger.info("[Orchestrator] Planner completed: #{String.slice(plan_text, 0, 200)}")

        book_id = state.book_id || extract_book_id_from_plan(plan_text)
        tasks = build_content_tasks_from_planner(plan_text, book_id, state.prompt)

        plan = %RunPlan{
          intent: plan_text,
          tasks: tasks
        }

        new_state = %{
          state
          | plan: plan,
            book_id: book_id,
            status: :executing,
            phase: :content
        }

        broadcast_event(new_state, :phase_completed, %{phase: :planner, task_count: length(tasks)})

        start_content_agents(new_state)

      _ ->
        Logger.error("[Orchestrator] Unexpected planner result")
        %{state | status: :failed}
    end
  end

  defp process_phase_results(%{phase: :content} = state) do
    Logger.info("[Orchestrator] Content phase completed")
    broadcast_event(state, :phase_completed, %{phase: :content})

    tasks = build_layout_tasks(state)

    if tasks == [] do
      Logger.info("[Orchestrator] No layout tasks — skipping layout phase")
      process_phase_results(%{state | status: :executing, phase: :media})
    else
      start_layout_agents(%{state | status: :executing, phase: :layout}, tasks)
    end
  end

  defp process_phase_results(%{phase: :layout} = state) do
    Logger.info("[Orchestrator] Layout phase completed")
    broadcast_event(state, :phase_completed, %{phase: :layout})

    process_phase_results(%{state | status: :executing, phase: :media})
  end

  defp process_phase_results(%{phase: :media} = state) do
    tasks = build_media_tasks(state)

    if tasks == [] do
      Logger.info("[Orchestrator] No media tasks — skipping media phase")
      run_validation(%{state | status: :validating})
    else
      start_media_agents(state, tasks)
    end
  end

  defp process_phase_results(state) do
    Logger.info("[Orchestrator] Phase #{state.phase} completed — transitioning to validation")
    run_validation(state)
  end

  defp extract_book_id_from_plan(plan_text) do
    json =
      case extract_json_from_markdown(plan_text) do
        {:ok, decoded} -> {:ok, decoded}
        :error -> Jason.decode(plan_text)
      end

    case json do
      {:ok, %{"book_id" => book_id}} when is_binary(book_id) -> book_id
      _ -> nil
    end
  end

  # Private functions — Planner helpers

  defp build_content_tasks_from_planner(plan_text, book_id, original_prompt) do
    json =
      case extract_json_from_markdown(plan_text) do
        {:ok, decoded} -> {:ok, decoded}
        :error -> Jason.decode(plan_text)
      end

    page_plans =
      case json do
        {:ok, pages} when is_list(pages) -> pages
        {:ok, %{"pages" => pages}} when is_list(pages) -> pages
        _ -> nil
      end

    case page_plans do
      [_ | _] ->
        Enum.map(page_plans, fn pp ->
          page_id = pp["page_id"]
          desc = pp["description"] || pp["text"] || original_prompt

          %SubagentTask{
            agent: :content,
            scope: {:page, page_id},
            instruction: "User request: \"#{original_prompt}\"\nCreate content for page #{page_id}: #{desc}"
          }
        end)

      _ ->
        build_content_tasks_from_book(book_id, plan_text)
    end
  end

  defp extract_json_from_markdown(text) do
    case Regex.run(~r/```(?:json)?\s*\n(.+?)\n```/s, text) do
      [_, captured] -> Jason.decode(String.trim(captured))
      nil -> :error
    end
  end

  defp build_content_tasks_from_book(nil, _plan_text) do
    Logger.error("[Orchestrator] Cannot build content tasks — no book_id")
    []
  end

  defp build_content_tasks_from_book(book_id, plan_text) do
    case Slidething.Book.get_outline(book_id) do
      {:ok, pages} when pages != [] ->
        Enum.map(pages, fn p ->
          desc = Map.get(p.metadata, "description", "") || p.metadata["description"] || ""

          %SubagentTask{
            agent: :content,
            scope: {:page, p.id},
            instruction: "Create content for page #{p.id} (#{p.position}/#{length(pages)}). #{desc}"
          }
        end)

      _ ->
        [
          %SubagentTask{
            agent: :content,
            scope: :book,
            instruction: "Create book content: #{String.slice(plan_text, 0, 200)}"
          }
        ]
    end
  end

  defp start_layout_agents(state, tasks) do
    layout_spec = Slidething.Agent.Config.agent_spec(:layout)

    pending =
      Enum.reduce(tasks, %{}, fn task, acc ->
        {:ok, pid} = start_agent(state.run_id, task.agent, task.scope, layout_spec)

        context = %{
          scope: AgentGenServer.scope_to_json(task.scope),
          task_count: length(tasks),
          format_id: @default_format_id
        }

        AgentGenServer.start_task(pid, task.instruction, context)
        Map.put(acc, pid, task)
      end)

    new_state = %{state | pending_agents: pending, agent_results: %{}}
    broadcast_event(new_state, :phase_started, %{phase: :layout, task_count: length(tasks)})
    new_state
  end

  defp build_layout_tasks(%{plan: nil}), do: []
  defp build_layout_tasks(%{book_id: nil}), do: []

  defp build_layout_tasks(state) do
    format = Slidething.Book.get_format(@default_format_id)

    format_note =
      if format do
        "Format: #{format.name}, #{format.width}#{format.unit} × #{format.height}#{format.unit}, " <>
          "safe_margin=#{format.safe_margin_mm}mm. "
      else
        ""
      end

    state.plan.tasks
    |> Enum.flat_map(fn
      %{scope: {:page, page_id}} -> [page_id]
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.map(fn page_id ->
      elements = Slidething.Element.list(page_id)

      elements_note =
        elements
        |> Enum.map(fn e ->
          content =
            case e.latest_version do
              %{content: c} when is_binary(c) -> String.slice(c, 0, 80)
              _ -> "(no content)"
            end

          "  {element_id: #{e.id}, type: #{e.element_type}, content: #{inspect(content)}}"
        end)
        |> Enum.join("\n")

      %SubagentTask{
        agent: :layout,
        scope: {:page, page_id},
        instruction:
          "Lay out elements on page #{page_id} for format \"#{@default_format_id}\".\n" <>
            format_note <>
            "Page elements:\n#{elements_note}\n" <>
            "Call propose_layout with page_id=#{page_id}, format_id=\"#{@default_format_id}\", " <>
            "and one entry per element with x, y, width, height as fractions in 0..1. " <>
            "Do NOT call get_page_elements or get_format — the data is already above."
      }
    end)
  end

  defp start_media_agents(state, tasks) do
    media_spec = Slidething.Agent.Config.agent_spec(:media)

    pending =
      Enum.reduce(tasks, %{}, fn task, acc ->
        {:ok, pid} = start_agent(state.run_id, task.agent, task.scope, media_spec)

        context = %{
          scope: AgentGenServer.scope_to_json(task.scope),
          task_count: length(tasks)
        }

        AgentGenServer.start_task(pid, task.instruction, context)
        Map.put(acc, pid, task)
      end)

    new_state = %{state | pending_agents: pending, agent_results: %{}}
    broadcast_event(new_state, :phase_started, %{phase: :media, task_count: length(tasks)})
    new_state
  end

  defp build_media_tasks(%{plan: nil}), do: []
  defp build_media_tasks(%{book_id: nil}), do: []

  defp build_media_tasks(state) do
    state.plan.tasks
    |> Enum.flat_map(fn
      %{scope: {:page, page_id}} -> [page_id]
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn page_id ->
      layout = fetch_layout(page_id)
      elements_by_id = page_id |> Slidething.Element.list() |> Map.new(&{&1.id, &1})

      page_id
      |> media_elements_for_page(layout, elements_by_id)
      |> Enum.map(fn {element, aspect} ->
        content = (element.latest_version && element.latest_version.content) || ""

        %SubagentTask{
          agent: :media,
          scope: {:element, element.id},
          instruction:
            "Generate an image for element #{element.id} at aspect ratio #{aspect}. " <>
              "Description: #{content}. " <>
              "Call generate_image with prompt and aspect_ratio=\"#{aspect}\", then call " <>
              "store_asset with the returned asset_path and the original prompt."
        }
      end)
    end)
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

  # Private functions — Agent lifecycle

  defp start_planner(state) do
    planner_spec =
      Slidething.Agent.Config.agent_spec(:planner)
      |> narrow_planner_spec(state)

    {:ok, pid} =
      start_agent(
        state.run_id,
        :planner,
        :book,
        planner_spec
      )

    task = planner_task(state.prompt, state.book_id, state.target_type, state.target_id)
    AgentGenServer.start_task(pid, task, %{})

    new_state = %{state | pending_agents: Map.put(state.pending_agents, pid, :planner)}
    broadcast_event(new_state, :phase_started, %{phase: :planner})
    new_state
  end

  defp narrow_planner_spec(spec, state) do
    remove =
      []
      |> then(fn r -> if state.book_id, do: r ++ [:create_book], else: r end)
      |> then(fn r -> if state.target_type in ["page", "element"], do: r ++ [:create_pages], else: r end)

    %{spec | tools: spec.tools -- remove}
  end

  defp planner_task(prompt, nil, _target_type, _target_id) do
    "Plan: #{prompt}"
  end

  defp planner_task(prompt, book_id, "page", page_id) do
    context = load_page_context(page_id)

    "Plan: #{prompt}\n\nIMPORTANT CONTEXT: A book already exists (book_id: \"#{book_id}\"). " <>
      "You are editing an EXISTING page (page_id: #{page_id}). DO NOT create new pages — " <>
      "return a plan for the target page only.#{context}"
  end

  defp planner_task(prompt, book_id, "element", element_id) do
    context = load_element_context(element_id)

    "Plan: #{prompt}\n\nIMPORTANT CONTEXT: A book already exists (book_id: \"#{book_id}\"). " <>
      "You are editing an EXISTING element (element_id: #{element_id}). DO NOT create new pages.#{context}"
  end

  defp planner_task(prompt, book_id, _target_type, _target_id) do
    "Plan: #{prompt}\n\nIMPORTANT CONTEXT: A book already exists with book_id \"#{book_id}\". " <>
      "DO NOT create a new book. Instead, use get_book with the book_id to inspect the existing book, " <>
      "then use create_pages as needed."
  end

  defp load_page_context(page_id) do
    case Slidething.Book.get_page(page_id) do
      {:ok, page} ->
        elements = Slidething.Element.list(page_id)
        elem_text =
          if elements == [] do
            " (no elements yet)"
          else
            "\n" <> (Enum.map(elements, fn e ->
              content = Map.get(e.latest_version || %{}, :content, "")
              "- #{e.element_type}: \"#{String.slice(content || "", 0, 200)}\""
            end) |> Enum.join("\n"))
          end

        "\n\nCURRENT PAGE (page_id: #{page_id}, position: #{page.position}):#{elem_text}"

      {:error, _} ->
        ""
    end
  end

  defp load_element_context(element_id) do
    case Slidething.Element.get(element_id) do
      {:ok, elem} ->
        latest = List.last(elem.versions)
        content = (latest && latest.content) || ""
        "\n\nCURRENT ELEMENT (element_id: #{element_id}, type: #{elem.element_type}): \"#{String.slice(content, 0, 200)}\""

      {:error, _} ->
        ""
    end
  end

  defp start_content_agents(state) do
    content_spec = Slidething.Agent.Config.agent_spec(:content)

    tasks = state.plan.tasks

    pending =
      Enum.reduce(tasks, %{}, fn task, acc ->
        {:ok, pid} = start_agent(state.run_id, task.agent, task.scope, content_spec)

        context = %{
          scope: AgentGenServer.scope_to_json(task.scope),
          task_count: length(tasks)
        }

        AgentGenServer.start_task(pid, task.instruction, context)
        Map.put(acc, pid, task)
      end)

    new_state = %{state | pending_agents: pending, agent_results: %{}}
    broadcast_event(new_state, :phase_started, %{phase: :content, task_count: length(tasks)})
    new_state
  end

  defp start_agent(run_id, agent_type, scope, spec) do
    opts = [
      run_id: run_id,
      agent_type: agent_type,
      scope: scope,
      orchestrator_pid: self(),
      agent_spec: spec
    ]

    DynamicSupervisor.start_child(
      Slidething.RunSupervisor,
      {AgentGenServer, opts}
    )
  end

  defp collect_agent_result(state, agent_pid, result) do
    %{
      state
      | agent_results: Map.put(state.agent_results, agent_pid, result),
        pending_agents: Map.delete(state.pending_agents, agent_pid)
    }
  end

  defp all_agents_done?(state) do
    map_size(state.pending_agents) == 0
  end

  # Private functions — Validation and completion

  defp run_validation(state) do
    Logger.info("[Orchestrator] Running validation")
    broadcast_event(state, :validation_started, %{})

    touched = touched_page_ids(state)
    issues = Enum.flat_map(touched, &Slidething.Validator.Layout.validate(&1, @default_format_id))

    if length(issues) > 0 and state.repair_count < state.max_repairs do
      new_state = %{
        state
        | status: :repairing,
          validation_issues: issues,
          repair_count: state.repair_count + 1
      }

      broadcast_event(new_state, :validation_failed, %{issues: Enum.map(issues, &issue_to_map/1)})
      start_repair(new_state)
    else
      complete_run(state)
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

  defp touched_page_ids(%{plan: nil}), do: []

  defp touched_page_ids(%{plan: %{tasks: tasks}}) do
    tasks
    |> Enum.flat_map(fn
      %{scope: {:page, id}} -> [id]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp start_repair(state) do
    Logger.info("[Orchestrator] Starting repair cycle #{state.repair_count}")
    state
  end

  defp complete_run(state) do
    Logger.info("[Orchestrator] Run completed successfully")

    new_state = %{
      state
      | status: :done,
        completed_at: DateTime.utc_now()
    }

    Slidething.Prompt.complete(state.run_id, summarize(new_state))

    broadcast_event(new_state, :completed, %{
      duration_ms: DateTime.diff(new_state.completed_at, state.started_at, :millisecond)
    })

    new_state
  end

  defp summarize(%{plan: nil}), do: "completed"
  defp summarize(%{plan: %{tasks: tasks}}), do: "completed #{length(tasks)} task(s)"

  # Private functions — Event broadcasting

  defp broadcast_event(state, event_type, data) do
    event = %{
      run_id: state.run_id,
      event: event_type,
      status: state.status,
      phase: state.phase,
      data: data,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Slidething.PubSub,
      "events:#{state.run_id}",
      {:run_event, event}
    )
  end
end
