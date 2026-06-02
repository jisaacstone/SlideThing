defmodule SlidethingWeb.PageController do
  use Phoenix.Controller

  alias Slidething.Book
  alias Slidething.Element

  def root(conn, _params) do
    index = Path.join(:code.priv_dir(:slidething), "static/index.html")
    html(conn, File.read!(index))
  end

  def show(conn, %{"page_id" => page_id}) do
    case Book.get_page(page_id) do
      {:ok, page} ->
        elements = Element.list(page_id)
        json(conn, Map.put(page, :elements, elements))

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "page not found"})
    end
  end
end