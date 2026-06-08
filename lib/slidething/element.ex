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
      [
        version_id,
        element_id,
        content,
        attrs[:asset_path] || attrs["asset_path"],
        prompt,
        prometa,
        now
      ]
    )

    {:ok,
     %{
       element_id: element_id,
       version: 1,
       element_type: element_type,
       content: content,
       page_id: page_id
     }}
  end

  @doc """
  Overwrite the content of an existing element. Returns {:ok, map}.
  """
  def update(element_id, content, attrs \\ %{}) do
    exists = query("SELECT id FROM elements WHERE id = ?", [element_id])

    if exists.num_rows == 0 do
      {:error, :not_found}
    else
      now = now_iso()
      attrs = as_map(attrs)
      prompt = attrs[:prompt] || attrs["prompt"]
      asset_path = attrs[:asset_path] || attrs["asset_path"]
      prometa = Jason.encode!(attrs[:metadata] || attrs["metadata"] || %{})
      version_id = generate_id("ev")

      query("DELETE FROM element_versions WHERE element_id = ?", [element_id])

      query(
        "INSERT INTO element_versions (id, element_id, version, content, asset_path, prompt, metadata, created_at) VALUES (?, ?, 1, ?, ?, ?, ?, ?)",
        [version_id, element_id, content, asset_path, prompt, prometa, now]
      )

      query("UPDATE elements SET updated_at = ? WHERE id = ?", [now, element_id])

      {:ok, %{element_id: element_id, content: content}}
    end
  end

  @doc """
  Get a single element with its content.
  """
  def get(element_id) do
    case query(
           "SELECT id, page_id, element_type, position, locked, created_at, updated_at FROM elements WHERE id = ?",
           [element_id]
         ) do
      %{num_rows: 0} ->
        {:error, :not_found}

      %{rows: [[id, page_id, element_type, position, locked, created, updated]]} ->
        {content, asset_path} = fetch_content(id)

        {:ok,
         %{
           id: id,
           page_id: page_id,
           element_type: element_type,
           position: position,
           locked: locked == 1,
           content: content,
           asset_path: asset_path,
           created_at: created,
           updated_at: updated
         }}
    end
  end

  @doc """
  List all elements on a page with their content.
  """
  def list(page_id) do
    result =
      query(
        "SELECT id, element_type, position, locked FROM elements WHERE page_id = ? ORDER BY position",
        [page_id]
      )

    for [elem_id, etype, pos, locked] <- result.rows do
      {content, asset_path} = fetch_content(elem_id)

      %{
        id: elem_id,
        element_type: etype,
        position: pos,
        locked: locked == 1,
        content: content,
        asset_path: asset_path
      }
    end
  end

  @doc """
  Delete an element and all its versions.
  """
  def delete(element_id) do
    query("DELETE FROM element_versions WHERE element_id = ?", [element_id])
    query("DELETE FROM elements WHERE id = ?", [element_id])
    :ok
  end

  defp fetch_content(element_id) do
    result =
      query(
        "SELECT content, asset_path FROM element_versions WHERE element_id = ? LIMIT 1",
        [element_id]
      )

    case result.rows do
      [[content, asset_path]] -> {content, asset_path}
      [] -> {nil, nil}
    end
  end

  defp generate_id(prefix), do: "#{prefix}_#{Ecto.UUID.generate()}"
  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
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
