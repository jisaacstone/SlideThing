defmodule Slidething.Agent.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.Orchestrator

  setup do
    run_id = "test_run_#{Ecto.UUID.generate()}"

    {:ok, orchestrator_pid} = Orchestrator.start_link(run_id: run_id)

    on_exit(fn ->
      DynamicSupervisor.which_children(Slidething.RunSupervisor)
      |> Enum.each(fn
        {:undefined, pid, :worker, [Slidething.Agent.GenServer]} when is_pid(pid) ->
          DynamicSupervisor.terminate_child(Slidething.RunSupervisor, pid)

        _ ->
          :ok
      end)
    end)

    %{run_id: run_id, orchestrator_pid: orchestrator_pid}
  end

  describe "start_link/1" do
    test "starts orchestrator and registers in registry", %{
      orchestrator_pid: orchestrator_pid,
      run_id: run_id
    } do
      assert Process.alive?(orchestrator_pid)

      assert [{^orchestrator_pid, _}] =
               Registry.lookup(Slidething.RunRegistry, run_id)
    end

    test "initializes with idle state", %{orchestrator_pid: orchestrator_pid} do
      state = Orchestrator.get_state(orchestrator_pid)

      assert state.status == :idle
      assert state.phase == nil
      assert state.plan == nil
      assert state.prompt == nil
      assert state.book_id == nil
    end
  end

  describe "start_run/3" do
    test "transitions to planning state", %{orchestrator_pid: orchestrator_pid} do
      Orchestrator.start_run(orchestrator_pid, "Create a book", "book-123")

      state = Orchestrator.get_state(orchestrator_pid)
      assert state.status in [:planning, :executing, :validating, :done]
      assert state.prompt == "Create a book"
      assert state.book_id == "book-123"
    end

    test "broadcasts started event", %{orchestrator_pid: orchestrator_pid, run_id: run_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

      Orchestrator.start_run(orchestrator_pid, "Test prompt", nil)

      assert_receive {:run_event, %{event: :started, data: %{prompt: "Test prompt"}}}, 1000
    end

    test "starts planner agent", %{orchestrator_pid: orchestrator_pid, run_id: run_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

      Orchestrator.start_run(orchestrator_pid, "Test", nil)

      # Should see phase_started for planner
      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :planner}}}, 1000
    end
  end

  describe "state machine transitions" do
    test "planner → content → validating → done", %{
      orchestrator_pid: orchestrator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

      Orchestrator.start_run(orchestrator_pid, "Create content", nil)

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

      state = Orchestrator.get_state(orchestrator_pid)
      assert state.status == :done
      assert state.completed_at != nil
    end

    test "creates run plan from planner result", %{
      orchestrator_pid: orchestrator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

      Orchestrator.start_run(orchestrator_pid, "Test", nil)

      # Wait for planner to complete
      assert_receive {:run_event, %{event: :phase_completed, data: %{phase: :planner}}},
                     2000

      state = Orchestrator.get_state(orchestrator_pid)
      assert state.plan != nil
      assert is_list(state.plan.tasks)
      assert length(state.plan.tasks) > 0
    end
  end

  describe "agent coordination" do
    test "collects results from multiple agents", %{
      orchestrator_pid: orchestrator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

      Orchestrator.start_run(orchestrator_pid, "Test", nil)

      # Wait for content phase to start (multiple agents)
      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :content}}}, 2000

      # Wait for completion
      assert_receive {:run_event, %{event: :completed}}, 5000

      state = Orchestrator.get_state(orchestrator_pid)
      assert state.status == :done
    end

    test "handles agent failures", %{orchestrator_pid: orchestrator_pid, run_id: run_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

      # Start run
      Orchestrator.start_run(orchestrator_pid, "Test", nil)

      # Manually send agent_failed message
      send(orchestrator_pid, {:agent_failed, self(), :test_failure})

      assert_receive {:run_event, %{event: :failed, data: %{reason: ":test_failure"}}}, 1000

      state = Orchestrator.get_state(orchestrator_pid)
      assert state.status == :failed
    end
  end

  describe "event broadcasting" do
    test "broadcasts all phase transitions", %{
      orchestrator_pid: orchestrator_pid,
      run_id: run_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

      Orchestrator.start_run(orchestrator_pid, "Test", nil)

      events =
        collect_until_completed([])
        |> Enum.map(fn %{event: event} -> event end)

      assert :started in events
      assert :phase_started in events
      assert :phase_completed in events
      assert :validation_started in events
      assert :completed in events
    end

    defp collect_until_completed(acc) do
      receive do
        {:run_event, %{event: :completed} = event} ->
          Enum.reverse([event | acc])
        {:run_event, event} ->
          collect_until_completed([event | acc])
      after
        5000 -> Enum.reverse(acc)
      end
    end
  end
end
