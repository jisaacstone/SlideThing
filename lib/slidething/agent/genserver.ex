defmodule Slidething.Agent.GenServer do
  @moduledoc """
  Generic agent GenServer with async LLM pattern.

  This module implements the core agent process that:
  - Accepts tasks via cast (non-blocking)
  - Spawns async Tasks for LLM calls
  - Handles Task results via handle_info
  - Sends results to orchestrator when done
  - Broadcasts events for monitoring
  """

  use GenServer
  require Logger

  alias Slidething.Agent.{AgentSpec, Message, ToolCall, ToolResult}

  defstruct [
    :run_id,
    :agent_type,
    :scope,
    :orchestrator_pid,
    :agent_spec,
    :status,
    :messages,
    :pending_task,
    :iteration,
    :max_iterations,
    :result
  ]

  @type t :: %__MODULE__{
          run_id: String.t(),
          agent_type: atom(),
          scope: term(),
          orchestrator_pid: pid(),
          agent_spec: AgentSpec.t(),
          status: :idle | :thinking | :executing_tools | :done | :failed,
          messages: [Message.t()],
          pending_task: Task.t() | nil,
          iteration: integer(),
          max_iterations: integer(),
          result: term() | nil
        }

  # Client API

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    agent_type = Keyword.fetch!(opts, :agent_type)
    scope = Keyword.get(opts, :scope)

    name = via_tuple(run_id, agent_type, scope)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def via_tuple(run_id, agent_type, scope) do
    {:via, Registry, {Slidething.AgentRegistry, {run_id, agent_type, scope}}}
  end

  def start_task(pid, task_description, context) do
    GenServer.cast(pid, {:start_task, task_description, context})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      run_id: Keyword.fetch!(opts, :run_id),
      agent_type: Keyword.fetch!(opts, :agent_type),
      scope: Keyword.get(opts, :scope),
      orchestrator_pid: Keyword.fetch!(opts, :orchestrator_pid),
      agent_spec: Keyword.fetch!(opts, :agent_spec),
      status: :idle,
      messages: [],
      pending_task: nil,
      iteration: 0,
      max_iterations: opts[:agent_spec].max_iterations || 10,
      result: nil
    }

    broadcast_event(state, :started, %{agent_type: state.agent_type, scope: state.scope})
    {:ok, state}
  end

  @impl true
  def handle_cast({:start_task, task_description, context}, state) do
    Logger.info(
      "[#{state.agent_type}] Starting task: #{inspect(task_description)} scope=#{inspect(state.scope)}"
    )

    system_message = %Message{
      role: :system,
      content: state.agent_spec.system_prompt
    }

    user_message = %Message{
      role: :user,
      content: task_description
    }

    new_state = %{
      state
      | messages: [system_message, user_message],
        status: :thinking,
        iteration: 0
    }

    broadcast_event(new_state, :task_started, %{task: task_description, context: context})

    send(self(), :do_llm_call)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:do_llm_call, %{iteration: iter, max_iterations: max} = state)
      when iter >= max do
    Logger.warning("[#{state.agent_type}] Max iterations reached (#{max})")
    fail_agent(state, :max_iterations_reached)
  end

  @impl true
  def handle_info(:do_llm_call, state) do
    Logger.debug("[#{state.agent_type}] Iteration #{state.iteration + 1}, calling LLM")

    task =
      Task.Supervisor.async_nolink(Slidething.IOTaskSupervisor, fn ->
        mock_llm_call(state.agent_spec, state.messages)
      end)

    new_state = %{state | status: :thinking, pending_task: task}
    broadcast_event(new_state, :llm_call_started, %{iteration: state.iteration + 1})
    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, result}, %{pending_task: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    Logger.debug("[#{state.agent_type}] LLM response received")
    broadcast_event(state, :llm_response, %{result: result})

    case result do
      {:tool_requests, calls} ->
        handle_tool_requests(state, calls)

      {:patch_proposal, patch} ->
        complete_agent(state, {:patch, patch})

      {:final_response, message} ->
        complete_agent(state, {:final, message})

      {:error, reason} ->
        Logger.error("[#{state.agent_type}] LLM call failed: #{inspect(reason)}")
        fail_agent(state, {:llm_error, reason})
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pending_task: %{ref: ref}} = state) do
    Logger.error("[#{state.agent_type}] Task crashed: #{inspect(reason)}")
    fail_agent(state, {:task_crash, reason})
  end

  # Private functions

  defp handle_tool_requests(state, calls) do
    Logger.info("[#{state.agent_type}] Executing #{length(calls)} tool calls")

    results =
      Enum.map(calls, fn %ToolCall{tool: tool, args: args} ->
        Logger.debug("[#{state.agent_type}] Tool call: #{tool}(#{inspect(args)})")
        execute_tool(tool, args)
      end)

    tool_message = %Message{
      role: :tool,
      tool_results: results
    }

    new_state = %{
      state
      | messages: state.messages ++ [tool_message],
        status: :executing_tools,
        iteration: state.iteration + 1,
        pending_task: nil
    }

    broadcast_event(new_state, :tools_executed, %{
      tool_count: length(calls),
      results: results
    })

    send(self(), :do_llm_call)
    {:noreply, new_state}
  end

  defp execute_tool(tool, args) do
    result =
      case tool do
        :mock_get_book ->
          %ToolResult{
            tool: tool,
            success: true,
            data: %{id: "book-1", title: "Mock Book", pages: []}
          }

        :mock_create_element ->
          %ToolResult{
            tool: tool,
            success: true,
            data: %{element_id: "elem-#{:rand.uniform(1000)}", type: args[:type]}
          }

        _ ->
          %ToolResult{
            tool: tool,
            success: false,
            error: "Unknown tool: #{tool}"
          }
      end

    broadcast_tool_result(tool, args, result)
    result
  end

  defp complete_agent(state, result) do
    Logger.info("[#{state.agent_type}] Completed with result: #{inspect(result)}")

    new_state = %{state | status: :done, result: result, pending_task: nil}
    broadcast_event(new_state, :completed, %{result: result})

    send(state.orchestrator_pid, {:agent_done, self(), result})
    {:noreply, new_state}
  end

  defp fail_agent(state, reason) do
    Logger.error("[#{state.agent_type}] Failed: #{inspect(reason)}")

    new_state = %{state | status: :failed, pending_task: nil}
    broadcast_event(new_state, :failed, %{reason: reason})

    send(state.orchestrator_pid, {:agent_failed, self(), reason})
    {:noreply, new_state}
  end

  defp broadcast_event(state, event_type, data) do
    event = %{
      run_id: state.run_id,
      agent_type: state.agent_type,
      scope: state.scope,
      event: event_type,
      data: data,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Slidething.PubSub,
      "agent_events:#{state.run_id}",
      {:agent_event, event}
    )
  end

  defp broadcast_tool_result(tool, args, result) do
    Phoenix.PubSub.broadcast(
      Slidething.PubSub,
      "agent_events:all",
      {:tool_result, %{tool: tool, args: args, result: result, timestamp: DateTime.utc_now()}}
    )
  end

  defp mock_llm_call(%AgentSpec{name: :planner}, _messages) do
    {:final_response, "Mock plan: create 3 pages with content"}
  end

  defp mock_llm_call(%AgentSpec{name: :content}, messages) do
    iteration = count_iterations(messages)

    if iteration < 2 do
      {:tool_requests,
       [
         %ToolCall{
           tool: :mock_create_element,
           args: %{type: :text, content: "Mock content #{iteration}"}
         }
       ]}
    else
      {:patch_proposal,
       %{
         content_changes: [
           %{element_id: "elem-1", page_id: "page-1", content: "Final content"}
         ]
       }}
    end
  end

  defp mock_llm_call(_agent_spec, _messages) do
    {:final_response, "Mock response"}
  end

  defp count_iterations(messages) do
    Enum.count(messages, fn
      %Message{role: :tool} -> true
      _ -> false
    end)
  end
end
