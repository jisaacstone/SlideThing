defmodule Slidething.Prompt do
  @moduledoc """
  Prompt persistence and querying.

  Records user prompts with optional target scoping and
  provides prompt history for books/pages/elements.
  """

  alias Slidething.Repo

  @doc """
  Record a prompt in the database.

  Options:
    - target_type: "page" | "element" (optional)
    - target_id: page id or element id (optional)
    - result_summary: agent response summary (optional)
    - agent_type: which agent processed this (defaults to "user")
  """
  def record(run_id, book_id, user_prompt, opts \\ []) do
    target_type = Keyword.get(opts, :target_type)
    target_id = Keyword.get(opts, :target_id)
    result_summary = Keyword.get(opts, :result_summary)
    agent_type = Keyword.get(opts, :agent_type, "user")

    prompt_id = "prompt_#{:rand.uniform(1_000_000)}"
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Repo
    |> Ecto.Adapters.SQL.query!("""
    INSERT INTO prompts (id, book_id, run_id, agent_type, user_prompt, context, result_summary, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """,
      [prompt_id, book_id, run_id, agent_type, user_prompt, Jason.encode!(%{}), result_summary, now])

    if target_type && target_id do
      Repo
      |> Ecto.Adapters.SQL.query!("""
      INSERT INTO prompt_targets (prompt_id, target_type, target_id)
      VALUES (?, ?, ?)
      """,
        [prompt_id, target_type, target_id])
    end

    {:ok, prompt_id}
  end

  @doc """
  List prompts for a book, optionally scoped to a target.

  Returns a list of maps with prompt info and targets.
  """
  def list(book_id, target_id \\ nil) do
    {base_query, base_args} =
      if target_id do
        {"INNER JOIN prompt_targets pt ON pt.prompt_id = p.id WHERE p.book_id = ? AND pt.target_id = ?",
         [book_id, target_id]}
      else
        {"WHERE p.book_id = ?", [book_id]}
      end

    result =
      Repo
      |> Ecto.Adapters.SQL.query!("""
      SELECT p.id, p.run_id, p.agent_type, p.user_prompt, p.result_summary, p.created_at
      FROM prompts p
      #{base_query}
      ORDER BY p.created_at DESC
      LIMIT 50
      """,
        base_args)

    rows =
      Enum.map(result.rows, fn [id, run_id, agent_type, user_prompt, result_summary, created_at] ->
        targets = fetch_targets(id)

        %{
          id: id,
          run_id: run_id,
          agent_type: agent_type,
          user_prompt: user_prompt,
          result_summary: result_summary,
          targets: targets,
          created_at: created_at
        }
      end)

    {:ok, rows}
  end

  defp fetch_targets(prompt_id) do
    result =
      Repo
      |> Ecto.Adapters.SQL.query!(
        "SELECT target_type, target_id FROM prompt_targets WHERE prompt_id = ?",
        [prompt_id])

    Enum.map(result.rows, fn [target_type, target_id] ->
      %{target_type: target_type, target_id: target_id}
    end)
  end
end