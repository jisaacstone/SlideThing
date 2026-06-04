defmodule SlidethingWeb.PageController do
  use Phoenix.Controller

  alias Slidething.Book
  alias Slidething.Element
  alias Slidething.Layout

  def root(conn, _params) do
    index = Path.join(:code.priv_dir(:slidething), "static/index.html")
    html(conn, File.read!(index))
  end

  def show(conn, %{"page_id" => page_id}) do
    case Book.get_page(page_id) do
      {:ok, page} ->
        elements = Element.list(page_id)
        {:ok, layouts} = Layout.get_all_with_format(page_id)

        page
        |> Map.put(:elements, elements)
        |> Map.put(:layouts, layouts)
        |> then(&json(conn, &1))

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "page not found"})
    end
  end

  def delete(conn, %{"page_id" => page_id}) do
    Book.delete_page(page_id)
    conn |> put_status(200) |> json(%{deleted: page_id})
  end
end