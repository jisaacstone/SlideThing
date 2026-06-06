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
        body
        |> Map.put(:tools, build_openai_tools(agent_spec.tools))
        |> then(&(if agent_spec.tool_choice, do: Map.put(&1, :tool_choice, agent_spec.tool_choice), else: &1))
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

      {:ok, resp} ->
        %{status: status, body: err_body} = resp

        error_info =
          case err_body do
            %{"error" => error} -> error
            _ -> err_body
          end

        err_msg =
          cond do
            is_map(error_info) -> Map.get(error_info, "message", "Provider returned error")
            is_binary(error_info) -> error_info
            true -> "Provider returned error"
          end

        Logger.error("[OpenRouter] API error (status=#{status}): #{inspect(err_body)}")

        debug =
          err_body
          |> Map.delete("messages")
          |> Jason.encode!(pretty: true)

        Logger.debug("[OpenRouter] Full error response: #{debug}")
        {:error, err_msg}

      {:error, reason} ->
        Logger.error("[OpenRouter] HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def messages_to_openai_messages(messages) do
    Enum.flat_map(messages, fn msg ->
      case msg do
        %Message{role: :system} ->
          [%{role: "system", content: msg.content || ""}]

        %Message{role: :user} ->
          [%{role: "user", content: msg.content || ""}]

        %Message{role: :assistant, content: content, tool_calls: calls} when not is_nil(calls) ->
          base = %{role: "assistant", content: content}
          openai_calls = Enum.map(calls, &tool_call_to_openai/1)
          [Map.put(base, :tool_calls, openai_calls)]

        %Message{role: :assistant} ->
          [%{role: "assistant", content: msg.content || ""}]

        %Message{role: :tool, tool_results: results} when not is_nil(results) ->
          Enum.map(results, fn r ->
            %{
              role: "tool",
              content: Jason.encode!(%{success: r.success, data: r.data, error: r.error}),
              tool_call_id: r.call_id || "call_tool"
            }
          end)

        %Message{role: :tool} ->
          [%{role: "tool", content: "", tool_call_id: "unknown"}]
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

  def build_openai_tools(tools) do
    Enum.map(tools, fn tool ->
      schema =
        case Slidething.Tool.Schemas.get(tool) do
          nil ->
            Logger.warning("[OpenRouter] Unknown tool schema: #{tool}")
            %{name: to_string(tool), description: "Tool: #{tool}", parameters: %{type: "object", properties: %{}}}
          s ->
            s
        end

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

  def parse_choice(%{"message" => %{"tool_calls" => calls}} = _choice) when not is_nil(calls) do
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

  def parse_choice(%{"message" => %{"content" => text}}) when not is_nil(text) and text != "" do
    {:final_response, text}
  end

  def parse_choice(%{"message" => _}) do
    {:final_response, ""}
  end
end