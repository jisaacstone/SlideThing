defmodule Slidething.LLM.Provider.Mock do
  @moduledoc """
  Mock LLM provider for testing. Returns predetermined responses
  based on agent type and iteration count.
  """

  @behaviour Slidething.LLM.Provider

  alias Slidething.Agent.{AgentSpec, Message, ToolCall}

  @impl true
  def complete_json(%AgentSpec{name: :planner}, _messages) do
    plan = %{
      "context" => %{
        "theme" => "adventure",
        "assessment" => "Theme and outline decided"
      }
    }

    {:tool_requests,
     [%ToolCall{call_id: "planner_0", tool: :submit_plan, args: %{"plan" => plan}}]}
  end

  def complete_json(%AgentSpec{name: :planner_decide}, messages) do
    # Decide if context gathering is needed
    has_existing_book? =
      Enum.any?(messages, fn msg ->
        is_binary(msg.content) and String.contains?(msg.content, "Existing book:")
      end)

    {:final_response, Jason.encode!(%{"needs_context" => has_existing_book?})}
  end

  def complete_json(%AgentSpec{name: :planner_gather}, _messages) do
    # Return a summary of gathered context
    {:final_response,
     "Book has 3 pages. Pages 1-3 have partial content. Recent prompts show layout and media work needed."}
  end

  def complete_json(%AgentSpec{name: :planner_emit}, messages) do
    existing_book? =
      Enum.any?(messages, fn msg ->
        is_binary(msg.content) and String.contains?(msg.content, "Existing book:")
      end)

    has_target_page? =
      Enum.any?(messages, fn msg ->
        is_binary(msg.content) and String.contains?(msg.content, "Target page:")
      end)

    plan =
      cond do
        existing_book? and has_target_page? ->
          target_page_id = extract_target_page_id(messages)
          image_elem_id = extract_image_element_id(messages)

          media_config =
            if image_elem_id do
              %{
                "op" => "update",
                "page_id" => target_page_id,
                "element_id" => image_elem_id,
                "aspect_ratio" => "1:1"
              }
            else
              %{"op" => "create", "page_id" => target_page_id, "aspect_ratio" => "1:1"}
            end

          %{
            "context" => "Edit specific page content and image",
            "phases" => [
              %{
                "name" => "generate_content",
                "step_type" => "agent",
                "agent_type" => "content",
                "scope" => "book",
                "config" => %{
                  "op" => "create",
                  "element_type" => "text",
                  "page_id" => target_page_id
                },
                "depends_on" => [],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "generate_media",
                "step_type" => "agent",
                "agent_type" => "media",
                "scope" => "book",
                "config" => media_config,
                "depends_on" => ["generate_content"],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "generate_layout",
                "step_type" => "agent",
                "agent_type" => "layout",
                "scope" => "per_page",
                "depends_on" => ["generate_media"],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "validate_layout",
                "step_type" => "validator",
                "agent_type" => "validator",
                "scope" => "per_page",
                "depends_on" => ["generate_layout"],
                "condition" => nil,
                "max_retries" => 1,
                "context" => nil
              },
              %{
                "name" => "repair_layout",
                "step_type" => "agent",
                "agent_type" => "layout",
                "scope" => "per_page",
                "depends_on" => ["validate_layout"],
                "condition" => "has_layout_issues",
                "max_retries" => 2,
                "context" => nil
              }
            ]
          }

        existing_book? ->
          %{
            "context" => "Edit existing book — add a new page",
            "phases" => [
              %{
                "name" => "generate_content",
                "step_type" => "agent",
                "agent_type" => "content",
                "scope" => "book",
                "config" => %{"op" => "create", "element_type" => "text", "page_index" => 0},
                "depends_on" => [],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "generate_media",
                "step_type" => "agent",
                "agent_type" => "media",
                "scope" => "book",
                "config" => %{"op" => "create", "page_index" => 0, "aspect_ratio" => "1:1"},
                "depends_on" => ["generate_content"],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "generate_layout",
                "step_type" => "agent",
                "agent_type" => "layout",
                "scope" => "per_page",
                "depends_on" => ["generate_media"],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "validate_layout",
                "step_type" => "validator",
                "agent_type" => "validator",
                "scope" => "per_page",
                "depends_on" => ["generate_layout"],
                "condition" => nil,
                "max_retries" => 1,
                "context" => nil
              },
              %{
                "name" => "repair_layout",
                "step_type" => "agent",
                "agent_type" => "layout",
                "scope" => "per_page",
                "depends_on" => ["validate_layout"],
                "condition" => "has_layout_issues",
                "max_retries" => 2,
                "context" => nil
              }
            ]
          }

        true ->
          %{
            "context" => %{"book_title" => "Mock Book", "theme" => "adventure"},
            "phases" => [
              %{
                "name" => "decide_theme",
                "step_type" => "planner",
                "agent_type" => "planner",
                "scope" => "book",
                "depends_on" => [],
                "condition" => nil,
                "max_retries" => 1,
                "context" => nil
              },
              %{
                "name" => "assign_outline",
                "step_type" => "planner",
                "agent_type" => "planner",
                "scope" => "book",
                "depends_on" => ["decide_theme"],
                "condition" => nil,
                "max_retries" => 1,
                "context" => nil
              },
              %{
                "name" => "generate_content",
                "step_type" => "agent",
                "agent_type" => "content",
                "scope" => "book",
                "config" => %{"op" => "create", "element_type" => "text", "page_index" => 0},
                "depends_on" => ["assign_outline"],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "generate_media",
                "step_type" => "agent",
                "agent_type" => "media",
                "scope" => "book",
                "config" => %{"op" => "create", "page_index" => 0, "aspect_ratio" => "1:1"},
                "depends_on" => ["generate_content"],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "generate_layout",
                "step_type" => "agent",
                "agent_type" => "layout",
                "scope" => "per_page",
                "depends_on" => ["generate_media"],
                "condition" => nil,
                "max_retries" => 2,
                "context" => nil
              },
              %{
                "name" => "review_book",
                "step_type" => "coordinator",
                "agent_type" => "coordinator",
                "scope" => "book",
                "depends_on" => ["generate_layout"],
                "condition" => nil,
                "max_retries" => 1,
                "context" => nil
              },
              %{
                "name" => "validate_book",
                "step_type" => "validator",
                "agent_type" => "validator",
                "scope" => "per_page",
                "depends_on" => ["review_book"],
                "condition" => nil,
                "max_retries" => 1,
                "context" => nil
              }
            ]
          }
      end

    {:tool_requests, [%ToolCall{call_id: "emit_0", tool: :submit_plan, args: %{"plan" => plan}}]}
  end

  def complete_json(%AgentSpec{name: :coordinator}, _messages) do
    result = %{
      "context" => %{
        "assessment" =>
          "Book content looks coherent. Tone and character are consistent across pages.",
        "issues_found" => []
      },
      "plan_patches" => []
    }

    {:final_response, Jason.encode!(result)}
  end

  def complete_json(%AgentSpec{name: :content}, _messages) do
    {:final_response, "Mock body text for the page."}
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

  defp count_iterations(messages) do
    Enum.count(messages, fn
      %Message{role: :tool} -> true
      _ -> false
    end)
  end

  defp extract_page_scope(messages) do
    messages
    |> Enum.find_value(fn
      %Message{role: :user, content: content} ->
        case Regex.run(~r/(page_[\w-]+)/, content) do
          [_, pid] -> {:page, pid}
          nil -> nil
        end

      _ ->
        nil
    end)
  end

  defp extract_page_scope_id(messages) do
    case extract_page_scope(messages) do
      {:page, pid} -> pid
      _ -> nil
    end
  end

  defp extract_target_page_id(messages) do
    Enum.find_value(messages, fn
      %Message{role: :user, content: content} when is_binary(content) ->
        case Regex.run(~r/Target page: (page_[\w-]+)/, content) do
          [_, pid] -> pid
          _ -> nil
        end

      %Message{role: :system, content: content} when is_binary(content) ->
        case Regex.run(~r/Target page: (page_[\w-]+)/, content) do
          [_, pid] -> pid
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp extract_image_element_id(messages) do
    Enum.find_value(messages, fn
      %Message{role: :user, content: content} when is_binary(content) ->
        case Regex.run(~r/\[image\] (elem_[\w-]+)/, content) do
          [_, eid] -> eid
          _ -> nil
        end

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
    content =
      Enum.find_value(messages, fn
        %Message{role: :user, content: c} -> c
        _ -> nil
      end) || ""

    case Regex.run(~r/format "([^"]+)"|format_id="([^"]+)"/, content) do
      [_, a, ""] -> a
      [_, "", b] -> b
      [_, a] -> a
      _ -> nil
    end
  end
end
