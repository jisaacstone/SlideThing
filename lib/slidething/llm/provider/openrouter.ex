defmodule Slidething.LLM.Provider.OpenRouter do
  @moduledoc """
  OpenRouter provider adapter via OpenAI-compatible chat/completions API.

  Uses provider-native tool calling. Env var: OPENROUTER_API_KEY.
  """

  @behaviour Slidething.LLM.Provider

  require Logger

  alias Slidething.Agent.{Message, ToolCall}

  @impl true
  def complete_json(agent_spec, messages) do
    api_key = System.get_env("OPENROUTER_API_KEY")

    unless api_key do
      Logger.error("[OpenRouter] OPENROUTER_API_KEY not set")
      {:error, :missing_api_key}
    else
      do_complete(agent_spec, messages, api_key)
    end
  end

  defp do_complete(agent_spec, messages, api_key) do
    base_url = Application.get_env(:slidething, :openrouter_base_url, "https://openrouter.ai/api/v1")
    url = "#{base_url}/chat/completions"

    body = %{
      model: agent_spec.model,
      messages: messages_to_openai_messages(messages),
      temperature: agent_spec.temperature,
      max_tokens: agent_spec.max_tokens
    }

    body =
      if Enum.empty?(agent_spec.tools) do
        body
      else
        Map.put(body, :tools, build_openai_tools(agent_spec.tools))
      end

    Logger.debug("[OpenRouter] Request: model=#{agent_spec.model}")

    case Req.post(url,
           json: body,
           headers: [
             {"content-type", "application/json"},
             {"authorization", "Bearer #{api_key}"},
             {"HTTP-Referer", "https://slidething.dev"},
             {"X-Title", "Slidething"}
           ]
         ) do
      {:ok, %{body: %{"choices" => [choice | _]}}} ->
        parse_choice(choice)

      {:ok, %{body: %{"error" => %{"message" => msg}}}} ->
        Logger.error("[OpenRouter] API error: #{msg}")
        {:error, msg}

      {:error, reason} ->
        Logger.error("[OpenRouter] HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp messages_to_openai_messages(messages) do
    Enum.map(messages, fn msg ->
      case msg do
        %Message{role: :system} ->
          %{role: "system", content: msg.content || ""}

        %Message{role: :user} ->
          %{role: "user", content: msg.content || ""}

        %Message{role: :assistant, content: content, tool_calls: calls} when not is_nil(calls) ->
          base = %{role: "assistant", content: content}
          openai_calls = Enum.map(calls, &tool_call_to_openai/1)
          Map.put(base, :tool_calls, openai_calls)

        %Message{role: :assistant} ->
          %{role: "assistant", content: msg.content || ""}

        %Message{role: :tool, tool_results: results} when not is_nil(results) ->
          case results do
            [single_result] ->
              %{
                role: "tool",
                content: Jason.encode!(%{success: single_result.success, data: single_result.data, error: single_result.error}),
                tool_call_id: single_result.call_id
              }

            _ ->
              %{
                role: "tool",
                content: Jason.encode!(Enum.map(results, fn r -> %{tool: r.tool, success: r.success, data: r.data, error: r.error} end)),
                tool_call_id: "batch"
              }
          end

        %Message{role: :tool} ->
          %{role: "tool", content: "", tool_call_id: "unknown"}
      end
    end)
  end

  defp tool_call_to_openai(%ToolCall{call_id: call_id, tool: tool, args: args}) do
    %{
      id: call_id || "call_#{System.unique_integer([:positive])}",
      type: "function",
      function: %{
        name: to_string(tool),
        arguments: Jason.encode!(args)
      }
    }
  end

  defp build_openai_tools(tools) do
    Enum.map(tools, fn tool ->
      schema = tool_schema(tool)
      %{
        type: "function",
        function: %{
          name: schema.name,
          description: schema.description,
          parameters: schema.parameters
        }
      }
    end)
  end

  defp parse_choice(%{"message" => %{"tool_calls" => calls}} = _choice) when not is_nil(calls) do
    parsed =
      Enum.map(calls, fn call ->
        %ToolCall{
          call_id: call["id"],
          tool: String.to_atom(call["function"]["name"]),
          args: Jason.decode!(call["function"]["arguments"])
        }
      end)

    Logger.debug("[OpenRouter] Tool calls: #{length(parsed)}")
    {:tool_requests, parsed}
  end

  defp parse_choice(%{"message" => %{"content" => text}}) when not is_nil(text) and text != "" do
    case Jason.decode(text) do
      {:ok, %{"type" => "tool_requests", "calls" => calls}} ->
        parsed =
          Enum.map(calls, fn call ->
            %ToolCall{
              call_id: Map.get(call, "call_id"),
              tool: String.to_atom(call["tool"]),
              args: call["args"] || %{}
            }
          end)

        {:tool_requests, parsed}

      {:ok, %{"type" => "patch_proposal", "patch" => patch}} ->
        {:patch_proposal, patch}

      {:ok, %{"type" => "final_response", "message" => message}} ->
        {:final_response, message}

      _ ->
        {:final_response, text}
    end
  end

  defp parse_choice(%{"message" => _}) do
    {:final_response, ""}
  end

  defp tool_schema(:get_book) do
    %{
      name: "get_book",
      description: "Get the current book data",
      parameters: %{type: "object", properties: %{}, required: []}
    }
  end

  defp tool_schema(:create_element) do
    %{
      name: "create_element",
      description: "Create a new element on a page",
      parameters: %{
        type: "object",
        properties: %{
          type: %{type: "string", description: "Element type: text, title, image"},
          content: %{type: "string", description: "Content for the element"},
          page_id: %{type: "string", description: "Target page ID"}
        },
        required: ["type"]
      }
    }
  end

  defp tool_schema(:mock_get_book) do
    tool_schema(:get_book)
  end

  defp tool_schema(:mock_create_element) do
    tool_schema(:create_element)
  end

  defp tool_schema(tool) do
    Logger.warning("[OpenRouter] Unknown tool: #{tool}, sending empty schema")
    %{name: to_string(tool), description: "Tool: #{tool}", parameters: %{type: "object", properties: %{}}}
  end
end