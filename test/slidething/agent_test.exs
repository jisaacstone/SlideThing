defmodule Slidething.Agent.APITest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.API

  @run_timeout 10_000

  describe "start_run/2" do
    test "creates a new run and returns run_id" do
      assert {:ok, run_id} = API.start_run("Test prompt")
      assert is_binary(run_id)
      assert byte_size(run_id) >= 16
    end

    test "registers orchestrator in RunRegistry" do
      {:ok, run_id} = API.start_run("Test")
      assert [{_pid, _}] = Registry.lookup(Slidething.RunRegistry, run_id)
    end

    test "starts run with book_id" do
      {:ok, %{book_id: book_id}} = Slidething.Book.create("Test Book", %{})
      {:ok, run_id} = API.start_run("Test", book_id)
      state = API.get_run_status(run_id)
      assert state.book_id == book_id
    end
  end

  describe "get_run_status/1" do
    test "returns orchestrator state for active run" do
      {:ok, run_id} = API.start_run("Test")
      state = API.get_run_status(run_id)
      assert state.run_id == run_id
      assert state.prompt == "Test"
      assert state.status in [:planning, :executing, :done, :failed]
    end

    test "returns :not_found for unknown run" do
      assert :not_found = API.get_run_status("nonexistent")
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
    test "subscribe/1 receives run events" do
      {:ok, run_id} = API.start_run("Test")
      API.subscribe(run_id)
      assert_receive {:run_event, %{run_id: ^run_id}}, 2_000
    end
  end

  describe "full run lifecycle" do
    test "completes a full run from start to finish" do
      {:ok, run_id} = API.start_run("Create a book about cats")
      API.subscribe(run_id)

      assert_receive {:run_event, %{event: :planning_complete}}, @run_timeout
      assert_receive {:run_event, %{event: :completed}}, @run_timeout

      state = API.get_run_status(run_id)
      assert state.status == :done
    end
  end
end
