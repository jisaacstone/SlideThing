defmodule Slidething.Image.Provider do
  @moduledoc """
  Behaviour for image generation providers.

  Implementations call an external image API (or fake one), store the
  resulting bytes via `Slidething.AssetStore`, and return the relative
  asset filename.
  """

  @type aspect_ratio :: String.t()
  @type result :: {:ok, String.t()} | {:error, term()}

  @callback generate(model :: String.t(), prompt :: String.t(), aspect_ratio :: aspect_ratio) ::
              result

  @allowed_aspects ["1:1", "9:16", "16:9", "3:4", "4:3"]

  @doc """
  Snaps an arbitrary width/height ratio (float) to the nearest Imagen-supported aspect string.
  """
  @spec snap_aspect(float()) :: aspect_ratio
  def snap_aspect(ratio) when is_number(ratio) and ratio > 0 do
    @allowed_aspects
    |> Enum.min_by(fn a -> abs(:math.log(parse_ratio(a) / ratio)) end)
  end

  def snap_aspect(_), do: "1:1"

  defp parse_ratio(str) do
    [w, h] = String.split(str, ":")
    String.to_integer(w) / String.to_integer(h)
  end
end
