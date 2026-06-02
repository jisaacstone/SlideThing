defmodule SlidethingWeb.LayoutController do
  use SlidethingWeb, :controller

  alias Slidething.Layout

  def show(conn, %{"page_id" => page_id, "format_id" => format_id}) do
    case Layout.get(page_id, format_id) do
      {:ok, layout} ->
        json(conn, layout)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "layout not found"})
    end
  end

  def list(conn, %{"page_id" => page_id}) do
    {:ok, layouts} = Layout.get_all(page_id)
    json(conn, layouts)
  end
end