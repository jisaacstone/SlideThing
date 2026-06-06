defmodule SlidethingWeb.BookController do
  use SlidethingWeb, :controller

  alias Slidething.Book

  def show(conn, %{"book_id" => book_id}) do
    case Book.get(book_id) do
      {:ok, book} ->
        json(conn, book)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "book not found"})
    end
  end

  def create(conn, %{"title" => title} = params) do
    metadata = params["metadata"] || %{}
    {:ok, book} = Book.create(title, metadata)
    conn |> put_status(201) |> json(book)
  end

  def list(conn, _params) do
    result =
      Slidething.Repo
      |> Ecto.Adapters.SQL.query!(
        "SELECT id, title, metadata, created_at, updated_at FROM books ORDER BY updated_at DESC"
      )

    books =
      for [id, title, meta_json, created, updated] <- result.rows do
        %{
          id: id,
          title: title,
          metadata: parse_json(meta_json),
          created_at: created,
          updated_at: updated
        }
      end

    json(conn, books)
  end

  def delete(conn, %{"book_id" => book_id}) do
    Book.delete(book_id)
    conn |> put_status(200) |> json(%{deleted: book_id})
  end

  def create_page(conn, %{"book_id" => book_id} = params) do
    next_pos = get_next_position(book_id)

    metadata =
      case params["title"] do
        nil -> %{}
        "" -> %{}
        title -> %{"title" => title}
      end

    {:ok, [page_id]} = Book.create_pages(book_id, [%{position: next_pos, metadata: metadata}])
    {:ok, page} = Book.get_page(page_id)
    conn |> put_status(201) |> json(page)
  end

  defp get_next_position(book_id) do
    result =
      Slidething.Repo
      |> Ecto.Adapters.SQL.query!(
        "SELECT COALESCE(MAX(position), 0) + 1 FROM pages WHERE book_id = ?",
        [book_id]
      )

    [[pos]] = result.rows
    pos
  end

  defp parse_json(nil), do: %{}
  defp parse_json(""), do: %{}
  defp parse_json(str), do: Jason.decode!(str)
end
