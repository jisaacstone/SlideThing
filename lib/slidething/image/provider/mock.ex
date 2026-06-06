defmodule Slidething.Image.Provider.Mock do
  @moduledoc """
  Mock image provider for tests and offline development.

  Writes a tiny valid 1x1 PNG to the asset store and returns its filename.
  """

  @behaviour Slidething.Image.Provider

  require Logger

  # 1x1 transparent PNG (precomputed; smallest valid PNG)
  @stub_png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0,
              1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 0, 1,
              0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  @impl true
  def generate(_model, prompt, aspect_ratio) do
    Logger.debug(
      "[Image.Mock] generate prompt=#{String.slice(prompt, 0, 40)} aspect=#{aspect_ratio}"
    )

    Slidething.AssetStore.store(@stub_png, "mock-image.png")
  end
end
