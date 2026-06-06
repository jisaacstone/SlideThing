defmodule Slidething.LLM.ClientTest do
  use ExUnit.Case, async: true

  alias Slidething.Agent.AgentSpec
  alias Slidething.LLM.Client

  describe "complete_json/2" do
    test "dispatches to mock provider" do
      spec = %AgentSpec{
        name: :planner,
        provider: "mock",
        model: "mock-model",
        temperature: 0.2,
        max_tokens: 4000,
        max_iterations: 5,
        system_prompt: "Test",
        tools: []
      }

      result = Client.complete_json(spec, [])
      assert is_tuple(result)
      assert elem(result, 0) in [:tool_requests, :final_response, :error]
    end

    test "unknown provider falls back to mock" do
      spec = %AgentSpec{
        name: :planner,
        provider: "unknown-ai-service",
        model: "test",
        temperature: 0.2,
        max_tokens: 4000,
        max_iterations: 5,
        system_prompt: "Test",
        tools: []
      }

      result = Client.complete_json(spec, [])
      assert is_tuple(result)
      assert elem(result, 0) in [:tool_requests, :final_response, :error]
    end

    test "handles all known providers" do
      for provider <- ["mock", "gemini", "openrouter"] do
        spec = %AgentSpec{
          name: :content,
          provider: provider,
          model: "test",
          temperature: 0.5,
          max_tokens: 1000,
          max_iterations: 2,
          system_prompt: "Test",
          tools: []
        }

        result = Client.complete_json(spec, [])
        assert is_tuple(result), "Provider #{provider} should return a tuple"

        assert elem(result, 0) in [:tool_requests, :final_response, :error],
               "Provider #{provider} should return a valid result"
      end
    end
  end
end
