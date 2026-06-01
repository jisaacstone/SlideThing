defmodule Slidething.LLM.Provider.Gemini do
  @moduledoc """
  Google Gemini provider adapter.

  Uses the generateContent API with native functionDeclarations.
  Env var: GOOGLE_API_KEY.
  """

  @behaviour Slidething.LLM.Provider

  require Logger

  alias Slidething.Agent.{Message, ToolCall}

  @base_url "https://generativelanguage.googleapis.com/v1beta"

  @impl true
  def complete_json(agent_spec, messages) do
    api_key = System.get_env("GOOGLE_API_KEY")

    unless api_key do
      Logger.error("[Gemini] GOOGLE_API_KEY not set")
      {:error, :missing_api_key}
    else
      do_complete(agent_spec, messages, api_key)
    end
  end

  defp do_complete(agent_spec, messages, api_key) do
    url = "#{@base_url}/models/#{agent_spec.model}:generateContent?key=#{api_key}"

    body = %{
      systemInstruction: %{
        role: "user",
        parts: [%{text: system_prompt_text(messages)}]
      },
      contents: messages_to_gemini_contents(messages),
      generationConfig: %{
        temperature: agent_spec.temperature,
        maxOutputTokens: agent_spec.max_tokens
      }
    }

    body =
      if Enum.empty?(agent_spec.tools) do
        body
      else
        Map.put(body, :tools, [%{functionDeclarations: build_function_declarations(agent_spec.tools)}])
      end

    Logger.debug("[Gemini] Request: model=#{agent_spec.model}")

    case Req.post(url, json: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{body: %{"candidates" => candidates}}} ->
        parse_candidates(candidates)

      {:ok, %{body: %{"error" => %{"message" => msg}}}} ->
        Logger.error("[Gemini] API error: #{msg}")
        {:error, msg}

      {:error, reason} ->
        Logger.error("[Gemini] HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp system_prompt_text(messages) do
    Enum.find_value(messages, fn
      %Message{role: :system, content: content} -> content
      _ -> nil
    end) || "You are a helpful assistant."
  end

  defp messages_to_gemini_contents(messages) do
    messages
    |> Enum.reject(&(&1.role == :system))
    |> Enum.flat_map(&message_to_gemini_parts/1)
    |> Enum.group_by(& &1.role, & &1.parts)
    |> Enum.map(fn {role, part_lists} ->
      %{role: gemini_role(role), parts: List.flatten(part_lists)}
    end)
  end

  defp message_to_gemini_parts(%Message{role: role, content: content, tool_calls: calls, tool_results: _results})
       when role in [:assistant, :model] and not is_nil(calls) do
    texts =
      if content do
        [%{text: content}]
      else
        []
      end

    call_parts = Enum.map(calls, &function_call_part/1)
    [%{role: :model, parts: texts ++ call_parts}]
  end

  defp message_to_gemini_parts(%Message{role: :assistant} = msg) do
    [%{role: :model, parts: [%{text: msg.content || ""}]}]
  end

  defp message_to_gemini_parts(%Message{role: :user} = msg) do
    [%{role: :user, parts: [%{text: msg.content || ""}]}]
  end

  defp message_to_gemini_parts(%Message{role: :tool, tool_results: results}) do
    parts = Enum.map(results, fn result ->
      %{functionResponse: %{
        name: to_string(result.tool),
        response: %{success: result.success, data: result.data, error: result.error}
      }}
    end)

    [%{role: :tool, parts: parts}]
  end

  defp function_call_part(%ToolCall{tool: tool, args: args}) do
    %{functionCall: %{name: to_string(tool), args: args}}
  end

  defp gemini_role(:assistant), do: "model"
  defp gemini_role(:model), do: "model"
  defp gemini_role(:tool), do: "tool"
  defp gemini_role(role), do: to_string(role)

  defp parse_candidates([%{"content" => %{"parts" => parts}} | _]) do
    parse_parts(parts)
  end

  defp parse_candidates([]) do
    {:error, :empty_response}
  end

  defp parse_parts(parts) do
    tool_calls =
      parts
      |> Enum.filter(&Map.has_key?(&1, "functionCall"))
      |> Enum.map(fn %{"functionCall" => fc} ->
        %ToolCall{
          call_id: nil,
          tool: String.to_atom(fc["name"]),
          args: fc["args"] || %{}
        }
      end)

    text_content =
      parts
      |> Enum.filter(&Map.has_key?(&1, "text"))
      |> Enum.map_join("\n", & &1["text"])

    if !Enum.empty?(tool_calls) do
      Logger.debug("[Gemini] Tool calls: #{length(tool_calls)}")
      {:tool_requests, tool_calls}
    else
      case Jason.decode(text_content) do
        {:ok, %{"type" => "patch_proposal", "patch" => patch}} ->
          {:patch_proposal, patch}

        {:ok, %{"type" => "final_response", "message" => message}} ->
          {:final_response, message}

        {:ok, %{"book_id" => _}} ->
          {:final_response, text_content}

        {:ok, _json} ->
          {:final_response, text_content}

        {:error, _} ->
          {:final_response, text_content}
      end
    end
  end

  defp build_function_declarations(tools) do
    tools
    |> Enum.map(fn tool ->
      case Slidething.Tool.Schemas.get(tool) do
        nil ->
          Logger.warning("[Gemini] Unknown tool schema: #{tool}")
          %{name: to_string(tool), description: "Tool: #{tool}", parameters: %{type: "object", properties: %{}}}
        schema ->
          schema
      end
    end)
  end
end