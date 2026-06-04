defmodule Slidething.Book do
  @moduledoc """
  Deterministic Book API. Called by tools and by the UI directly.
  """

  alias Slidething.Repo

  @doc """
  Create a new book. Returns {:ok, %{book_id, title, metadata}}.
  """
  def create(title, metadata \\ %{}) do
    book_id = generate_id("book")
    now = now_iso()

    meta_json = Jason.encode!(metadata)
    attrs = [book_id, title, meta_json, now, now]

    query("INSERT INTO books (id, title, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", attrs)

    {:ok, %{book_id: book_id, title: title, metadata: metadata}}
  end

  @doc """
  Create pages for a book. pages is either an integer (count) or a list of %{position, metadata}.
  Returns {:ok, [page_id]}.
  """
  def create_pages(book_id, count_or_list)

  def create_pages(book_id, count) when is_integer(count) do
    entries = Enum.map(1..count, &%{position: &1, metadata: %{}})
    create_pages(book_id, entries)
  end

  def create_pages(book_id, pages) when is_list(pages) do
    ids =
      Enum.map(pages, fn %{position: pos} = entry ->
        page_id = generate_id("page")
        meta = Jason.encode!(Map.get(entry, :metadata, %{}))
        now = now_iso()
        query("INSERT INTO pages (id, book_id, position, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)", [page_id, book_id, pos, meta, now, now])
        page_id
      end)

    {:ok, ids}
  end

  @doc """
  Get a book with its pages.
  """
  def get(book_id) do
    case query("SELECT id, title, metadata, created_at, updated_at FROM books WHERE id = ?", [book_id]) do
      %{num_rows: 0} -> {:error, :not_found}
      %{rows: [[id, title, meta_json, created, updated]]} ->
        pages = query("SELECT id, position, metadata FROM pages WHERE book_id = ? ORDER BY position", [book_id])
        page_list = for [pid, pos, pmeta] <- pages.rows, do: %{id: pid, position: pos, metadata: parse_json(pmeta)}

        {:ok, %{
          id: id,
          title: title,
          metadata: parse_json(meta_json),
          pages: page_list,
          created_at: created,
          updated_at: updated
        }}
    end
  end

  @doc """
  Get page outline (just IDs and positions).
  """
  def get_outline(book_id) do
    result = query("SELECT id, position, metadata FROM pages WHERE book_id = ? ORDER BY position", [book_id])
    pages = for [pid, pos, meta] <- result.rows, do: %{id: pid, position: pos, metadata: parse_json(meta)}
    {:ok, pages}
  end

  @doc """
  Get a single page.
  """
  def get_page(page_id) do
    case query("SELECT id, book_id, position, metadata, created_at, updated_at FROM pages WHERE id = ?", [page_id]) do
      %{num_rows: 0} -> {:error, :not_found}
      %{rows: [[id, book_id, pos, meta_json, created, updated]]} ->
        {:ok, %{id: id, book_id: book_id, position: pos, metadata: parse_json(meta_json), created_at: created, updated_at: updated}}
    end
  end

  @doc """
  Update book metadata.
  """
  def update_metadata(book_id, metadata) do
    now = now_iso()
    meta_json = Jason.encode!(metadata)
    query("UPDATE books SET metadata = ?, updated_at = ? WHERE id = ?", [meta_json, now, book_id])
    :ok
  end

  @doc """
  Update page metadata.
  """
  def update_page_metadata(page_id, metadata) do
    now = now_iso()
    meta_json = Jason.encode!(metadata)
    query("UPDATE pages SET metadata = ?, updated_at = ? WHERE id = ?", [meta_json, now, page_id])
    :ok
  end

  @doc """
  Link a book to a format.
  """
  def add_format(book_id, format_id) do
    query("INSERT OR IGNORE INTO book_formats (book_id, format_id) VALUES (?, ?)", [book_id, format_id])
    :ok
  end

  @doc """
  Get formats linked to a book.
  """
  def get_formats(book_id) do
    result = query("""
      SELECT f.id, f.name, f.unit, f.width, f.height, f.dpi, f.bleed_mm, f.safe_margin_mm
      FROM formats f
      JOIN book_formats bf ON bf.format_id = f.id
      WHERE bf.book_id = ?
    """, [book_id])

    for [id, name, unit, width, height, dpi, b_mm, s_mm] <- result.rows do
      %{id: id, name: name, unit: unit, width: width, height: height, dpi: dpi, bleed_mm: b_mm, safe_margin_mm: s_mm}
    end
  end

  @doc """
  Fetch a single format by ID. Returns the format map or nil.
  """
  def get_format(format_id) do
    result = query("SELECT id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm FROM formats WHERE id = ?", [format_id])

    case result.rows do
      [[id, name, unit, width, height, dpi, b_mm, s_mm]] ->
        %{id: id, name: name, unit: unit, width: width, height: height, dpi: dpi, bleed_mm: b_mm, safe_margin_mm: s_mm}
      _ ->
        nil
    end
  end

  @doc """
  Delete a book and all its pages, elements, and prompts.
  """
  def delete(book_id) do
    pages = query("SELECT id FROM pages WHERE book_id = ?", [book_id])
    for [pid] <- pages.rows do
      query("DELETE FROM element_versions WHERE element_id IN (SELECT id FROM elements WHERE page_id = ?)", [pid])
      query("DELETE FROM elements WHERE page_id = ?", [pid])
      query("DELETE FROM layout_versions WHERE page_id = ?", [pid])
    end
    query("DELETE FROM pages WHERE book_id = ?", [book_id])
    query("DELETE FROM agent_messages WHERE agent_run_id IN (SELECT id FROM agent_runs WHERE prompt_id IN (SELECT id FROM prompts WHERE book_id = ?))", [book_id])
    query("DELETE FROM agent_runs WHERE prompt_id IN (SELECT id FROM prompts WHERE book_id = ?)", [book_id])
    query("DELETE FROM prompts WHERE book_id = ?", [book_id])
    query("DELETE FROM book_formats WHERE book_id = ?", [book_id])
    query("DELETE FROM books WHERE id = ?", [book_id])
    :ok
  end

  @doc """
  Delete a single page and all its elements.
  """
  def delete_page(page_id) do
    query("DELETE FROM element_versions WHERE element_id IN (SELECT id FROM elements WHERE page_id = ?)", [page_id])
    query("DELETE FROM elements WHERE page_id = ?", [page_id])
    query("DELETE FROM layout_versions WHERE page_id = ?", [page_id])
    query("DELETE FROM pages WHERE id = ?", [page_id])
    :ok
  end

  defp generate_id(prefix), do: "#{prefix}_#{Ecto.UUID.generate()}"
  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp parse_json(nil), do: %{}
  defp parse_json(""), do: %{}
  defp parse_json(str), do: Jason.decode!(str)

  defp query(sql, params) do
    case Ecto.Adapters.SQL.query(Repo, sql, params) do
      {:ok, result} -> result
      {:error, err} -> raise "Book API query error: #{inspect(err)}"
    end
  end
end