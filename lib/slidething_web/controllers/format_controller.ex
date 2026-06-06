defmodule SlidethingWeb.FormatController do
  use SlidethingWeb, :controller

  def list(conn, %{"book_id" => book_id}) do
    formats = Slidething.Book.get_formats(book_id)
    json(conn, formats)
  end

  def list_all(conn, _params) do
    result =
      Slidething.Repo
      |> Ecto.Adapters.SQL.query!(
        "SELECT id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm FROM formats"
      )

    formats =
      for [id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm] <- result.rows do
        %{
          id: id,
          name: name,
          unit: unit,
          width: width,
          height: height,
          dpi: dpi,
          bleed_mm: bleed_mm,
          safe_margin_mm: safe_margin_mm
        }
      end

    json(conn, formats)
  end
end
