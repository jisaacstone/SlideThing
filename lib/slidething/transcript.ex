defmodule Slidething.Transcript do
  @moduledoc """
  Persists agent transcripts: one `agent_runs` row per agent invocation,
  one `agent_messages` row per LLM message in that invocation.

  Independent of the user-facing `prompts` table. A single prompt has
  one orchestrator run (= one prompt row) and N agent runs under it.

  Tables are not FK-constrained at the SQL level (SQLite FKs off), so
  callers that bypass `Slidething.Agent.API` can still write transcripts
  without a parent prompt row — useful for tests.
  """

  require Logger

  alias Slidething.Agent.{Message, ToolCall, ToolResult}
  alias Slidething.Repo

  @doc """
  Record the start of an agent invocation. Returns the agent_run_id.
  """
  def start_agent_run(prompt_id, agent_type, scope, agent_spec) do
    id = Ecto.UUID.generate()
    {scope_type, scope_id} = encode_scope(scope)
    now = now_iso()

    query!(
      """
      INSERT INTO agent_runs
        (id, prompt_id, agent_type, scope_type, scope_id, provider, model, status, started_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 'running', ?)
      """,
      [
        id,
        prompt_id,
        to_string(agent_type),
        scope_type,
        scope_id,
        agent_spec && agent_spec.provider,
        agent_spec && agent_spec.model,
        now
      ]
    )

    id
  end

  @doc """
  Append messages from the agent's conversation. Each message becomes one row.

  `iteration` is the loop iteration the messages were produced in (0-indexed).
  """
  def append_messages(agent_run_id, iteration, messages) when is_list(messages) do
    Enum.each(messages, fn msg -> append_message(agent_run_id, iteration, msg) end)
  end

  def append_message(agent_run_id, iteration, %Message{} = msg) do
    id = Ecto.UUID.generate()
    now = now_iso()

    query!(
      """
      INSERT INTO agent_messages
        (id, agent_run_id, iteration, role, content, tool_calls, tool_results, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        id,
        agent_run_id,
        iteration,
        Atom.to_string(msg.role),
        msg.content,
        encode_tool_calls(msg.tool_calls),
        encode_tool_results(msg.tool_results),
        now
      ]
    )

    id
  end

  @doc """
  Mark an agent run completed with the final result.
  """
  def complete_agent_run(agent_run_id, result) do
    query!(
      "UPDATE agent_runs SET status = 'done', final_result = ?, completed_at = ? WHERE id = ?",
      [encode_result(result), now_iso(), agent_run_id]
    )

    :ok
  end

  @doc """
  Mark an agent run failed.
  """
  def fail_agent_run(agent_run_id, reason) do
    query!(
      "UPDATE agent_runs SET status = 'failed', failure_reason = ?, completed_at = ? WHERE id = ?",
      [inspect(reason), now_iso(), agent_run_id]
    )

    :ok
  end

  @doc """
  List all agent runs for a prompt, oldest first. Each row includes its messages.
  Intended for the debug/history UI.
  """
  def list_for_prompt(prompt_id) do
    runs =
      query!(
        """
        SELECT id, agent_type, scope_type, scope_id, provider, model,
               status, final_result, failure_reason, started_at, completed_at
        FROM agent_runs
        WHERE prompt_id = ?
        ORDER BY started_at ASC
        """,
        [prompt_id]
      )

    Enum.map(runs.rows, fn [id, agent_type, st, sid, prov, model, status, result, fail, started, completed] ->
      %{
        id: id,
        agent_type: agent_type,
        scope_type: st,
        scope_id: sid,
        provider: prov,
        model: model,
        status: status,
        final_result: result,
        failure_reason: fail,
        started_at: started,
        completed_at: completed,
        messages: list_messages(id)
      }
    end)
  end

  defp list_messages(agent_run_id) do
    result =
      query!(
        """
        SELECT iteration, role, content, tool_calls, tool_results, created_at
        FROM agent_messages
        WHERE agent_run_id = ?
        ORDER BY created_at ASC, rowid ASC
        """,
        [agent_run_id]
      )

    Enum.map(result.rows, fn [iter, role, content, tcalls, tresults, created] ->
      %{
        iteration: iter,
        role: role,
        content: content,
        tool_calls: decode_json(tcalls),
        tool_results: decode_json(tresults),
        created_at: created
      }
    end)
  end

  # Encoding helpers

  defp encode_scope(nil), do: {nil, nil}
  defp encode_scope(:book), do: {"book", nil}
  defp encode_scope({:page, id}), do: {"page", id}
  defp encode_scope({:pages, ids}), do: {"pages", Jason.encode!(ids)}
  defp encode_scope({:element, id}), do: {"element", id}
  defp encode_scope({:elements, ids}), do: {"elements", Jason.encode!(ids)}
  defp encode_scope(other) when is_atom(other), do: {Atom.to_string(other), nil}
  defp encode_scope(other), do: {inspect(other), nil}

  defp encode_tool_calls(nil), do: nil

  defp encode_tool_calls(calls) when is_list(calls) do
    calls
    |> Enum.map(fn %ToolCall{call_id: id, tool: tool, args: args} ->
      %{call_id: id, tool: to_string(tool), args: args}
    end)
    |> Jason.encode!()
  end

  defp encode_tool_results(nil), do: nil

  defp encode_tool_results(results) when is_list(results) do
    results
    |> Enum.map(fn %ToolResult{call_id: id, tool: tool, success: ok, data: data, error: err} ->
      %{call_id: id, tool: to_string(tool), success: ok, data: safe_jsonable(data), error: err}
    end)
    |> Jason.encode!()
  end

  defp encode_result({:final, msg}), do: Jason.encode!(%{type: "final", message: msg})
  defp encode_result({:patch, patch}), do: Jason.encode!(%{type: "patch", patch: safe_jsonable(patch)})
  defp encode_result(other), do: inspect(other)

  defp decode_json(nil), do: nil

  defp decode_json(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, v} -> v
      _ -> s
    end
  end

  defp safe_jsonable(term) do
    case Jason.encode(term) do
      {:ok, _} -> term
      _ -> inspect(term)
    end
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp query!(sql, args), do: Ecto.Adapters.SQL.query!(Repo, sql, args, log: :debug)
end
