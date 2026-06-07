defmodule SlidethingWeb.PageController do
  use SlidethingWeb, :controller

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

        # When the page has no layout yet, synthesize a placeholder layout using the
        # book's first format so the UI can render the correct aspect ratio.
        layouts =
          if layouts == [] do
            case Book.get_formats(page.book_id) do
              [format | _] ->
                [
                  %{
                    id: nil,
                    page_id: page_id,
                    format_id: format.id,
                    version: 0,
                    run_id: nil,
                    element_layouts: [],
                    created_at: nil,
                    format: format
                  }
                ]

              _ ->
                []
            end
          else
            layouts
          end

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
