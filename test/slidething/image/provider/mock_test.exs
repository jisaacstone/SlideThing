defmodule Slidething.Image.Provider.MockTest do
  use ExUnit.Case, async: false

  alias Slidething.Image.Provider.Mock

  test "generate writes a stub PNG to the asset store" do
    {:ok, asset_path} = Mock.generate("mock-model", "A flying duck", "1:1")

    assert is_binary(asset_path)
    assert String.ends_with?(asset_path, ".png")

    full = Slidething.AssetStore.full_path(asset_path)
    assert File.exists?(full)

    bytes = File.read!(full)
    # PNG signature: 89 50 4E 47 0D 0A 1A 0A
    assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = bytes
  end
end
