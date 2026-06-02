defmodule SlidethingWeb.ElementController do
  use SlidethingWeb, :controller

  alias Slidething.Element

  def show(conn, %{"element_id" => element_id}) do
    case Element.get(element_id) do
      {:ok, element} ->
        json(conn, element)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "element not found"})
    end
  end

  def list(conn, %{"page_id" => page_id}) do
    elements = Element.list(page_id)
    json(conn, elements)
  end
end