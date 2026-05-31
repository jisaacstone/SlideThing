defmodule Slidething.Agent.RunCoordinatorTest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.RunCoordinator

  setup do
    run_id = "test_run_#{:rand.uniform(1000)}"

    {:ok, coordinator_pid} = RunCoordinator.start_link(run_id: run_id)

    %{run_id: run_id, coordinator_pid: coordinator_pid}
  end

  describe "start_link/1" do
    test "starts coordinator and registers in registry", %{
      coordinator_pid: coordinator_pid,
      run_id: run_id
    } do
      assert Process.alive?(coordinator_pid)

      assert [{^coordinator_pid, _}] =
               Registry.lookup(Slidething.RunRegistry, run_id)
    end

    test "initializes with idle state", %{coordinator_pid: coordinator_pid} do
      state = RunCoordinator.get_state(coordinator_pid)

      assert state.status == :idle
      assert state.phase == nil
      assert state.plan == nil
      assert state.prompt == nil
      assert state.book_id == nil
    end
  end

  describe "start_run/3" do
    test "transitions to planning state", %{coordinator_pid: coordinator_pid} do
      RunCoordinator.start_run(coordinator_pid, "Create a book", "book-123")
      Process.sleep(100)

      state = RunCoordinator.get_state(coordinator_pid)
      assert state.status in [:planning, :executing, :validating, :done]
      assert state.prompt == "Create a book"
      assert state.book_id == "book-123"
    end

    test "broadcasts started event", %{coordinator_pid: coordinator_pid, run_id: run_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      RunCoordinator.start_run(coordinator_pid, "Test prompt", nil)

      assert_receive {:run_event, %{event: :started, data: %{prompt: "Test prompt"}}}, 1000
    end

    test "starts planner agent", %{coordinator_pid: coordinator_pid, run_id: run_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      RunCoordinator.start_run(coordinator_pid, "Test", nil)

      # Should see phase_started for planner
      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :planner}}}, 1000
    end
  end

  describe "state machine transitions" do
    test "planner → content → validating → done", %{
      coordinator_pid: coordinator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      RunCoordinator.start_run(coordinator_pid, "Create content", nil)

      # Planner phase
      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :planner}}}, 1000

      # Planner completes
      assert_receive {:run_event, %{event: :phase_completed, data: %{phase: :planner}}}, 2000

      # Content phase starts
      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :content}}}, 1000

      # Content completes
      assert_receive {:run_event, %{event: :phase_completed, data: %{phase: :content}}}, 3000

      # Validation starts
      assert_receive {:run_event, %{event: :validation_started}}, 1000

      # Run completes
      assert_receive {:run_event, %{event: :completed}}, 1000

      # Final state should be done
      Process.sleep(100)
      state = RunCoordinator.get_state(coordinator_pid)
      assert state.status == :done
      assert state.completed_at != nil
    end

    test "creates run plan from planner result", %{
      coordinator_pid: coordinator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      RunCoordinator.start_run(coordinator_pid, "Test", nil)

      # Wait for planner to complete
      assert_receive {:run_event, %{event: :phase_completed, data: %{phase: :planner, plan: plan}}},
                     2000

      assert plan.intent
      assert is_list(plan.tasks)
      assert length(plan.tasks) > 0
    end
  end

  describe "agent coordination" do
    test "collects results from multiple agents", %{
      coordinator_pid: coordinator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      RunCoordinator.start_run(coordinator_pid, "Test", nil)

      # Wait for content phase to start (multiple agents)
      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :content}}}, 2000

      # Wait for completion
      assert_receive {:run_event, %{event: :completed}}, 5000

      state = RunCoordinator.get_state(coordinator_pid)
      assert state.status == :done
    end

    test "handles agent failures", %{coordinator_pid: coordinator_pid, run_id: run_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      # Start run
      RunCoordinator.start_run(coordinator_pid, "Test", nil)

      # Manually send agent_failed message
      send(coordinator_pid, {:agent_failed, self(), :test_failure})

      assert_receive {:run_event, %{event: :failed, data: %{reason: :test_failure}}}, 1000

      Process.sleep(100)
      state = RunCoordinator.get_state(coordinator_pid)
      assert state.status == :failed
    end
  end

  describe "event broadcasting" do
    test "broadcasts all phase transitions", %{
      coordinator_pid: coordinator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")

      RunCoordinator.start_run(coordinator_pid, "Test", nil)

      events =
        collect_events(5000, [])
        |> Enum.map(fn %{event: event} -> event end)

      assert :started in events
      assert :phase_started in events
      assert :phase_completed in events
      assert :validation_started in events
      assert :completed in events
    end

    defp collect_events(timeout, acc) do
      receive do
        {:run_event, event} ->
          collect_events(timeout, [event | acc])
      after
        timeout ->
          Enum.reverse(acc)
      end
    end
  end
end
