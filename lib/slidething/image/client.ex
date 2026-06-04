defmodule Slidething.Image.Client do
  @moduledoc """
  Dispatches image generation requests to the configured `Slidething.Image.Provider`.
  """

  require Logger

  @spec generate(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def generate(provider, model, prompt, aspect_ratio) do
    module = provider_module(provider)
    module.generate(model, prompt, aspect_ratio)
  end

  defp provider_module("mock"), do: Slidething.Image.Provider.Mock
  defp provider_module("gemini"), do: Slidething.Image.Provider.Gemini
  defp provider_module("openrouter"), do: Slidething.Image.Provider.OpenRouter

  defp provider_module(unknown) do
    Logger.warning("[Image.Client] Unknown provider: #{unknown}, falling back to mock")
    Slidething.Image.Provider.Mock
  end
end
