defmodule Slidething.Agent.GenServerTest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.AgentSpec
  alias Slidething.Agent.GenServer, as: AgentGenServer

  setup do
    run_id = "test_run_#{:rand.uniform(1000)}"

    {:ok, %{book_id: book_id}} = Slidething.Book.create("Test Book")
    {:ok, [page_id]} = Slidething.Book.create_pages(book_id, 1)

    spec = %AgentSpec{
      name: :content,
      provider: "mock",
      model: "mock-model",
      temperature: 0.7,
      max_tokens: 4000,
      max_iterations: 5,
      system_prompt: "You are a test agent.",
      tools: [:create_element]
    }

    test_pid = self()
    {:ok, orchestrator_pid} = Task.start(fn -> 
      receive do
        msg -> send(test_pid, {:received, msg})
      after
        5000 -> :ok
      end
    end)

    {:ok, agent_pid} = AgentGenServer.start_link(
      run_id: run_id,
      agent_type: :content,
      scope: {:page, page_id},
      orchestrator_pid: orchestrator_pid,
      agent_spec: spec
    )

    %{
      run_id: run_id,
      agent_pid: agent_pid,
      orchestrator_pid: orchestrator_pid,
      spec: spec,
      page_id: page_id
    }
  end

  describe "start_link/1" do
    test "starts agent and registers in registry", %{agent_pid: agent_pid, run_id: run_id, page_id: page_id} do
      assert Process.alive?(agent_pid)

      assert [{^agent_pid, _}] = Registry.lookup(
        Slidething.AgentRegistry,
        {run_id, :content, {:page, page_id}}
      )
    end

    test "initializes with correct state", %{agent_pid: agent_pid} do
      state = AgentGenServer.get_state(agent_pid)
      
      assert state.status == :idle
      assert state.iteration == 0
      assert state.messages == []
      assert state.pending_task == nil
      assert state.result == nil
    end
  end

describe "start_task/3" do
    test "transitions to thinking state", %{agent_pid: agent_pid, page_id: page_id} do
      AgentGenServer.start_task(agent_pid, "Create content for page #{page_id}", %{})

      state = AgentGenServer.get_state(agent_pid)
      assert state.status in [:thinking, :executing_tools, :done]
      assert length(state.messages) > 0
    end

    test "broadcasts task_started event", %{agent_pid: agent_pid, run_id: run_id, page_id: page_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:#{run_id}")

      AgentGenServer.start_task(agent_pid, "Create content for page #{page_id}", %{})

      assert_receive {:agent_event, %{event: :task_started}}, 1000
    end
  end

  describe "async LLM pattern" do
    test "executes tool calls and continues loop", %{agent_pid: agent_pid, run_id: run_id, page_id: page_id} do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:#{run_id}")

      AgentGenServer.start_task(agent_pid, "Create content for page #{page_id}", %{})

      # Should see LLM call started
      assert_receive {:agent_event, %{event: :llm_call_started}}, 1000

      # Should see tools executed (mock LLM returns tool_requests first)
      assert_receive {:agent_event, %{event: :tools_executed}}, 2000

      # Should see another LLM call (iteration 2)
      assert_receive {:agent_event, %{event: :llm_call_started}}, 1000

      # Should complete with patch
      assert_receive {:agent_event, %{event: :completed}}, 2000
    end

    test "sends agent_done to orchestrator on completion", %{
      agent_pid: agent_pid,
      orchestrator_pid: orchestrator_pid,
      run_id: run_id,
      page_id: page_id
    } do
      Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:#{run_id}")

      AgentGenServer.start_task(agent_pid, "Create content for page #{page_id}", %{})

      assert_receive {:agent_event, %{event: :completed}}, 2000

      send(orchestrator_pid, :check)
      assert_receive {:received, {:agent_done, ^agent_pid, result}}, 1000
      assert {:final, _} = result
    end

    test "respects max_iterations limit", %{run_id: run_id} do
      spec = %AgentSpec{
        name: :content,
        provider: "mock",
        model: "mock-model",
        temperature: 0.7,
        max_tokens: 4000,
        max_iterations: 1,  # Very low limit
        system_prompt: "Test",
        tools: []
      }

      {:ok, orchestrator} = Task.start(fn -> 
        receive do
          msg -> send(self(), {:received, msg})
        after
          5000 -> :ok
        end
      end)

      {:ok, agent_pid} = AgentGenServer.start_link(
        run_id: run_id,
        agent_type: :content,
        scope: nil,
        orchestrator_pid: orchestrator,
        agent_spec: spec
      )

      Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:#{run_id}")
      
      AgentGenServer.start_task(agent_pid, "Test", %{})
      
      # Should fail due to max iterations
      assert_receive {:agent_event, %{event: :failed, data: %{reason: :max_iterations_reached}}}, 2000
    end
  end

  describe "error handling" do
    test "handles task crashes gracefully", %{run_id: run_id} do
      {:ok, %{book_id: book_id}} = Slidething.Book.create("Test Book")
      {:ok, [page_id]} = Slidething.Book.create_pages(book_id, 1)

      spec = %AgentSpec{
        name: :content,
        provider: "mock",
        model: "mock-model",
        temperature: 0.7,
        max_tokens: 4000,
        max_iterations: 1,
        system_prompt: "Test",
        tools: [:create_element]
      }

      test_pid = self()
      {:ok, orchestrator} = Task.start(fn ->
        receive do
          msg -> send(test_pid, {:orchestrator_received, msg})
        after
          5000 -> :ok
        end
      end)

      {:ok, agent_pid} = AgentGenServer.start_link(
        run_id: run_id,
        agent_type: :content,
        scope: {:page, page_id},
        orchestrator_pid: orchestrator,
        agent_spec: spec
      )

      Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:#{run_id}")

      AgentGenServer.start_task(agent_pid, "Test for page #{page_id}", %{})

      assert_receive {:agent_event, %{event: :failed}}, 2000
    end
  end

  describe "state inspection" do
    test "get_state returns full agent state", %{agent_pid: agent_pid, page_id: page_id} do
      state = AgentGenServer.get_state(agent_pid)
      
      assert %AgentGenServer{} = state
      assert state.run_id
      assert state.agent_type == :content
      assert state.scope == {:page, page_id}
      assert state.agent_spec
    end
  end
end
