defmodule Slidething.Agent.API do
  @moduledoc """
  Public API for the agentic system.

  This module provides the main interface for starting and managing agent runs.
  """

  alias Slidething.Agent.Orchestrator
  alias Slidething.Agent.GenServer, as: AgentGenServer

  @doc """
  Start a new agent run.

  Returns {:ok, run_id} on success.
  """
  def start_run(prompt, book_id \\ nil) do
    run_id = generate_run_id()

    opts = [run_id: run_id]

    case DynamicSupervisor.start_child(
           Slidething.RunSupervisor,
           {Orchestrator, opts}
         ) do
      {:ok, pid} ->
        Orchestrator.start_run(pid, prompt, book_id)
        {:ok, run_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the status of a run.

  Returns the orchestrator state or :not_found.
  """
  def get_run_status(run_id) do
    case Registry.lookup(Slidething.RunRegistry, run_id) do
      [{pid, _}] ->
        Orchestrator.get_state(pid)

      [] ->
        :not_found
    end
  end

  @doc """
  Get all running agent processes for a run.

  Returns a list of {agent_type, scope, pid} tuples.
  """
  def get_agents(run_id) do
    Registry.select(Slidething.AgentRegistry, [
      {{{:"$1", :"$2", :"$3"}, :"$4", :_}, [{:==, :"$1", run_id}],
       [{{:"$2", :"$3", :"$4"}}]}
    ])
  end

  @doc """
  Get the state of a specific agent.
  """
  def get_agent_state(run_id, agent_type, scope \\ nil) do
    case Registry.lookup(Slidething.AgentRegistry, {run_id, agent_type, scope}) do
      [{pid, _}] ->
        AgentGenServer.get_state(pid)

      [] ->
        :not_found
    end
  end

  @doc """
  Subscribe to events for a specific run.
  """
  def subscribe_to_run(run_id) do
    Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")
  end

  @doc """
  Subscribe to agent events for a specific run.
  """
  def subscribe_to_agent_events(run_id) do
    Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:#{run_id}")
  end

  @doc """
  Subscribe to all agent events (for monitoring dashboard).
  """
  def subscribe_to_all_agent_events() do
    Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:all")
  end

  @doc """
  List all active runs.
  """
  def list_runs() do
    Registry.select(Slidething.RunRegistry, [
      {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  defp generate_run_id() do
    "run_#{:rand.uniform(1_000_000)}"
  end
end
