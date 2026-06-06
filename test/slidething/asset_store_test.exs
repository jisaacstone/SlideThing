defmodule Slidething.AssetStoreTest do
  use ExUnit.Case, async: true
  alias Slidething.AssetStore

  @test_dir AssetStore.base_dir()

  setup do
    AssetStore.clean!()
    :ok
  end

  defp make_png do
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>

    # IHDR: 1x1, 8-bit, RGBA
    ihdr_data = <<1::32, 1::32, 8, 6, 0, 0, 0>>

    # 1 red pixel: filter byte (0=none) + RGBA
    raw_scanline = <<0, 255, 0, 0, 255>>
    compressed = :zlib.compress(raw_scanline)

    signature <>
      make_png_chunk("IHDR", ihdr_data) <>
      make_png_chunk("IDAT", compressed) <>
      make_png_chunk("IEND", "")
  end

  defp make_png_chunk(type, data) do
    chunk = type <> data
    crc = :erlang.crc32(chunk)
    <<byte_size(data)::32, chunk::binary, crc::32>>
  end

  describe "base_dir/0" do
    test "returns the tmp dir in test env" do
      assert AssetStore.base_dir() == @test_dir
    end
  end

  describe "ensure_dir!/0" do
    test "creates the directory" do
      dir = AssetStore.base_dir()
      File.rm_rf!(dir)
      refute File.dir?(dir)

      AssetStore.ensure_dir!()
      assert File.dir?(dir)
    end
  end

  describe "clean!/0" do
    test "removes and recreates the directory" do
      AssetStore.store("hello", "doc.txt")

      AssetStore.clean!()
      assert File.dir?(AssetStore.base_dir())

      {:ok, files} = File.ls(AssetStore.base_dir())
      assert files == []
    end
  end

  describe "store/2" do
    test "writes a png and returns a UUID-based relative path" do
      png = make_png()
      {:ok, path} = AssetStore.store(png, "cover.png")

      assert String.ends_with?(path, ".png")
      assert byte_size(path) == 40
      assert String.match?(path, ~r/^[0-9a-f\-]+\.png$/)
    end

    test "the stored content is identical to the original" do
      png = make_png()
      {:ok, path} = AssetStore.store(png, "image.png")
      {:ok, stored} = AssetStore.retrieve(path)

      assert stored == png
    end

    test "preserves the extension from the original filename" do
      {:ok, path} = AssetStore.store("data", "photo.jpeg")

      assert String.ends_with?(path, ".jpeg")
    end

    test "no extension when source has none" do
      {:ok, path} = AssetStore.store("data", "readme")
      refute String.contains?(path, ".")
    end
  end

  describe "store_from_path/1" do
    test "copies a file into the media directory" do
      png = make_png()
      tmp = Path.join(@test_dir, "source.png")
      File.write!(tmp, png)

      {:ok, rel} = AssetStore.store_from_path(tmp)
      {:ok, stored} = AssetStore.retrieve(rel)

      assert stored == png
      assert String.ends_with?(rel, ".png")
    end
  end

  describe "retrieve/1" do
    test "returns an error for a nonexistent file" do
      {:error, _} = AssetStore.retrieve("nonexistent.png")
    end
  end

  describe "retrieve_meta/1" do
    test "returns file size" do
      png = make_png()
      {:ok, path} = AssetStore.store(png, "cover.png")
      {:ok, meta} = AssetStore.retrieve_meta(path)

      assert meta.size == byte_size(png)
      assert meta.filename == path
    end
  end

  describe "delete/1" do
    test "removes a file" do
      png = make_png()
      {:ok, path} = AssetStore.store(png, "cover.png")
      assert {:ok, _} = AssetStore.retrieve(path)

      AssetStore.delete(path)

      {:error, _} = AssetStore.retrieve(path)
    end

    test "ignores nonexistent files" do
      assert AssetStore.delete("nothing.png") == :ok
    end
  end

  describe "full_path/1" do
    test "prepends the base directory" do
      full = AssetStore.full_path("photo.png")
      assert full == Path.join(@test_dir, "photo.png")
    end
  end
end
