defmodule Slidething.AssetStore do
  @moduledoc """
  Deterministic filesystem storage for uploaded and generated media.

  Files are stored in the media directory:
    - Config override via `config :slidething, :media_dir`
    - `$XDG_DATA_HOME/slidething/media`
    - `~/.local/share/slidething/media`

  All files are stored with UUID filenames (preserving the original extension)
  to avoid collisions. No MIME type filtering — anything the browser can display
  is accepted.
  """

  def base_dir do
    case Application.get_env(:slidething, :media_dir) do
      nil ->
        data_home =
          System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")

        Path.join([data_home, "slidething", "media"])

      dir ->
        dir
    end
  end

  @doc """
  Ensures the media directory exists.
  Called at startup by Application — idempotent.
  """
  def ensure_dir! do
    File.mkdir_p!(base_dir())
    :ok
  end

  @doc """
  Removes and recreates the media directory. Used in test env to start clean.
  """
  def clean! do
    File.rm_rf!(base_dir())
    File.mkdir_p!(base_dir())
    :ok
  end

  @doc """
  Writes binary content to a file with a UUID-based filename.

  The extension is extracted from `original_filename`. Returns the relative path
  (filename only, relative to the media directory).

  ## Examples
      iex> {:ok, path} = AssetStore.store(png_bytes, "photo.png")
      iex> String.ends_with?(path, ".png")
      true
  """
  @spec store(binary, String.t()) :: {:ok, String.t()} | {:error, term}
  def store(content, original_filename) do
    ext = Path.extname(original_filename)
    filename = "#{uuid()}#{ext}"
    full = Path.join(base_dir(), filename)

    case File.write(full, content) do
      :ok -> {:ok, filename}
      {:error, _} = error -> error
    end
  end

  @doc """
  Copies an existing file into the media directory with a UUID filename.
  Returns the relative path.
  """
  @spec store_from_path(String.t()) :: {:ok, String.t()} | {:error, term}
  def store_from_path(source_path) do
    ext = Path.extname(source_path)
    filename = "#{uuid()}#{ext}"
    full = Path.join(base_dir(), filename)

    case File.cp(source_path, full) do
      :ok -> {:ok, filename}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reads a file from the media directory by its relative path.
  """
  @spec retrieve(String.t()) :: {:ok, binary} | {:error, term}
  def retrieve(asset_path) do
    full = full_path(asset_path)
    File.read(full)
  end

  @doc """
  Returns metadata about a stored file.
  """
  @spec retrieve_meta(String.t()) :: {:ok, map} | {:error, term}
  def retrieve_meta(asset_path) do
    full = full_path(asset_path)

    case File.stat(full) do
      {:ok, stat} ->
        {:ok, %{size: stat.size, filename: asset_path}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes a file from the media directory.
  """
  @spec delete(String.t()) :: :ok
  def delete(asset_path) do
    full = full_path(asset_path)
    File.rm(full)
    :ok
  end

  @doc """
  Resolves a relative asset path to an absolute filesystem path.
  """
  @spec full_path(String.t()) :: String.t()
  def full_path(asset_path) do
    Path.join(base_dir(), asset_path)
  end

  defp uuid do
    Ecto.UUID.generate()
  end
end
