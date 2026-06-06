defmodule Slidething.Agent.API do
  @moduledoc """
  Public API for the agentic system.

  This module provides the main interface for starting and managing agent runs.
  """

  alias Slidething.Agent.Orchestrator
  alias Slidething.Agent.GenServer, as: AgentGenServer

  @doc """
  Start a new agent run.

  Optional target_type and target_id scope the run to a specific page or
  element. When `book_id` is provided, a row is recorded in `prompts` and
  the returned run_id is the prompt id. When `book_id` is nil (e.g.
  from tests that bypass the controller path) a UUID is generated and
  no prompt row is written.

  Returns {:ok, run_id} on success.
  """
  def start_run(prompt, book_id \\ nil, target_type \\ nil, target_id \\ nil) do
    run_id =
      if book_id do
        Slidething.Prompt.start_run(book_id, prompt,
          target_type: target_type,
          target_id: target_id
        )
      else
        Ecto.UUID.generate()
      end

    opts = [run_id: run_id, target_type: target_type, target_id: target_id]

    case DynamicSupervisor.start_child(
           Slidething.RunSupervisor,
           {Orchestrator, opts}
         ) do
      {:ok, pid} ->
        Orchestrator.start_run(pid, prompt, book_id, target_type, target_id)
        {:ok, run_id}

      {:error, reason} ->
        if book_id, do: Slidething.Prompt.fail(run_id, reason)
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
      {{{:"$1", :"$2", :"$3"}, :"$4", :_}, [{:==, :"$1", run_id}], [{{:"$2", :"$3", :"$4"}}]}
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
  Subscribe to all events (orchestrator and agent) for a specific run.

  Subscribers receive `{:run_event, %{...}}` from the orchestrator and
  `{:agent_event, %{...}}` from agent processes on the same topic.
  """
  def subscribe(run_id) do
    Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")
  end

  @doc false
  def subscribe_to_run(run_id), do: subscribe(run_id)

  @doc false
  def subscribe_to_agent_events(run_id), do: subscribe(run_id)

  @doc """
  List all active runs.
  """
  def list_runs() do
    Registry.select(Slidething.RunRegistry, [
      {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end
end
