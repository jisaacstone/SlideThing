defmodule Slidething.LLM.Provider.Mock do
  @moduledoc """
  Mock LLM provider for testing. Returns predetermined responses
  based on agent type and iteration count.
  """

  @behaviour Slidething.LLM.Provider

  alias Slidething.Agent.{AgentSpec, Message, ToolCall}

  @impl true
  def complete_json(%AgentSpec{name: :planner}, messages) do
    # If we have tool results, use them to generate a smarter plan.
    # Otherwise, call get_page_elements on the target page (if targeting one).
    has_tool_results? = Enum.any?(messages, &(&1.role == :tool))

    if has_tool_results? do
      # Parse tool results to decide which phases to include
      existing_elements = extract_elements_from_tool_results(messages)
      has_content? = Enum.any?(existing_elements, fn el ->
        el["element_type"] in ["title", "text"] || el[:element_type] in ["title", "text"]
      end)

      # Determine if we're targeting an existing page
      existing_book? = Enum.any?(messages, fn msg ->
        is_binary(msg.content) and String.contains?(msg.content, "Existing book:")
      end)

      pages =
        if existing_book? do
          [%{"position" => 1, "metadata" => %{"description" => "Page in existing book"}}]
        else
          [
            %{"position" => 1, "metadata" => %{"description" => "Introduction"}},
            %{"position" => 2, "metadata" => %{"description" => "Development"}},
            %{"position" => 3, "metadata" => %{"description" => "Resolution"}}
          ]
        end

      phases = if has_content? do
        # Page already has text content — skip generate_content, just layout + media
        [
          %{"name" => "generate_layout", "step_type" => "agent", "agent_type" => "layout",
            "scope" => "per_page", "depends_on" => [], "condition" => nil, "max_retries" => 2,
            "context" => %{"note" => "Page already has text content — only arrange existing elements"}},
          %{"name" => "generate_media", "step_type" => "agent", "agent_type" => "media",
            "scope" => "per_element", "depends_on" => ["generate_layout"], "condition" => nil, "max_retries" => 2,
            "context" => nil},
          %{"name" => "validate_layout", "step_type" => "validator", "agent_type" => "validator",
            "scope" => "per_page", "depends_on" => ["generate_layout"], "condition" => nil, "max_retries" => 1,
            "context" => nil},
          %{"name" => "repair_layout", "step_type" => "agent", "agent_type" => "layout",
            "scope" => "per_page", "depends_on" => ["validate_layout"], "condition" => "has_layout_issues", "max_retries" => 2,
            "context" => nil}
        ]
      else
        # No existing content — run full pipeline
        [
          %{"name" => "generate_content", "step_type" => "agent", "agent_type" => "content",
            "scope" => "per_page", "depends_on" => [], "condition" => nil, "max_retries" => 2,
            "context" => nil},
          %{"name" => "generate_layout", "step_type" => "agent", "agent_type" => "layout",
            "scope" => "per_page", "depends_on" => ["generate_content"], "condition" => nil, "max_retries" => 2,
            "context" => nil},
          %{"name" => "generate_media", "step_type" => "agent", "agent_type" => "media",
            "scope" => "per_element", "depends_on" => ["generate_layout"], "condition" => nil, "max_retries" => 2,
            "context" => nil},
          %{"name" => "validate_layout", "step_type" => "validator", "agent_type" => "validator",
            "scope" => "per_page", "depends_on" => ["generate_layout"], "condition" => nil, "max_retries" => 1,
            "context" => nil},
          %{"name" => "repair_layout", "step_type" => "agent", "agent_type" => "layout",
            "scope" => "per_page", "depends_on" => ["validate_layout"], "condition" => "has_layout_issues", "max_retries" => 2,
            "context" => nil}
        ]
      end

      plan = %{
        "book" => %{
          "title" => "Mock Children's Book",
          "metadata" => %{"theme" => "adventure", "target_audience" => "ages 4-6", "style" => "watercolor"}
        },
        "pages" => pages,
        "phases" => phases
      }

      {:final_response, Jason.encode!(plan)}
    else
      # First turn: fetch page elements if we have a target page
      page_id = extract_target_page_id(messages)

      if page_id do
        tool_call("p0", :get_page_elements, %{"page_id" => page_id})
      else
        # No specific page target.
        # For existing books: add 1 page with standard pipeline.
        # For new books: use multi-planner flow (decide_theme → assign_outline → process_pages).
        existing_book? = Enum.any?(messages, fn msg ->
          is_binary(msg.content) and String.contains?(msg.content, "Existing book:")
        end)

        if existing_book? do
          plan = %{
            "book" => %{
              "title" => "Mock Children's Book",
              "metadata" => %{"theme" => "adventure", "target_audience" => "ages 4-6", "style" => "watercolor"}
            },
            "pages" => [%{"position" => 1, "metadata" => %{"description" => "New page added to book"}}],
            "phases" => [
              %{"name" => "generate_content", "step_type" => "agent", "agent_type" => "content",
                "scope" => "per_page", "depends_on" => [], "condition" => nil, "max_retries" => 2, "context" => nil},
              %{"name" => "generate_layout", "step_type" => "agent", "agent_type" => "layout",
                "scope" => "per_page", "depends_on" => ["generate_content"], "condition" => nil, "max_retries" => 2, "context" => nil},
              %{"name" => "generate_media", "step_type" => "agent", "agent_type" => "media",
                "scope" => "per_element", "depends_on" => ["generate_layout"], "condition" => nil, "max_retries" => 2, "context" => nil},
              %{"name" => "validate_layout", "step_type" => "validator", "agent_type" => "validator",
                "scope" => "per_page", "depends_on" => ["generate_layout"], "condition" => nil, "max_retries" => 1, "context" => nil},
              %{"name" => "repair_layout", "step_type" => "agent", "agent_type" => "layout",
                "scope" => "per_page", "depends_on" => ["validate_layout"], "condition" => "has_layout_issues", "max_retries" => 2, "context" => nil}
            ]
          }
          {:final_response, Jason.encode!(plan)}
        else
          # Fresh book creation — use multi-planner flow
          plan = %{
            "book" => %{
              "title" => "Mock Children's Book",
              "metadata" => %{"theme" => "adventure", "target_audience" => "ages 4-6", "style" => "watercolor"}
            },
            "pages" => [
              %{"position" => 1, "metadata" => %{"description" => "Introduction"}},
              %{"position" => 2, "metadata" => %{"description" => "Development"}},
              %{"position" => 3, "metadata" => %{"description" => "Resolution"}}
            ],
            "phases" => [
              %{"name" => "decide_theme",   "step_type" => "planner",     "agent_type" => "planner",       "scope" => "book",     "depends_on" => [],                "condition" => nil, "max_retries" => 1, "context" => nil},
              %{"name" => "assign_outline", "step_type" => "planner",     "agent_type" => "planner",       "scope" => "book",     "depends_on" => ["decide_theme"],   "condition" => nil, "max_retries" => 1, "context" => nil},
              %{"name" => "process_pages",  "step_type" => "agent",       "agent_type" => "page_pipeline", "scope" => "per_page", "depends_on" => ["assign_outline"], "condition" => nil, "max_retries" => 2, "context" => nil},
              %{"name" => "review_book",    "step_type" => "coordinator", "agent_type" => "coordinator",   "scope" => "book",     "depends_on" => ["process_pages"],  "condition" => nil, "max_retries" => 1, "context" => nil},
              %{"name" => "validate_book",  "step_type" => "validator",   "agent_type" => "validator",     "scope" => "per_page", "depends_on" => ["review_book"],    "condition" => nil, "max_retries" => 1, "context" => nil}
            ]
          }
          {:final_response, Jason.encode!(plan)}
        end
      end
    end
  end

  def complete_json(%AgentSpec{name: :page_pipeline}, messages) do
    iteration = count_iterations(messages)
    page_id = extract_page_scope_id(messages)
    existing_image_id = extract_existing_image_id(messages)

    if existing_image_id do
      # Update-image flow: just update the existing element then finish
      case iteration do
        0 ->
          tool_call("pp_0", :update_element, %{
            "element_id" => existing_image_id,
            "content" => "Vibrant fox in forest with sunset colors"
          })
        _ ->
          {:final_response, "Page complete for #{page_id}"}
      end
    else
      case iteration do
        0 ->
          tool_call("pp_0", :create_element, %{
            "page_id" => page_id || "page-unknown",
            "element_type" => "title",
            "content" => "Mock title for #{page_id}"
          })

        1 ->
          tool_call("pp_1", :create_element, %{
            "page_id" => page_id || "page-unknown",
            "element_type" => "text",
            "content" => "Once upon a time on #{page_id}, a brave fox set off on an adventure."
          })

        2 ->
          tool_call("pp_2", :propose_layout, %{
            "page_id" => page_id || "page-unknown",
            "format_id" => "format-web",
            "element_layouts" => [
              %{"element_id" => "title-placeholder", "x" => 0.1, "y" => 0.05, "width" => 0.8, "height" => 0.1},
              %{"element_id" => "text-placeholder",  "x" => 0.1, "y" => 0.18, "width" => 0.8, "height" => 0.3}
            ]
          })

        3 ->
          tool_call("pp_3", :validate_page, %{
            "page_id" => page_id || "page-unknown",
            "format_id" => "format-web"
          })

        _ ->
          {:final_response, "Page complete for #{page_id}"}
      end
    end
  end

  def complete_json(%AgentSpec{name: :coordinator}, _messages) do
    result = %{
      "context" => %{
        "assessment" => "Book content looks coherent. Tone and character are consistent across pages.",
        "issues_found" => []
      },
      "plan_patches" => []
    }

    {:final_response, Jason.encode!(result)}
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

  defp extract_existing_image_id(messages) do
    content = extract_user_content(messages) || ""
    case Regex.run(~r/\[image\] (elem_[a-z0-9_-]+)/, content) do
      [_, id] -> id
      _ -> nil
    end
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

  defp extract_target_page_id(messages) do
    Enum.find_value(messages, fn msg ->
      if is_binary(msg.content) do
        case Regex.run(~r/Target page: (page_[a-z0-9_-]+)/, msg.content) do
          [_, id] -> id
          _ -> nil
        end
      end
    end)
  end

  defp extract_elements_from_tool_results(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: :tool, tool_results: results} ->
        Enum.find_value(results, fn
          %{tool: :get_page_elements, success: true, data: %{elements: els}} -> els
          %{tool: :get_page_elements, success: true, data: %{"elements" => els}} -> els
          _ -> nil
        end)
      _ -> nil
    end) || []
  end
end