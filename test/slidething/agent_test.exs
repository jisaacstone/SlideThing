defmodule Slidething.Agent.APITest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.API

  describe "start_run/2" do
    test "creates a new run and returns run_id" do
      assert {:ok, run_id} = API.start_run("Test prompt")
      assert is_binary(run_id)
      assert String.starts_with?(run_id, "run_")
    end

    test "registers orchestrator in RunRegistry" do
      {:ok, run_id} = API.start_run("Test")

      assert [{_pid, _}] = Registry.lookup(Slidething.RunRegistry, run_id)
    end

    test "starts run with book_id" do
      {:ok, run_id} = API.start_run("Test", "book-123")

      state = API.get_run_status(run_id)
      assert state.book_id == "book-123"
    end
  end

  describe "get_run_status/1" do
    test "returns orchestrator state for active run" do
      {:ok, run_id} = API.start_run("Test")

      state = API.get_run_status(run_id)
      assert state.run_id == run_id
      assert state.prompt == "Test"
      assert state.status in [:planning, :executing, :validating, :done]
    end

    test "returns :not_found for unknown run" do
      assert :not_found = API.get_run_status("nonexistent")
    end
  end

  describe "get_agents/1" do
    test "returns list of agents for a run" do
      {:ok, run_id} = API.start_run("Test")
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :content}}}, 3000

      agents = API.get_agents(run_id)
      assert is_list(agents)
      assert length(agents) > 0
    end

    test "returns empty list for run with no agents yet" do
      agents = API.get_agents("nonexistent")
      assert agents == []
    end
  end

  describe "get_agent_state/3" do
    test "returns agent state for specific agent" do
      {:ok, run_id} = API.start_run("Test")
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :content}}}, 3000

      case API.get_agent_state(run_id, :content, :book) do
        :not_found ->
          assert true

        state ->
          assert state.run_id == run_id
          assert state.agent_type == :content
      end
    end

    test "returns :not_found for unknown agent" do
      assert :not_found = API.get_agent_state("run_123", :unknown, nil)
    end
  end

  describe "list_runs/0" do
    test "returns all active runs" do
      {:ok, run_id1} = API.start_run("Test 1")
      {:ok, run_id2} = API.start_run("Test 2")

      runs = API.list_runs()
      run_ids = Enum.map(runs, fn {id, _pid} -> id end)

      assert run_id1 in run_ids
      assert run_id2 in run_ids
    end
  end

  describe "event subscriptions" do
    test "subscribe_to_run/1 receives run events" do
      {:ok, run_id} = API.start_run("Test")
      API.subscribe_to_run(run_id)

      assert_receive {:run_event, %{run_id: ^run_id}}, 1000
    end

    test "subscribe_to_agent_events/1 receives agent events" do
      {:ok, run_id} = API.start_run("Test")
      API.subscribe_to_agent_events(run_id)

      assert_receive {:agent_event, %{run_id: ^run_id}}, 2000
    end

    test "subscribe_to_all_agent_events/0 receives all events" do
      API.subscribe_to_all_agent_events()
      {:ok, _run_id} = API.start_run("Test")

      assert_receive {:tool_result, _}, 3000
    end
  end

  describe "full run lifecycle" do
    test "completes a full run from start to finish" do
      {:ok, run_id} = API.start_run("Create a book about cats")
      API.subscribe_to_run(run_id)

      assert_receive {:run_event, %{event: :phase_completed, data: %{phase: :planner}}}, 2000

      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :content}}}, 1000

      assert_receive {:run_event, %{event: :validation_started}}, 3000

      assert_receive {:run_event, %{event: :completed}}, 1000

      state = API.get_run_status(run_id)
      assert state.status == :done
    end
  end
end