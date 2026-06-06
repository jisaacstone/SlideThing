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

  alias Slidething.Agent.{AgentSpec, Message, ToolCall}

  defstruct [
    :run_id,
    :agent_run_id,
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
          agent_run_id: String.t() | nil,
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
    phase_name = Keyword.get(opts, :phase_name)

    name = via_tuple(run_id, phase_name, agent_type, scope)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def via_tuple(run_id, phase_name, agent_type, scope) do
    {:via, Registry, {Slidething.AgentRegistry, {run_id, phase_name, agent_type, scope}}}
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
      agent_run_id: nil,
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

    broadcast_event(state, :started, %{
      agent_type: state.agent_type,
      scope: scope_to_json(state.scope)
    })

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

    agent_run_id =
      Slidething.Transcript.start_agent_run(
        state.run_id,
        state.agent_type,
        state.scope,
        state.agent_spec
      )

    Slidething.Transcript.append_messages(agent_run_id, 0, [system_message, user_message])

    new_state = %{
      state
      | agent_run_id: agent_run_id,
        messages: [system_message, user_message],
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
        Slidething.LLM.Client.complete_json(state.agent_spec, state.messages)
      end)

    new_state = %{state | status: :thinking, pending_task: task}
    broadcast_event(new_state, :llm_call_started, %{iteration: state.iteration + 1})
    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, result}, %{pending_task: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    Logger.debug("[#{state.agent_type}] LLM response received")

    case result do
      {:tool_requests, calls} ->
        broadcast_event(state, :llm_response, %{
          result_type: :tool_requests,
          tool_count: length(calls)
        })

        handle_tool_requests(state, calls)

      {:patch_proposal, patch} ->
        broadcast_event(state, :llm_response, %{result_type: :patch_proposal})
        complete_agent(state, {:patch, patch})

      {:final_response, message} ->
        broadcast_event(state, :llm_response, %{result_type: :final_response, message: message})
        complete_agent(state, {:final, message})

      {:error, reason} ->
        Logger.error("[#{state.agent_type}] LLM call failed: #{inspect(reason)}")
        broadcast_event(state, :llm_response, %{result_type: :error, reason: inspect(reason)})
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
      Enum.map(calls, fn %ToolCall{call_id: call_id, tool: tool, args: args} ->
        Logger.debug("[#{state.agent_type}] Tool call: #{tool}(#{inspect(args)})")
        %{Slidething.Tool.Registry.execute(tool, args) | call_id: call_id}
      end)

    assistant_message = %Message{
      role: :assistant,
      content: "",
      tool_calls: calls
    }

    tool_message = %Message{
      role: :tool,
      tool_results: results
    }

    next_iteration = state.iteration + 1

    if state.agent_run_id do
      Slidething.Transcript.append_messages(state.agent_run_id, next_iteration, [
        assistant_message,
        tool_message
      ])
    end

    new_state = %{
      state
      | messages: state.messages ++ [assistant_message, tool_message],
        status: :executing_tools,
        iteration: next_iteration,
        pending_task: nil
    }

    broadcast_event(new_state, :tools_executed, %{
      tool_count: length(calls),
      results: Enum.map(results, &tool_result_to_map/1)
    })

    send(self(), :do_llm_call)
    {:noreply, new_state}
  end

  defp complete_agent(state, result) do
    Logger.info("[#{state.agent_type}] Completed with result: #{inspect(result)}")

    if state.agent_run_id do
      case result do
        {:final, msg} ->
          Slidething.Transcript.append_message(state.agent_run_id, state.iteration + 1, %Message{
            role: :assistant,
            content: msg
          })

        _ ->
          :ok
      end

      Slidething.Transcript.complete_agent_run(state.agent_run_id, result)
    end

    new_state = %{state | status: :done, result: result, pending_task: nil}
    broadcast_event(new_state, :completed, %{result: result_to_map(result)})

    send(state.orchestrator_pid, {:agent_done, self(), result})
    {:noreply, new_state}
  end

  defp fail_agent(state, reason) do
    Logger.error("[#{state.agent_type}] Failed: #{inspect(reason)}")

    if state.agent_run_id do
      Slidething.Transcript.fail_agent_run(state.agent_run_id, reason)
    end

    new_state = %{state | status: :failed, pending_task: nil}
    broadcast_event(new_state, :failed, %{reason: inspect(reason)})

    send(state.orchestrator_pid, {:agent_failed, self(), reason})
    {:noreply, new_state}
  end

  defp result_to_map({:final, message}), do: %{type: "final", message: message}
  defp result_to_map({:patch, _patch}), do: %{type: "patch"}
  defp result_to_map(other), do: %{type: "unknown", value: inspect(other)}

  defp tool_result_to_map(%Slidething.Agent.ToolResult{} = r) do
    %{
      call_id: r.call_id,
      tool: r.tool,
      success: r.success,
      error: r.error
    }
  end

  defp broadcast_event(state, event_type, data) do
    event = %{
      run_id: state.run_id,
      agent_type: state.agent_type,
      scope: scope_to_json(state.scope),
      event: event_type,
      data: data,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Slidething.PubSub,
      "events:#{state.run_id}",
      {:agent_event, event}
    )
  end

  def scope_to_json({:page, page_id}), do: %{type: "page", page_id: page_id}
  def scope_to_json({:elements, element_ids}), do: %{type: "elements", element_ids: element_ids}
  def scope_to_json({:element, element_id}), do: %{type: "element", element_id: element_id}
  def scope_to_json({:pages, page_ids}), do: %{type: "pages", page_ids: page_ids}
  def scope_to_json(nil), do: nil
  def scope_to_json(other) when is_atom(other), do: Atom.to_string(other)
  def scope_to_json(other), do: other
end
