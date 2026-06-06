defmodule Slidething.Image.Provider.Gemini do
  @moduledoc """
  Google Gemini / Imagen image generation provider.

  Calls the Generative Language API's `:predict` endpoint and stores the returned
  base64-encoded PNG bytes via `Slidething.AssetStore`.

  Env var: GOOGLE_API_KEY.
  """

  @behaviour Slidething.Image.Provider

  require Logger

  @base_url "https://generativelanguage.googleapis.com/v1beta"

  @impl true
  def generate(model, prompt, aspect_ratio) do
    case System.get_env("GOOGLE_API_KEY") do
      nil ->
        Logger.error("[Image.Gemini] GOOGLE_API_KEY not set")
        {:error, :missing_api_key}

      api_key ->
        do_generate(model, prompt, aspect_ratio, api_key)
    end
  end

  defp do_generate(model, prompt, aspect_ratio, api_key) do
    url = "#{@base_url}/models/#{model}:predict?key=#{api_key}"

    body = %{
      instances: [%{prompt: prompt}],
      parameters: %{aspectRatio: aspect_ratio, sampleCount: 1}
    }

    Logger.debug("[Image.Gemini] Generating model=#{model} aspect=#{aspect_ratio}")

    case Req.post(url,
           json: body,
           receive_timeout: 120_000,
           headers: [{"content-type", "application/json"}]
         ) do
      {:ok, %{body: %{"predictions" => [%{"bytesBase64Encoded" => b64} | _]}}} ->
        case Base.decode64(b64) do
          {:ok, bytes} -> Slidething.AssetStore.store(bytes, "imagen.png")
          :error -> {:error, :invalid_base64}
        end

      {:ok, %{body: %{"error" => %{"message" => msg}}}} ->
        Logger.error("[Image.Gemini] API error: #{msg}")
        {:error, msg}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[Image.Gemini] Unexpected response status=#{status} body=#{inspect(body)}")
        {:error, {:unexpected_response, status}}

      {:error, reason} ->
        Logger.error("[Image.Gemini] HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
