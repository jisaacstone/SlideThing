defmodule Mix.Tasks.Slidething.Generate do
  @moduledoc """
  Generate a children's book from the command line.

  ## Usage

      mix generate "Create a 5-page children's book about a penguin who wants to fly"
      SLIDETHING_PROVIDER=gemini mix generate "Create a children's book about a fox"
      mix generate "Create a book" --provider openrouter

  Streams agent events in real time. Blocks until completion.
  """

  use Mix.Task

  @shortdoc "Generate a children's book"

  @impl true
  def run(args) do
    {opts, rest, []} =
      OptionParser.parse(args, strict: [provider: :string])

    prompt = Enum.join(rest, " ")

    if prompt == "" do
      IO.puts("Usage: mix generate \"Your book prompt\" [--provider gemini|mock|openrouter]")
      System.halt(1)
    end

    if provider = opts[:provider] do
      System.put_env("SLIDETHING_PROVIDER", provider)
    end

    IO.puts("==> Starting slidething...")
    {:ok, _} = Application.ensure_all_started(:slidething)

    IO.puts("")
    IO.puts("Prompt: #{prompt}")
    IO.puts("")

    alias Slidething.Agent.API

    {:ok, run_id} = API.start_run(prompt)

    API.subscribe_to_run(run_id)
    API.subscribe_to_agent_events(run_id)

    wait_for_completion()
  end

  defp wait_for_completion do
    receive do
      {:run_event, %{event: :started, data: %{prompt: prompt}}} ->
        IO.puts("▶ Run started")

        if book_id = prompt[:book_id] do
          IO.puts("  book_id: #{book_id}")
        end

        wait_for_completion()

      {:run_event, %{event: :phase_started, data: %{phase: phase}}} ->
        IO.puts("→ Phase: #{phase}")
        wait_for_completion()

      {:run_event, %{event: :phase_completed, data: %{phase: phase}}} ->
        IO.puts("✓ Phase done: #{phase}")
        wait_for_completion()

      {:agent_event, %{event: :task_started, agent_type: agent, data: %{task: task}}} ->
        IO.puts("  ── #{agent} working: #{String.slice(task, 0, 80)}")
        wait_for_completion()

      {:agent_event, %{event: :llm_call_started, agent_type: agent, data: %{iteration: iter}}} ->
        IO.puts("  🤖 #{agent} (iter #{iter}) → LLM")
        wait_for_completion()

      {:agent_event, %{event: :tools_executed, agent_type: agent, data: %{tool_count: count}}} ->
        IO.puts("  🔧 #{agent}: #{count} tool(s)")
        wait_for_completion()

      {:agent_event, %{event: :completed, agent_type: agent}} ->
        IO.puts("  ✓ #{agent} done")
        wait_for_completion()

      {:run_event, %{event: :validation_started}} ->
        IO.puts("→ Validating...")
        wait_for_completion()

      {:run_event, %{event: :completed, data: %{duration_ms: ms}}} ->
        IO.puts("")
        IO.puts("=== Book generated (#{ms}ms) ===")

      {:run_event, %{event: :failed, data: %{reason: reason}}} ->
        IO.puts("")
        IO.puts("FAILED: #{inspect(reason)}")
        System.halt(1)

      _ ->
        wait_for_completion()
    end
  end
end