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

    case iteration do
      0 ->
        tool_call("content_call_0", :create_element, %{
          "page_id" => page_id,
          "element_type" => "title",
          "content" => "Mock title for #{page_id}"
        })

      1 ->
        tool_call("content_call_1", :create_element, %{
          "page_id" => page_id,
          "element_type" => "image",
          "content" => "Mock image prompt for #{page_id}"
        })

      2 ->
        tool_call("content_call_2", :create_element, %{
          "page_id" => page_id,
          "element_type" => "text",
          "content" => "Mock body text for #{page_id}"
        })

      _ ->
        {:final_response, "Content creation complete for #{page_id}"}
    end
  end

  def complete_json(%AgentSpec{name: :media}, messages) do
    iteration = count_iterations(messages)

    cond do
      iteration == 0 ->
        prompt = extract_user_content(messages) || "mock image"
        aspect = extract_aspect_ratio(messages) || "1:1"

        {:tool_requests,
         [
           %ToolCall{
             call_id: "media_call_0",
             tool: :generate_image,
             args: %{"prompt" => prompt, "aspect_ratio" => aspect}
           }
         ]}

      iteration == 1 ->
        element_id = extract_element_id(messages)
        asset_path = extract_asset_path(messages)
        prompt = extract_user_content(messages) || "mock image"

        if element_id && asset_path do
          {:tool_requests,
           [
             %ToolCall{
               call_id: "media_call_1",
               tool: :store_asset,
               args: %{
                 "element_id" => element_id,
                 "asset_path" => asset_path,
                 "prompt" => prompt
               }
             }
           ]}
        else
          {:final_response, "Media generation complete"}
        end

      true ->
        {:final_response, "Media generation complete"}
    end
  end

  def complete_json(%AgentSpec{name: :layout}, messages) do
    iteration = count_iterations(messages)
    page_id = extract_page_scope_id(messages)

    cond do
      iteration == 0 and page_id ->
        {:tool_requests,
         [
           %ToolCall{
             call_id: "layout_call_0",
             tool: :get_page_elements,
             args: %{"page_id" => page_id}
           }
         ]}

      iteration == 1 and page_id ->
        elements = extract_page_elements(messages)
        format_id = extract_format_id(messages) || "format-web"

        layouts =
          elements
          |> Enum.with_index()
          |> Enum.map(fn {el, idx} ->
            %{
              "element_id" => el.id,
              "x" => 0.1,
              "y" => 0.1 + idx * 0.15,
              "width" => 0.8,
              "height" => 0.12
            }
          end)

        {:tool_requests,
         [
           %ToolCall{
             call_id: "layout_call_1",
             tool: :propose_layout,
             args: %{
               "page_id" => page_id,
               "format_id" => format_id,
               "element_layouts" => layouts
             }
           }
         ]}

      true ->
        {:final_response, "Layout complete"}
    end
  end

  def complete_json(_agent_spec, _messages) do
    {:final_response, "Mock response"}
  end

  defp tool_call(call_id, tool, args) do
    {:tool_requests, [%ToolCall{call_id: call_id, tool: tool, args: args}]}
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
        case Regex.run(~r/(page_[\w-]+)/, content) do
          [_, pid] -> {:page, pid}
          nil -> nil
        end
      _ -> nil
    end)
  end

  defp extract_page_scope_id(messages) do
    case extract_page_scope(messages) do
      {:page, pid} -> pid
      _ -> nil
    end
  end

  defp extract_user_content(messages) do
    Enum.find_value(messages, fn
      %Message{role: :user, content: content} -> content
      _ -> nil
    end)
  end

  defp extract_aspect_ratio(messages) do
    content = extract_user_content(messages) || ""

    case Regex.run(~r/(\d+:\d+)/, content) do
      [_, ratio] -> ratio
      _ -> nil
    end
  end

  defp extract_element_id(messages) do
    messages
    |> Enum.find_value(fn
      %Message{role: :user, content: content} when is_binary(content) ->
        case Regex.run(~r/(elem_[0-9a-f-]+)/, content) do
          [_, eid] -> eid
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp extract_asset_path(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: :tool, tool_results: results} ->
        Enum.find_value(results, fn
          %{tool: :generate_image, success: true, data: %{asset_path: ap}} -> ap
          %{tool: :generate_image, success: true, data: %{"asset_path" => ap}} -> ap
          _ -> nil
        end)

      _ ->
        nil
    end)
  end

  defp extract_page_elements(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: :tool, tool_results: results} ->
        Enum.find_value(results, fn
          %{tool: :get_page_elements, success: true, data: %{elements: els}} -> els
          %{tool: :get_page_elements, success: true, data: %{"elements" => els}} -> els
          _ -> nil
        end)

      _ ->
        nil
    end) || []
  end

  defp extract_format_id(messages) do
    content = extract_user_content(messages) || ""

    case Regex.run(~r/format "([^"]+)"|format_id="([^"]+)"/, content) do
      [_, a, ""] -> a
      [_, "", b] -> b
      [_, a] -> a
      _ -> nil
    end
  end
end