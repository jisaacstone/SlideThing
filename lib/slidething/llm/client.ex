defmodule Slidething.LLM.Client do
  @moduledoc """
  Dispatches LLM calls to the correct provider adapter based on AgentSpec.provider.
  """

  require Logger

  alias Slidething.Agent.{AgentSpec, Message}

  @type result :: Slidething.LLM.Provider.result()

  @doc """
  Sends messages to the LLM provider specified in agent_spec.provider
  and returns a structured result.
  """
  @spec complete_json(AgentSpec.t(), [Message.t()]) :: result
  def complete_json(%AgentSpec{provider: provider} = agent_spec, messages) do
    module = provider_module(provider)
    module.complete_json(agent_spec, messages)
  end

  defp provider_module("mock"), do: Slidething.LLM.Provider.Mock
  defp provider_module("gemini"), do: Slidething.LLM.Provider.Gemini
  defp provider_module("openrouter"), do: Slidething.LLM.Provider.OpenRouter

  defp provider_module(unknown) do
    Logger.warning("[LLM.Client] Unknown provider: #{unknown}, falling back to mock")
    Slidething.LLM.Provider.Mock
  end
end