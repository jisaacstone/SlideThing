defmodule Slidething.Image.Provider.OpenRouter do
  @moduledoc """
  OpenRouter image generation provider via the chat/completions endpoint.

  Uses the same OPENROUTER_API_KEY env var as the LLM provider.
  Models with image output (e.g. `black-forest-labs/flux-schnell`,
  `black-forest-labs/flux.2-flex`) are called with `modalities: ["image"]`.
  """

  @behaviour Slidething.Image.Provider

  require Logger

  @base_url "https://openrouter.ai/api/v1"

  @impl true
  def generate(model, prompt, aspect_ratio) do
    case System.get_env("OPENROUTER_API_KEY") do
      nil ->
        Logger.error("[Image.OpenRouter] OPENROUTER_API_KEY not set")
        {:error, :missing_api_key}

      api_key ->
        do_generate(model, prompt, aspect_ratio, api_key)
    end
  end

  defp do_generate(model, prompt, aspect_ratio, api_key) do
    url = "#{@base_url}/chat/completions"

    body = %{
      model: model,
      messages: [%{role: "user", content: prompt}],
      modalities: ["image"]
    }

    body =
      if aspect_ratio && aspect_ratio != "1:1" do
        Map.put(body, :image_config, %{aspect_ratio: aspect_ratio})
      else
        body
      end

    Logger.debug("[Image.OpenRouter] Generating model=#{model} aspect=#{aspect_ratio}")

    case Req.post(url,
           json: body,
           receive_timeout: 120_000,
           headers: [
             {"content-type", "application/json"},
             {"authorization", "Bearer #{api_key}"},
             {"HTTP-Referer", "https://slidething.dev"},
             {"X-Title", "Slidething"}
           ]
         ) do
      {:ok, %{body: %{"choices" => [%{"message" => msg} | _]}}} when is_map(msg) ->
        extract_image(msg)

      {:ok, %{body: %{"error" => error}}} ->
        msg = Map.get(error, "message", inspect(error))
        Logger.error("[Image.OpenRouter] API error: #{msg}")
        {:error, msg}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "[Image.OpenRouter] Unexpected response status=#{status} body=#{inspect(body)}"
        )

        {:error, {:unexpected_response, status}}

      {:error, reason} ->
        Logger.error("[Image.OpenRouter] HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_image(%{"images" => [%{"image_url" => %{"url" => data_uri}} | _]}) do
    case parse_data_uri(data_uri) do
      {:ok, ext, bytes} -> Slidething.AssetStore.store(bytes, "image#{ext}")
      :error -> {:error, :invalid_data_uri}
    end
  end

  defp extract_image(%{"content" => content}) when is_binary(content) do
    case Regex.run(~r/!\[.*?\]\((data:image\/[^;]+;base64,([^)]+))\)/, content) do
      [_, _data_uri, b64] ->
        case Base.decode64(b64) do
          {:ok, bytes} -> Slidething.AssetStore.store(bytes, "image.png")
          :error -> {:error, :invalid_base64}
        end

      _ ->
        Logger.error("[Image.OpenRouter] No image found in assistant message")
        {:error, :no_image}
    end
  end

  defp extract_image(_msg) do
    Logger.error("[Image.OpenRouter] No image found in assistant message")
    {:error, :no_image}
  end

  defp parse_data_uri("data:image/" <> rest) do
    case String.split(rest, ";base64,", parts: 2) do
      [fmt, b64] ->
        ext = "." <> hd(String.split(fmt, "+"))

        case Base.decode64(b64) do
          {:ok, bytes} -> {:ok, ext, bytes}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_data_uri(_), do: :error
end
