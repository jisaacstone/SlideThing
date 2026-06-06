defmodule Slidething.Prompt do
  @moduledoc """
  User-facing prompt persistence. One row per user submission.

  The prompt row IS the orchestrator-run record: `prompt.id` is the
  canonical run_id used everywhere downstream. The `run_id` column on
  the table is kept equal to `id` for backward compatibility with the
  existing schema; new code should treat them as the same value.

  The per-agent transcripts (system prompts, LLM messages, tool calls)
  live in `Slidething.Transcript`, not here.
  """

  alias Slidething.Repo

  @doc """
  Insert a new prompt row at the start of a run. Returns the prompt id.

  Target type/id are optional and scope the prompt to a single page or
  element. Stored inline on the row (no separate join table).
  """
  def start_run(book_id, user_prompt, opts \\ []) do
    id = Ecto.UUID.generate()
    target_type = Keyword.get(opts, :target_type)
    target_id = Keyword.get(opts, :target_id)
    now = now_iso()

    query!(
      """
      INSERT INTO prompts
        (id, book_id, user_prompt, target_type, target_id, status, created_at)
      VALUES (?, ?, ?, ?, ?, 'running', ?)
      """,
      [id, book_id, user_prompt, target_type, target_id, now]
    )

    id
  end

  @doc """
  Mark a prompt completed and write the result summary.
  Safe no-op if no row matches (e.g. tests that bypass the API).
  """
  def complete(prompt_id, summary) when is_binary(prompt_id) do
    query!(
      "UPDATE prompts SET status = 'done', result_summary = ?, completed_at = ? WHERE id = ?",
      [summary, now_iso(), prompt_id]
    )

    :ok
  end

  @doc """
  Mark a prompt failed. Safe no-op if no row matches.
  """
  def fail(prompt_id, reason) when is_binary(prompt_id) do
    query!(
      "UPDATE prompts SET status = 'failed', result_summary = ?, completed_at = ? WHERE id = ?",
      [inspect(reason), now_iso(), prompt_id]
    )

    :ok
  end

  @doc """
  List prompts for a book, optionally scoped to a single target id.
  Returns the shape expected by the UI.
  """
  def list(book_id, target_id \\ nil) do
    {where, args} =
      if target_id do
        {"WHERE book_id = ? AND target_id = ?", [book_id, target_id]}
      else
        {"WHERE book_id = ?", [book_id]}
      end

    result =
      query!(
        """
        SELECT id, user_prompt, result_summary,
               target_type, target_id, status, created_at, completed_at
        FROM prompts
        #{where}
        ORDER BY created_at DESC
        LIMIT 50
        """,
        args
      )

    rows =
      Enum.map(result.rows, fn [
                                 id,
                                 user_prompt,
                                 result_summary,
                                 ttype,
                                 tid,
                                 status,
                                 created,
                                 completed
                               ] ->
        targets =
          case {ttype, tid} do
            {nil, _} -> []
            {_, nil} -> []
            {t, i} -> [%{target_type: t, target_id: i}]
          end

        %{
          id: id,
          run_id: id,
          agent_type: "user",
          user_prompt: user_prompt,
          result_summary: result_summary,
          targets: targets,
          status: status,
          created_at: created,
          completed_at: completed
        }
      end)

    {:ok, rows}
  end

  @doc """
  List recent prompts for a specific target (page or element).
  Returns the most recent `limit` prompts, oldest first.
  """
  def list_recent(target_type, target_id, limit \\ 5) do
    result =
      query!(
        """
        SELECT id, user_prompt, result_summary, status, created_at
        FROM prompts
        WHERE target_type = ? AND target_id = ?
        ORDER BY created_at DESC
        LIMIT ?
        """,
        [target_type, target_id, limit]
      )

    result.rows
    |> Enum.map(fn [id, user_prompt, result_summary, status, created_at] ->
      %{
        id: id,
        user_prompt: user_prompt,
        result_summary: result_summary,
        status: status,
        created_at: created_at
      }
    end)
    |> Enum.reverse()
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp query!(sql, args), do: Ecto.Adapters.SQL.query!(Repo, sql, args, log: :debug)
end
