defmodule Slidething.Schema.Bootstrap do
  @moduledoc """
  Creates database tables programmatically (no migrations).
  Safe to run on every startup — all statements use IF NOT EXISTS.
  """

  require Logger

  alias Slidething.Repo

  def ensure_tables do
    Logger.info("[Bootstrap] Ensuring database tables...")

    Enum.each(ddl(), fn {name, sql} ->
      Logger.debug("[Bootstrap] Creating table: #{name}")
      Ecto.Adapters.SQL.query!(Repo, sql, [], log: :debug)
    end)

    migrate_formats()
    migrate_prompts()
    drop_legacy_tables()
    create_indexes()
    seed_formats()
    Logger.info("[Bootstrap] Database tables ready")
  end

  defp ddl do
    [
      books: """
      CREATE TABLE IF NOT EXISTS books (
        id TEXT PRIMARY KEY,
        title TEXT,
        metadata TEXT DEFAULT '{}',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
      """,
      pages: """
      CREATE TABLE IF NOT EXISTS pages (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id),
        position INTEGER NOT NULL DEFAULT 0,
        metadata TEXT DEFAULT '{}',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
      """,
      elements: """
      CREATE TABLE IF NOT EXISTS elements (
        id TEXT PRIMARY KEY,
        page_id TEXT NOT NULL REFERENCES pages(id),
        element_type TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        locked INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
      """,
      element_versions: """
      CREATE TABLE IF NOT EXISTS element_versions (
        id TEXT PRIMARY KEY,
        element_id TEXT NOT NULL REFERENCES elements(id),
        version INTEGER NOT NULL DEFAULT 1,
        run_id TEXT,
        content TEXT,
        asset_path TEXT,
        prompt TEXT,
        metadata TEXT DEFAULT '{}',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
      """,
      formats: """
      CREATE TABLE IF NOT EXISTS formats (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        width REAL NOT NULL,
        height REAL NOT NULL,
        dpi INTEGER NOT NULL DEFAULT 300,
        bleed_mm REAL,
        safe_margin_mm REAL
      )
      """,
      book_formats: """
      CREATE TABLE IF NOT EXISTS book_formats (
        book_id TEXT NOT NULL REFERENCES books(id),
        format_id TEXT NOT NULL REFERENCES formats(id),
        UNIQUE(book_id, format_id)
      )
      """,
      layout_versions: """
      CREATE TABLE IF NOT EXISTS layout_versions (
        id TEXT PRIMARY KEY,
        page_id TEXT NOT NULL REFERENCES pages(id),
        format_id TEXT NOT NULL REFERENCES formats(id),
        version INTEGER NOT NULL DEFAULT 1,
        run_id TEXT,
        element_layouts TEXT DEFAULT '[]',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
      """,
      prompts: """
      CREATE TABLE IF NOT EXISTS prompts (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id),
        user_prompt TEXT NOT NULL,
        target_type TEXT,
        target_id TEXT,
        status TEXT NOT NULL DEFAULT 'running',
        result_summary TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
      """,
      agent_runs: """
      CREATE TABLE IF NOT EXISTS agent_runs (
        id TEXT PRIMARY KEY,
        prompt_id TEXT NOT NULL,
        agent_type TEXT NOT NULL,
        scope_type TEXT,
        scope_id TEXT,
        provider TEXT,
        model TEXT,
        status TEXT NOT NULL DEFAULT 'running',
        final_result TEXT,
        failure_reason TEXT,
        started_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT
      )
      """,
      agent_messages: """
      CREATE TABLE IF NOT EXISTS agent_messages (
        id TEXT PRIMARY KEY,
        agent_run_id TEXT NOT NULL,
        iteration INTEGER NOT NULL DEFAULT 0,
        role TEXT NOT NULL,
        content TEXT,
        tool_calls TEXT,
        tool_results TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
      """
    ]
  end

  defp create_indexes do
    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_pages_book ON pages(book_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_elements_page ON elements(page_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_element_versions_element ON element_versions(element_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_layout_versions_page ON layout_versions(page_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_layout_versions_page_format ON layout_versions(page_id, format_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_prompts_book ON prompts(book_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_prompts_target ON prompts(target_type, target_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_agent_runs_prompt ON agent_runs(prompt_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_agent_messages_run ON agent_messages(agent_run_id)",
      [],
      log: :debug
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS idx_book_formats_book ON book_formats(book_id)",
      [],
      log: :debug
    )
  end

  defp migrate_prompts do
    add_column_if_missing("prompts", "target_type", "TEXT")
    add_column_if_missing("prompts", "target_id", "TEXT")
    add_column_if_missing("prompts", "status", "TEXT NOT NULL DEFAULT 'running'")
    add_column_if_missing("prompts", "completed_at", "TEXT")

    # Drop indexes referencing legacy columns before dropping the columns.
    Ecto.Adapters.SQL.query!(
      Repo,
      "DROP INDEX IF EXISTS idx_prompts_run",
      [],
      log: :debug
    )

    drop_column_if_present("prompts", "context")
    drop_column_if_present("prompts", "run_id")
    drop_column_if_present("prompts", "agent_type")
  end

  defp drop_legacy_tables do
    Ecto.Adapters.SQL.query!(Repo, "DROP TABLE IF EXISTS prompt_targets", [], log: :debug)
  end

  defp drop_column_if_present(table, column) do
    cols =
      Ecto.Adapters.SQL.query!(
        Repo,
        "PRAGMA table_info(#{table})",
        [],
        log: :debug
      )

    if Enum.any?(cols.rows, fn row -> Enum.at(row, 1) == column end) do
      Logger.info("[Bootstrap] Dropping column #{table}.#{column}")

      Ecto.Adapters.SQL.query!(
        Repo,
        "ALTER TABLE #{table} DROP COLUMN #{column}",
        [],
        log: :debug
      )
    end
  end

  defp migrate_formats do
    add_column_if_missing("formats", "dpi", "INTEGER NOT NULL DEFAULT 300")
    add_column_if_missing("formats", "bleed_mm", "REAL")
    add_column_if_missing("formats", "safe_margin_mm", "REAL")

    result =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT id FROM formats WHERE id = 'format-default'",
        [],
        log: :debug
      )

    if result.num_rows > 0 do
      Logger.info("[Bootstrap] Migrating format-default to format-print")

      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE formats SET id = 'format-print', name = 'Children Book Square (Print)', dpi = 300, bleed_mm = 3.0, safe_margin_mm = 6.0 WHERE id = 'format-default'",
        [],
        log: :debug
      )
    end
  end

  defp add_column_if_missing(table, column, type) do
    cols =
      Ecto.Adapters.SQL.query!(
        Repo,
        "PRAGMA table_info(#{table})",
        [],
        log: :debug
      )

    if not Enum.any?(cols.rows, fn row -> Enum.at(row, 1) == column end) do
      Logger.info("[Bootstrap] Adding column #{table}.#{column}")

      Ecto.Adapters.SQL.query!(
        Repo,
        "ALTER TABLE #{table} ADD COLUMN #{column} #{type}",
        [],
        log: :debug
      )
    end
  end

  defp seed_formats do
    seed_format("format-print", "Children Book Square (Print)", "cm", 20.0, 20.0, 300, 3.0, 6.0)
    seed_format("format-web", "Children Book Square (Web)", "cm", 20.0, 20.0, 72, nil, 6.0)
  end

  defp seed_format(id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm) do
    result =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT id FROM formats WHERE id = ?",
        [id],
        log: :debug
      )

    if result.num_rows == 0 do
      Logger.info("[Bootstrap] Seeding format: #{id}")

      Ecto.Adapters.SQL.query!(
        Repo,
        "INSERT INTO formats (id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm],
        log: :debug
      )
    end
  end
end
