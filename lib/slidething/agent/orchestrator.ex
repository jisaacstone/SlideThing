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

  alias Slidething.Agent.{AgentSpec, RunPlan, SubagentTask}
  alias Slidething.Agent.GenServer, as: AgentGenServer

  defstruct [
    :run_id,
    :book_id,
    :prompt,
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
    GenServer.cast(pid, {:start_run, prompt, book_id})
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
  def handle_cast({:start_run, prompt, book_id}, state) do
    Logger.info("[Orchestrator] Starting run: #{state.run_id}")

    new_state = %{
      state
      | prompt: prompt,
        book_id: book_id,
        status: :planning,
        phase: :planner
    }

    broadcast_event(new_state, :started, %{prompt: prompt, book_id: book_id})

    start_planner(new_state)
    {:noreply, new_state}
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

    new_state = %{state | status: :failed}
    broadcast_event(new_state, :failed, %{reason: reason, agent: agent_pid})

    {:noreply, new_state}
  end

  # Private functions

  defp start_planner(state) do
    planner_spec = %AgentSpec{
      name: :planner,
      provider: "mock",
      model: "mock-model",
      temperature: 0.2,
      max_tokens: 2000,
      max_iterations: 5,
      system_prompt: "You are a planner agent.",
      tools: [:mock_get_book]
    }

    {:ok, pid} =
      start_agent(
        state.run_id,
        :planner,
        :book,
        planner_spec
      )

    AgentGenServer.start_task(pid, "Plan: #{state.prompt}", %{})

    new_state = %{state | pending_agents: Map.put(state.pending_agents, pid, :planner)}
    broadcast_event(new_state, :phase_started, %{phase: :planner})
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

  defp process_phase_results(%{phase: :planner} = state) do
    results = Map.values(state.agent_results)

    case results do
      [{:final, plan_text} | _] ->
        Logger.info("[Orchestrator] Planner completed: #{plan_text}")

        plan = %RunPlan{
          intent: plan_text,
          tasks: [
            %SubagentTask{agent: :content, scope: :book, instruction: "Create book content"}
          ]
        }

        new_state = %{state | plan: plan, status: :executing, phase: :content}
        broadcast_event(new_state, :phase_completed, %{phase: :planner, plan: plan})

        start_content_agents(new_state)

      _ ->
        Logger.error("[Orchestrator] Unexpected planner result")
        %{state | status: :failed}
    end
  end

  defp process_phase_results(%{phase: :content} = state) do
    Logger.info("[Orchestrator] Content phase completed")

    new_state = %{state | status: :validating}
    broadcast_event(new_state, :phase_completed, %{phase: :content})

    run_validation(new_state)
  end

  defp process_phase_results(state) do
    Logger.info("[Orchestrator] Phase #{state.phase} completed")
    state
  end

  defp start_content_agents(state) do
    content_spec = %AgentSpec{
      name: :content,
      provider: "mock",
      model: "mock-model",
      temperature: 0.7,
      max_tokens: 4000,
      max_iterations: 10,
      system_prompt: "You are a content agent.",
      tools: [:mock_create_element]
    }

    tasks = state.plan.tasks

    pending =
      Enum.reduce(tasks, %{}, fn task, acc ->
        {:ok, pid} = start_agent(state.run_id, task.agent, task.scope, content_spec)
        AgentGenServer.start_task(pid, task.instruction, %{})
        Map.put(acc, pid, task)
      end)

    new_state = %{state | pending_agents: pending, agent_results: %{}}
    broadcast_event(new_state, :phase_started, %{phase: :content, task_count: length(tasks)})
    new_state
  end

  defp run_validation(state) do
    Logger.info("[Orchestrator] Running validation")
    broadcast_event(state, :validation_started, %{})

    issues = []

    if length(issues) > 0 and state.repair_count < state.max_repairs do
      new_state = %{
        state
        | status: :repairing,
          validation_issues: issues,
          repair_count: state.repair_count + 1
      }

      broadcast_event(new_state, :validation_failed, %{issues: issues})
      start_repair(new_state)
    else
      complete_run(state)
    end
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

    broadcast_event(new_state, :completed, %{
      duration_ms: DateTime.diff(new_state.completed_at, state.started_at, :millisecond)
    })

    new_state
  end

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
      "run_events:#{state.run_id}",
      {:run_event, event}
    )
  end
end
