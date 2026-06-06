defmodule SlidethingWeb.AssetController do
  use SlidethingWeb, :controller

  alias Slidething.AssetStore

  def show(conn, %{"filename" => filename}) do
    full = AssetStore.full_path(filename)

    case File.read(full) do
      {:ok, content} ->
        conn
        |> put_resp_content_type(content_type(filename))
        |> send_resp(200, content)

      {:error, _} ->
        conn |> put_status(404) |> json(%{error: "asset not found"})
    end
  end

  defp content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end
end
