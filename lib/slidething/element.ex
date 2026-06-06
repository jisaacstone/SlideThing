defmodule Slidething.Element do
  @moduledoc """
  Deterministic Element API. CRUD on elements with versioning.
  Called by tools and by the UI directly.
  """

  alias Slidething.Repo

  @doc """
  Create a new element + its first version. Returns {:ok, map}.
  """
  def create(page_id, element_type, content, attrs \\ %{}) do
    element_id = generate_id("elem")
    version_id = generate_id("ev")
    now = now_iso()
    attrs = as_map(attrs)
    prompt = attrs[:prompt] || attrs["prompt"]
    prometa = Jason.encode!(attrs[:metadata] || attrs["metadata"] || %{})

    query(
      "INSERT INTO elements (id, page_id, element_type, position, locked, created_at, updated_at) VALUES (?, ?, ?, 0, 0, ?, ?)",
      [element_id, page_id, element_type, now, now]
    )

    query(
      "INSERT INTO element_versions (id, element_id, version, content, asset_path, prompt, metadata, created_at) VALUES (?, ?, 1, ?, ?, ?, ?, ?)",
      [version_id, element_id, content, attrs[:asset_path] || attrs["asset_path"], prompt, prometa, now]
    )

    {:ok, %{
      element_id: element_id,
      version: 1,
      element_type: element_type,
      content: content,
      page_id: page_id
    }}
  end

  @doc """
  Create a new version of an existing element. Returns {:ok, map}.
  """
  def update(element_id, content, attrs \\ %{}) do
    result = query(
      "SELECT version FROM element_versions WHERE element_id = ? ORDER BY version DESC LIMIT 1",
      [element_id]
    )

    if result.num_rows == 0 do
      {:error, :not_found}
    else
      [[current_version]] = result.rows
      new_version = current_version + 1
      version_id = generate_id("ev")
      now = now_iso()
      attrs = as_map(attrs)
      prompt = attrs[:prompt] || attrs["prompt"]
      prometa = Jason.encode!(attrs[:metadata] || attrs["metadata"] || %{})

      query(
        "INSERT INTO element_versions (id, element_id, version, content, asset_path, prompt, metadata, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [version_id, element_id, new_version, content, attrs[:asset_path] || attrs["asset_path"], prompt, prometa, now]
      )

      query("UPDATE elements SET updated_at = ? WHERE id = ?", [now, element_id])

      {:ok, %{element_id: element_id, version: new_version, content: content}}
    end
  end

  @doc """
  Get a single element with its latest version. 
  Options: :history (N latest versions), :version (specific version).
  """
  def get(element_id, opts \\ []) do
    case query("SELECT id, page_id, element_type, position, locked, created_at, updated_at FROM elements WHERE id = ?", [element_id]) do
      %{num_rows: 0} -> {:error, :not_found}
      %{rows: [[id, page_id, element_type, position, locked, created, updated]]} ->
        versions = get_versions(element_id, opts)
        latest_version = List.last(versions)
        {:ok, %{
          id: id,
          page_id: page_id,
          element_type: element_type,
          position: position,
          locked: locked == 1,
          versions: versions,
          latest_version: latest_version,
          created_at: created,
          updated_at: updated
        }}
    end
  end

  @doc """
  List all elements on a page with their latest versions.
  """
  def list(page_id) do
    result = query(
      "SELECT id, element_type, position, locked FROM elements WHERE page_id = ? ORDER BY position",
      [page_id]
    )

    for [elem_id, etype, pos, locked] <- result.rows do
      latest = query(
        "SELECT version, content, asset_path, prompt FROM element_versions WHERE element_id = ? ORDER BY version DESC LIMIT 1",
        [elem_id]
      )

      lv =
        case latest.rows do
          [[v, content, asset, prompt]] -> %{version: v, content: content, asset_path: asset, prompt: prompt}
          [] -> %{version: 1, content: nil, asset_path: nil, prompt: nil}
        end

      %{id: elem_id, element_type: etype, position: pos, locked: locked == 1, latest_version: lv}
    end
  end

  @doc """
  List all elements on a page with full version history. Heavy, use for agent context.
  """
  def list_with_history(page_id) do
    list(page_id)
    |> Enum.map(fn elem ->
      versions = get_versions_raw(elem.id)
      Map.put(elem, :versions, versions)
    end)
  end

  @doc """
  Delete an element (marks inactive by clearing page_id).
  """
  def delete(element_id) do
    query("DELETE FROM element_versions WHERE element_id = ?", [element_id])
    query("DELETE FROM elements WHERE id = ?", [element_id])
    :ok
  end

  defp get_versions(element_id, opts) do
    history = Keyword.get(opts, :history)
    version = Keyword.get(opts, :version)

    cond do
      version ->
        result = query(
          "SELECT version, content, asset_path, prompt, metadata, created_at FROM element_versions WHERE element_id = ? AND version = ?",
          [element_id, version]
        )
        for [v, c, a, p, m, t] <- result.rows, do: %{version: v, content: c, asset_path: a, prompt: p, metadata: parse_json(m), created_at: t}

      history ->
        result = query(
          "SELECT version, content, asset_path, prompt, metadata, created_at FROM element_versions WHERE element_id = ? ORDER BY version DESC LIMIT ?",
          [element_id, history]
        )
        for [v, c, a, p, m, t] <- Enum.reverse(result.rows), do: %{version: v, content: c, asset_path: a, prompt: p, metadata: parse_json(m), created_at: t}

      true ->
        result = query(
          "SELECT version, content, asset_path, prompt, metadata, created_at FROM element_versions WHERE element_id = ? ORDER BY version DESC LIMIT 1",
          [element_id]
        )
        for [v, c, a, p, m, t] <- result.rows, do: %{version: v, content: c, asset_path: a, prompt: p, metadata: parse_json(m), created_at: t}
    end
  end

  defp get_versions_raw(element_id) do
    result = query(
      "SELECT version, content, asset_path, prompt, metadata, created_at FROM element_versions WHERE element_id = ? ORDER BY version ASC",
      [element_id]
    )
    for [v, c, a, p, m, t] <- result.rows, do: %{version: v, content: c, asset_path: a, prompt: p, metadata: parse_json(m), created_at: t}
  end

  defp generate_id(prefix), do: "#{prefix}_#{Ecto.UUID.generate()}"
  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp parse_json(nil), do: %{}
  defp parse_json(""), do: %{}
  defp parse_json(str), do: Jason.decode!(str)

  defp as_map(m) when is_map(m), do: m
  defp as_map(l) when is_list(l), do: Map.new(l)
  defp as_map(_), do: %{}

  defp query(sql, params) do
    case Ecto.Adapters.SQL.query(Repo, sql, params) do
      {:ok, result} -> result
      {:error, err} -> raise "Element query error: #{inspect(err)}"
    end
  end
end