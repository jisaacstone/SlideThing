defmodule Slidething.LLM.Provider.Mock do
  @moduledoc """
  Mock LLM provider for testing. Returns predetermined responses
  based on agent type and iteration count.
  """

  @behaviour Slidething.LLM.Provider

  alias Slidething.Agent.{AgentSpec, Message, ToolCall}

  @impl true
  def complete_json(%AgentSpec{name: :planner}, _messages) do
    {:final_response, "Mock plan: create 3 pages with content"}
  end

  def complete_json(%AgentSpec{name: :content}, messages) do
    iteration = count_iterations(messages)

    if iteration < 2 do
      {:tool_requests,
       [
         %ToolCall{
           call_id: "mock_call_#{iteration}",
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

  def complete_json(_agent_spec, _messages) do
    {:final_response, "Mock response"}
  end

  defp count_iterations(messages) do
    Enum.count(messages, fn
      %Message{role: :tool} -> true
      _ -> false
    end)
  end
end