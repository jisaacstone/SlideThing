defmodule Slidething.Layout do
  @moduledoc """
  Deterministic Layout API. CRUD on layout_versions.
  Called by tools and by the UI.
  """

  alias Slidething.Repo

  @doc """
  Create a layout version for a page. Returns {:ok, map}.
  """
  def create(page_id, format_id, run_id \\ nil, element_layouts \\ []) do
    layout_id = generate_id("lv")
    now = now_iso()
    layouts_json = Jason.encode!(element_layouts)

    query(
      "INSERT INTO layout_versions (id, page_id, format_id, version, run_id, element_layouts, created_at) VALUES (?, ?, ?, 1, ?, ?, ?)",
      [layout_id, page_id, format_id, run_id, layouts_json, now]
    )

    {:ok, %{
      id: layout_id,
      page_id: page_id,
      format_id: format_id,
      version: 1,
      run_id: run_id,
      element_layouts: element_layouts
    }}
  end

  @doc """
  Create a new layout version for a page. Returns {:ok, map}.
  """
  def update(page_id, format_id, run_id \\ nil, element_layouts \\ []) do
    result = query(
      "SELECT version FROM layout_versions WHERE page_id = ? AND format_id = ? ORDER BY version DESC LIMIT 1",
      [page_id, format_id]
    )

    if result.num_rows == 0 do
      create(page_id, format_id, run_id, element_layouts)
    else
      [[current_version]] = result.rows
      new_version = current_version + 1
      layout_id = generate_id("lv")
      now = now_iso()
      layouts_json = Jason.encode!(element_layouts)

      query(
        "INSERT INTO layout_versions (id, page_id, format_id, version, run_id, element_layouts, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [layout_id, page_id, format_id, new_version, run_id, layouts_json, now]
      )

      {:ok, %{
        id: layout_id,
        page_id: page_id,
        format_id: format_id,
        version: new_version,
        run_id: run_id,
        element_layouts: element_layouts
      }}
    end
  end

  @doc """
  Get the latest layout version for a page + format combination.
  """
  def get(page_id, format_id) do
    result = query(
      "SELECT id, page_id, format_id, version, run_id, element_layouts, created_at FROM layout_versions WHERE page_id = ? AND format_id = ? ORDER BY version DESC LIMIT 1",
      [page_id, format_id]
    )

    case result.rows do
      [] -> {:error, :not_found}
      [[id, pid, fid, ver, rid, layouts_json, created]] ->
        layout = parse_layout(id, pid, fid, ver, rid, layouts_json, created)
        {:ok, layout}
    end
  end

  @doc """
  Get all layout versions for a page (across all formats).
  """
  def get_all(page_id) do
    result = query(
      "SELECT id, page_id, format_id, version, run_id, element_layouts, created_at FROM layout_versions WHERE page_id = ? ORDER BY format_id, version DESC",
      [page_id]
    )

    layouts =
      for [id, pid, fid, ver, rid, layouts_json, created] <- result.rows do
        parse_layout(id, pid, fid, ver, rid, layouts_json, created)
      end

    {:ok, layouts}
  end

  @doc """
  Get a specific layout version by id.
  """
  def get_by_id(layout_id) do
    result = query(
      "SELECT id, page_id, format_id, version, run_id, element_layouts, created_at FROM layout_versions WHERE id = ?",
      [layout_id]
    )

    case result.rows do
      [] -> {:error, :not_found}
      [[id, pid, fid, ver, rid, layouts_json, created]] ->
        layout = parse_layout(id, pid, fid, ver, rid, layouts_json, created)
        {:ok, layout}
    end
  end

  @doc """
  Get all layout versions for a page+format with version history.
  """
  def get_history(page_id, format_id, limit \\ 10) do
    result = query(
      "SELECT id, page_id, format_id, version, run_id, element_layouts, created_at FROM layout_versions WHERE page_id = ? AND format_id = ? ORDER BY version DESC LIMIT ?",
      [page_id, format_id, limit]
    )

    layouts =
      for [id, pid, fid, ver, rid, layouts_json, created] <- result.rows do
        parse_layout(id, pid, fid, ver, rid, layouts_json, created)
      end

    {:ok, layouts}
  end

  defp parse_layout(id, page_id, format_id, version, run_id, layouts_json, created_at) do
    %{
      id: id,
      page_id: page_id,
      format_id: format_id,
      version: version,
      run_id: run_id,
      element_layouts: parse_json(layouts_json),
      created_at: created_at
    }
  end

  defp generate_id(prefix), do: "#{prefix}_#{Ecto.UUID.generate()}"
  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp parse_json(nil), do: []
  defp parse_json(""), do: []
  defp parse_json(str), do: Jason.decode!(str)

  defp query(sql, params) do
    case Ecto.Adapters.SQL.query(Repo, sql, params) do
      {:ok, result} -> result
      {:error, err} -> raise "Layout query error: #{inspect(err)}"
    end
  end
end