defmodule Slidething.Agent.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.Orchestrator

  @run_timeout 10_000

  setup do
    run_id = "test_run_#{Ecto.UUID.generate()}"
    {:ok, orchestrator_pid} = Orchestrator.start_link(run_id: run_id)

    Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

    on_exit(fn ->
      if Process.alive?(orchestrator_pid), do: GenServer.stop(orchestrator_pid, :normal, 1_000)
    end)

    %{run_id: run_id, orchestrator_pid: orchestrator_pid}
  end

  describe "start_link/1" do
    test "starts and registers in RunRegistry", %{orchestrator_pid: pid, run_id: run_id} do
      assert Process.alive?(pid)
      assert [{^pid, _}] = Registry.lookup(Slidething.RunRegistry, run_id)
    end

    test "initializes with idle status", %{orchestrator_pid: pid} do
      state = Orchestrator.get_state(pid)
      assert state.status == :idle
      assert state.generated_plan == nil
      assert state.prompt == nil
      assert state.book_id == nil
    end
  end

  describe "start_run/3" do
    test "transitions out of idle on start", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      state = Orchestrator.get_state(pid)
      assert state.status in [:planning, :executing, :done, :failed]
    end

    test "stores prompt and book_id", %{orchestrator_pid: pid} do
      {:ok, %{book_id: book_id}} = Slidething.Book.create("Pre-existing", %{})
      Orchestrator.start_run(pid, "My prompt", book_id)
      state = Orchestrator.get_state(pid)
      assert state.prompt == "My prompt"
      assert state.book_id == book_id
    end

    test "broadcasts :started event immediately", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Test prompt", nil)
      assert_receive {:run_event, %{event: :started, data: %{prompt: "Test prompt"}}}, 2_000
    end

    test "broadcasts :phase_started for initial planning", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Test", nil)

      assert_receive {:run_event, %{event: :phase_started, data: %{phase: :initial_planning}}},
                     2_000
    end
  end

  describe "full run lifecycle" do
    test "completes with :done status", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      assert_receive {:run_event, %{event: :completed}}, @run_timeout
      assert Orchestrator.get_state(pid).status == :done
    end

    test "planning_complete event carries book_id and counts", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      assert_receive {:run_event, %{event: :planning_complete, data: data}}, @run_timeout
      assert is_binary(data.book_id)
      assert data.page_count > 0
      assert data.phase_count > 0
    end

    test "generated_plan is set after planning", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      assert_receive {:run_event, %{event: :planning_complete}}, @run_timeout
      state = Orchestrator.get_state(pid)
      assert state.generated_plan != nil
      assert is_list(state.generated_plan.phases)
      assert length(state.generated_plan.phases) > 0
    end

    test "all phases in the plan complete", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      assert_receive {:run_event, %{event: :completed}}, @run_timeout

      state = Orchestrator.get_state(pid)
      plan_phase_names = MapSet.new(state.generated_plan.phases, & &1.name)

      # Every phase whose condition was met should be in completed_phases
      # (conditional phases that weren't triggered won't be)
      Enum.each(state.generated_plan.phases, fn phase ->
        if is_nil(phase.condition) do
          assert MapSet.member?(state.completed_phases, phase.name),
                 "phase '#{phase.name}' should be completed"
        end
      end)

      _ = plan_phase_names
    end

    test "completed_at is set on :done", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      assert_receive {:run_event, %{event: :completed}}, @run_timeout
      assert Orchestrator.get_state(pid).completed_at != nil
    end
  end

  describe "failure handling" do
    test "unknown agent_failed pid is ignored gracefully", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      assert_receive {:run_event, %{event: :planning_complete}}, @run_timeout

      # Send a failure from a pid not tracked in pending_agents — should not crash
      send(pid, {:agent_failed, self(), :stray_failure})
      assert Process.alive?(pid)
    end

    test "status is :done after successful run", %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)
      assert_receive {:run_event, %{event: :completed}}, @run_timeout
      assert Orchestrator.get_state(pid).status == :done
    end
  end

  describe "event stream" do
    test "event stream includes :started, :planning_complete, :phase_started, :phase_completed, :completed",
         %{orchestrator_pid: pid} do
      Orchestrator.start_run(pid, "Create a book", nil)

      events =
        collect_events_until(:completed, @run_timeout)
        |> Enum.map(& &1.event)

      assert :started in events
      assert :planning_complete in events
      assert :phase_started in events
      assert :phase_completed in events
      assert :completed in events
    end

    test "every event carries run_id and timestamp", %{orchestrator_pid: pid, run_id: run_id} do
      Orchestrator.start_run(pid, "Test", nil)

      events = collect_events_until(:completed, @run_timeout)

      for event <- events do
        assert event.run_id == run_id
        assert %DateTime{} = event.timestamp
      end
    end
  end

  # ---------------------------------------------------------------------------

  defp collect_events_until(terminal, timeout, acc \\ []) do
    receive do
      {:run_event, %{event: ^terminal} = e} -> Enum.reverse([e | acc])
      {:run_event, e} -> collect_events_until(terminal, timeout, [e | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end
end
