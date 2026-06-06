defmodule Slidething.Agent.JsonSafetyTest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.AgentSpec
  alias Slidething.Agent.GenServer, as: AgentGenServer

  setup do
    run_id = "json_test_#{System.unique_integer([:positive])}"
    {:ok, %{book_id: book_id}} = Slidething.Book.create("JSON Test")
    {:ok, [page_id]} = Slidething.Book.create_pages(book_id, 1)
    %{run_id: run_id, page_id: page_id}
  end

  defp start_agent(run_id, agent_type, scope, spec) do
    {:ok, pid} =
      AgentGenServer.start_link(
        run_id: run_id,
        agent_type: agent_type,
        scope: scope,
        orchestrator_pid: self(),
        agent_spec: spec
      )

    pid
  end

  defp agent_spec(agent_type) do
    %AgentSpec{
      name: agent_type,
      provider: "mock",
      model: "mock-model",
      temperature: 0.5,
      max_tokens: 4000,
      max_iterations: 10,
      system_prompt: "You are a #{agent_type} agent.",
      tools: []
    }
  end

  @tag :capture_log
  test "agent planner broadcast events are JSON-encodable", %{run_id: run_id} do
    spec = agent_spec(:planner)
    agent_pid = start_agent(run_id, :planner, :book, spec)
    Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

    AgentGenServer.start_task(agent_pid, "Plan: test", %{})

    events = collect_events(2)
    assert length(events) > 0

    for event <- events do
      assert Jason.encode!(event), "planner event should be JSON: #{inspect(event.event)}"
    end
  end

  @tag :capture_log
  test "agent content broadcast events are JSON-encodable", %{run_id: run_id, page_id: page_id} do
    spec = agent_spec(:content)
    agent_pid = start_agent(run_id, :content, {:page, page_id}, spec)
    Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

    AgentGenServer.start_task(agent_pid, "Create content", %{})

    events = collect_events(2)
    assert length(events) > 0

    for event <- events do
      assert Jason.encode!(event), "content event should be JSON: #{inspect(event.event)}"
    end
  end

  @terminal_events [:completed, :failed]

  defp collect_events(timeout_s) do
    collect([], timeout_s * 1000)
  end

  defp collect(acc, timeout_ms) do
    receive do
      {:agent_event, %{event: event_type} = event} when event_type in @terminal_events ->
        Enum.reverse([event | acc])

      {:agent_event, event} ->
        collect([event | acc], timeout_ms)
    after
      timeout_ms ->
        Enum.reverse(acc)
    end
  end
end
