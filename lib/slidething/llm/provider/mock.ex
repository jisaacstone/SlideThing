defmodule Slidething.LLM.Provider.Mock do
  @moduledoc """
  Mock LLM provider for testing. Returns predetermined responses
  based on agent type and iteration count.
  """

  @behaviour Slidething.LLM.Provider

  alias Slidething.Agent.{AgentSpec, Message, ToolCall}

  @impl true
  def complete_json(%AgentSpec{name: :planner}, messages) do
    iteration = count_iterations(messages)

    case iteration do
      0 ->
        {:tool_requests,
         [
           %ToolCall{
             call_id: "planner_call_0",
             tool: :create_book,
             args: %{"title" => "Mock Children's Book", "metadata" => %{"theme" => "adventure", "target_audience" => "ages 4-6"}}
           }
         ]}

      1 ->
        book_id = extract_book_id(messages)
        {:tool_requests,
         [
           %ToolCall{
             call_id: "planner_call_1",
             tool: :create_pages,
             args: %{
               "book_id" => book_id,
               "pages" => [
                 %{"position" => 1, "metadata" => %{"description" => "Page 1: Introduction — the main character appears"}},
                 %{"position" => 2, "metadata" => %{"description" => "Page 2: The problem arises"}},
                 %{"position" => 3, "metadata" => %{"description" => "Page 3: The resolution"}}
               ]
             }
           }
         ]}

      _ ->
        page_ids = extract_page_ids(messages)
        plan_json = Jason.encode!(%{
          "book_id" => extract_book_id(messages),
          "pages" => Enum.map(page_ids, fn {id, pos} ->
            %{"page_id" => id, "position" => pos, "description" => "Mock page description"}
          end)
        })
        {:final_response, plan_json}
    end
  end

  def complete_json(%AgentSpec{name: :content}, messages) do
    iteration = count_iterations(messages)
    page_scope = extract_page_scope(messages)

    page_id =
      case page_scope do
        {:page, pid} -> pid
        _ -> "page-unknown"
      end

    if iteration < 3 do
      {:tool_requests,
       [
         %ToolCall{
           call_id: "content_call_#{iteration}",
           tool: :create_element,
           args: %{"page_id" => page_id, "element_type" => "text", "content" => "Mock content #{iteration} for #{page_id}"}
         }
       ]}
    else
      {:final_response, "Content creation complete for #{page_id}"}
    end
  end

  def complete_json(%AgentSpec{name: :media}, _messages) do
    {:final_response, "Media generation complete"}
  end

  def complete_json(%AgentSpec{name: :layout}, _messages) do
    {:final_response, "Layout complete"}
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

  defp extract_book_id(messages) do
    messages
    |> Enum.find_value(fn
      %Message{role: :tool, tool_results: results} ->
        Enum.find_value(results, fn
          %{tool: :create_book, success: true, data: %{book_id: bid}} -> bid
          %{tool: :create_book, success: true, data: %{"book_id" => bid}} -> bid
          _ -> nil
        end)
      _ -> nil
    end) || "book-mock-default"
  end

  defp extract_page_ids(messages) do
    messages
    |> Enum.find_value(fn
      %Message{role: :tool, tool_results: results} ->
        ids = Enum.find_value(results, fn
          %{tool: :create_pages, success: true, data: %{page_ids: pids}} -> pids
          %{tool: :create_pages, success: true, data: %{"page_ids" => pids}} -> pids
          _ -> nil
        end)
        if ids, do: Enum.with_index(ids, 1)
      _ -> nil
    end) || []
  end

  defp extract_page_scope(messages) do
    messages
    |> Enum.find_value(fn
      %Message{role: :user, content: content} ->
        case Regex.run(~r/(page_\w+)/, content) do
          [_, pid] -> {:page, pid}
          nil -> nil
        end
      _ -> nil
    end)
  end
end