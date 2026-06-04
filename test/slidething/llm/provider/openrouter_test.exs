defmodule Slidething.LLM.Provider.OpenRouterTest do
  use ExUnit.Case, async: true

  alias Slidething.Agent.{AgentSpec, Message, ToolCall, ToolResult}
  alias Slidething.LLM.Provider.OpenRouter

  @test_spec %AgentSpec{
    name: :planner,
    provider: "openrouter",
    model: "test-model",
    temperature: 0.2,
    max_tokens: 4000,
    max_iterations: 5,
    system_prompt: "Test",
    tools: [:get_book, :create_pages]
  }

  describe "messages_to_openai_messages/1" do
    test "serializes system message" do
      messages = [%Message{role: :system, content: "You are a helper."}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "system", content: "You are a helper."}] = result
    end

    test "serializes user message" do
      messages = [%Message{role: :user, content: "Plan: hello"}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "user", content: "Plan: hello"}] = result
    end

    test "serializes assistant message with tool_calls" do
      calls = [
        %ToolCall{call_id: "call_1", tool: :get_book, args: %{"book_id" => "book_abc"}},
        %ToolCall{call_id: "call_2", tool: :create_pages, args: %{"book_id" => "book_abc", "count" => 3}}
      ]

      messages = [%Message{role: :assistant, content: "", tool_calls: calls}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "assistant", content: "", tool_calls: [
        %{id: "call_1", type: "function", function: %{name: "get_book", arguments: json}},
        %{id: "call_2", type: "function", function: %{name: "create_pages", arguments: json2}}
      ]}] = result

      assert Jason.decode!(json) == %{"book_id" => "book_abc"}
      assert Jason.decode!(json2) == %{"book_id" => "book_abc", "count" => 3}
    end

    test "serializes plain assistant message (no tool_calls)" do
      messages = [%Message{role: :assistant, content: "Hello!"}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "assistant", content: "Hello!"}] = result
    end

    test "serializes single tool result with call_id" do
      results = [%ToolResult{call_id: "call_x", tool: :get_book, success: true, data: %{id: "abc"}, error: nil}]
      messages = [%Message{role: :tool, tool_results: results}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "tool", tool_call_id: "call_x", content: content}] = result
      decoded = Jason.decode!(content)
      assert decoded["success"] == true
      assert decoded["data"] == %{"id" => "abc"}
      assert decoded["error"] == nil
    end

    test "serializes single tool result with nil call_id (fallback)" do
      results = [%ToolResult{call_id: nil, tool: :get_book, success: true, data: %{}, error: nil}]
      messages = [%Message{role: :tool, tool_results: results}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "tool", tool_call_id: "call_tool", content: _}] = result
    end

    test "serializes multiple tool results as separate messages" do
      results = [
        %ToolResult{call_id: "call_1", tool: :get_book, success: true, data: %{id: "abc"}, error: nil},
        %ToolResult{call_id: "call_2", tool: :create_pages, success: true, data: nil, error: nil}
      ]
      messages = [%Message{role: :tool, tool_results: results}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert length(result) == 2
      assert Enum.at(result, 0)[:tool_call_id] == "call_1"
      assert Enum.at(result, 0)[:role] == "tool"
      assert Enum.at(result, 1)[:tool_call_id] == "call_2"
      assert Enum.at(result, 1)[:role] == "tool"
    end

    test "serializes failed tool result" do
      results = [%ToolResult{call_id: "call_e", tool: :get_book, success: false, data: nil, error: "not found"}]
      messages = [%Message{role: :tool, tool_results: results}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "tool", tool_call_id: "call_e", content: content}] = result
      decoded = Jason.decode!(content)
      assert decoded["success"] == false
      assert decoded["error"] == "not found"
    end

    test "serializes tool message with nil results" do
      messages = [%Message{role: :tool, tool_results: nil}]
      result = OpenRouter.messages_to_openai_messages(messages)

      assert [%{role: "tool", content: "", tool_call_id: "unknown"}] = result
    end

    test "serializes full conversation: system → user → assistant(tool_calls) → tool" do
      calls = [%ToolCall{call_id: "call_abc", tool: :get_book, args: %{"book_id" => "book_1"}}]
      results = [%ToolResult{call_id: "call_abc", tool: :get_book, success: true, data: %{id: "book_1"}, error: nil}]

      messages = [
        %Message{role: :system, content: "System prompt"},
        %Message{role: :user, content: "Plan: create a book"},
        %Message{role: :assistant, content: "", tool_calls: calls},
        %Message{role: :tool, tool_results: results}
      ]

      result = OpenRouter.messages_to_openai_messages(messages)

      assert length(result) == 4
      assert Enum.at(result, 0) == %{role: "system", content: "System prompt"}
      assert Enum.at(result, 1) == %{role: "user", content: "Plan: create a book"}
      assert Enum.at(result, 2)[:role] == "assistant"
      assert Enum.at(result, 2)[:tool_calls] |> length() == 1
      assert Enum.at(result, 3)[:role] == "tool"
      assert Enum.at(result, 3)[:tool_call_id] == "call_abc"
    end

    test "all serialized messages are JSON-encodable" do
      calls = [%ToolCall{call_id: "call_1", tool: :get_book, args: %{"book_id" => "abc"}}]
      results = [%ToolResult{call_id: "call_1", tool: :get_book, success: true, data: %{}, error: nil}]

      messages = [
        %Message{role: :system, content: "System"},
        %Message{role: :user, content: "User"},
        %Message{role: :assistant, content: "", tool_calls: calls},
        %Message{role: :tool, tool_results: results}
      ]

      openai_messages = OpenRouter.messages_to_openai_messages(messages)
      encoded = Jason.encode!(openai_messages)
      assert is_binary(encoded)
    end
  end

  describe "parse_choice/1" do
    test "parses native tool_calls response" do
      choice = %{
        "message" => %{
          "tool_calls" => [
            %{
              "id" => "call_abc",
              "function" => %{
                "name" => "get_book",
                "arguments" => ~s({"book_id":"book_1"})
              }
            }
          ]
        }
      }

      assert {:tool_requests, [%ToolCall{call_id: "call_abc", tool: :get_book, args: %{"book_id" => "book_1"}}]} =
               OpenRouter.parse_choice(choice)
    end

    test "parses text content as final_response (plain text)" do
      choice = %{"message" => %{"content" => "The plan is complete."}}

      assert {:final_response, "The plan is complete."} = OpenRouter.parse_choice(choice)
    end

    test "returns text content verbatim even when it looks like JSON" do
      choice = %{"message" => %{"content" => ~s({"type":"final_response","message":"Done"})}}

      assert {:final_response, ~s({"type":"final_response","message":"Done"})} =
               OpenRouter.parse_choice(choice)
    end

    test "handles empty message content" do
      choice = %{"message" => %{"content" => ""}}

      assert {:final_response, ""} = OpenRouter.parse_choice(choice)
    end

    test "handles message with nil content" do
      choice = %{"message" => %{}}

      assert {:final_response, ""} = OpenRouter.parse_choice(choice)
    end
  end

  describe "build_openai_tools/1" do
    test "converts known tools to OpenAI function definitions" do
      result = OpenRouter.build_openai_tools([:get_book, :create_pages])

      assert length(result) == 2
      assert Enum.at(result, 0)[:type] == "function"
      assert Enum.at(result, 0)[:function][:name] == "get_book"
      assert Enum.at(result, 0)[:function][:parameters]
    end

    test "handles unknown tools with fallback" do
      result = OpenRouter.build_openai_tools([:unknown_tool])

      assert length(result) == 1
      assert Enum.at(result, 0)[:function][:name] == "unknown_tool"
      assert Enum.at(result, 0)[:function][:parameters] == %{type: "object", properties: %{}}
    end
  end

  describe "complete_json/2 with missing API key" do
    test "returns error when OPENROUTER_API_KEY is not set" do
      key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")

      try do
        assert {:error, :missing_api_key} = OpenRouter.complete_json(@test_spec, [])
      after
        if key, do: System.put_env("OPENROUTER_API_KEY", key)
      end
    end
  end
end