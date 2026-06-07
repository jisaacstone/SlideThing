defmodule Slidething.Layout do
  @moduledoc """
  CRUD for `layout_versions` rows. One row per (page_id, format_id) version.

  `element_layouts` is stored as a JSON-encoded array of maps:
  `[%{"element_id" => "...", "x" => 0.0, "y" => 0.0, "width" => 1.0, "height" => 1.0}, ...]`
  """

  alias Slidething.Repo

  @doc """
  Insert a new layout version for the given (page_id, format_id).
  `element_layouts` is a list of maps. Returns {:ok, %{id, version}}.
  """
  def create(page_id, format_id, element_layouts, opts \\ []) do
    id = "lv_#{Ecto.UUID.generate()}"
    now = now_iso()
    run_id = Keyword.get(opts, :run_id)
    version = next_version(page_id, format_id)
    layouts_json = Jason.encode!(element_layouts || [])

    query(
      "INSERT INTO layout_versions (id, page_id, format_id, version, run_id, element_layouts, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      [id, page_id, format_id, version, run_id, layouts_json, now]
    )

    {:ok, %{id: id, version: version, page_id: page_id, format_id: format_id}}
  end

  @doc """
  Get all layout versions for a page, newest first.
  """
  def get_all(page_id) do
    result =
      query(
        "SELECT id, page_id, format_id, version, run_id, element_layouts, created_at FROM layout_versions WHERE page_id = ? ORDER BY version DESC",
        [page_id]
      )

    rows =
      Enum.map(result.rows, fn [id, pid, fid, version, run_id, layouts_json, created] ->
        %{
          id: id,
          page_id: pid,
          format_id: fid,
          version: version,
          run_id: run_id,
          element_layouts: parse_layouts(layouts_json),
          created_at: created
        }
      end)

    {:ok, rows}
  end

  @doc """
  Get all layout versions for a page, newest first.
  """
  def get_all_with_format(page_id) do
    result =
      query(
        """
        SELECT lv.id, lv.page_id, lv.format_id, lv.version, lv.run_id, lv.element_layouts, lv.created_at,
               f.name, f.unit, f.width, f.height, f.dpi, f.safe_margin_mm, f.bleed_mm
        FROM layout_versions lv
        JOIN formats f ON lv.format_id = f.id
        WHERE lv.page_id = ?
        ORDER BY lv.version DESC
        """,
        [page_id]
      )

    rows =
      Enum.map(result.rows, fn [
                                 id,
                                 pid,
                                 fid,
                                 version,
                                 run_id,
                                 layouts_json,
                                 created,
                                 fname,
                                 unit,
                                 width,
                                 height,
                                 dpi,
                                 safe_margin_mm,
                                 bleed_mm
                               ] ->
        %{
          id: id,
          page_id: pid,
          format_id: fid,
          version: version,
          run_id: run_id,
          element_layouts: parse_layouts(layouts_json),
          created_at: created,
          format: %{
            name: fname,
            unit: unit,
            width: width,
            height: height,
            dpi: dpi,
            safe_margin_mm: safe_margin_mm,
            bleed_mm: bleed_mm
          }
        }
      end)

    {:ok, rows}
  end

  @doc """
  Get the latest layout for a (page_id, format_id) pair together with format dimensions.
  Returns `{:ok, %{element_layouts: [...], format: %{...}}}` or `{:error, :not_found}`.
  Single indexed JOIN — use this for validation to avoid a second query.
  """
  def get_with_format(page_id, format_id) do
    result =
      query(
        """
        SELECT lv.id, lv.version, lv.element_layouts,
               f.width, f.height, f.unit, f.dpi, f.safe_margin_mm, f.bleed_mm
        FROM layout_versions lv
        JOIN formats f ON lv.format_id = f.id
        WHERE lv.page_id = ? AND lv.format_id = ?
        ORDER BY lv.version DESC
        LIMIT 1
        """,
        [page_id, format_id]
      )

    case result.rows do
      [] ->
        {:error, :not_found}

      [[_id, _version, layouts_json, width, height, unit, dpi, safe_margin_mm, bleed_mm]] ->
        {:ok,
         %{
           element_layouts: parse_layouts(layouts_json),
           format: %{
             width: width,
             height: height,
             unit: unit,
             dpi: dpi,
             safe_margin_mm: safe_margin_mm,
             bleed_mm: bleed_mm
           }
         }}
    end
  end

  @doc """
  Move a single element within the latest layout version by creating a new version.
  Returns {:ok, %{id, version}} or {:error, :not_found}.
  """
  def move_element(page_id, format_id, element_id, x, y) do
    case get_latest(page_id, format_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, latest} ->
        updated =
          Enum.map(latest.element_layouts, fn el ->
            if el["element_id"] == element_id do
              Map.merge(el, %{"x" => x, "y" => y})
            else
              el
            end
          end)

        create(page_id, format_id, updated)
    end
  end

  def get_latest(page_id, format_id) do
    result =
      query(
        "SELECT id, version, run_id, element_layouts, created_at FROM layout_versions WHERE page_id = ? AND format_id = ? ORDER BY version DESC LIMIT 1",
        [page_id, format_id]
      )

    case result.rows do
      [] ->
        {:error, :not_found}

      [[id, version, run_id, layouts_json, created]] ->
        {:ok,
         %{
           id: id,
           page_id: page_id,
           format_id: format_id,
           version: version,
           run_id: run_id,
           element_layouts: parse_layouts(layouts_json),
           created_at: created
         }}
    end
  end

  defp next_version(page_id, format_id) do
    result =
      query(
        "SELECT MAX(version) FROM layout_versions WHERE page_id = ? AND format_id = ?",
        [page_id, format_id]
      )

    case result.rows do
      [[nil]] -> 1
      [[v]] -> v + 1
      _ -> 1
    end
  end

  defp parse_layouts(nil), do: []
  defp parse_layouts(""), do: []

  defp parse_layouts(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp query(sql, params) do
    case Ecto.Adapters.SQL.query(Repo, sql, params) do
      {:ok, result} -> result
      {:error, err} -> raise "Layout query error: #{inspect(err)}"
    end
  end
end
