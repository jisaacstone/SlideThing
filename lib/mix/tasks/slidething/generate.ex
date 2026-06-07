defmodule Mix.Tasks.Slidething.Generate do
  @moduledoc """
  Generate a children's book from the command line.

  ## Usage

      mix generate "Create a 5-page children's book about a penguin who wants to fly"
      mix generate "Create a children's book about a fox" --provider openrouter
      mix generate "Create a book" --provider openrouter --model google/gemma-4-31b-it:free

  Streams agent events in real time. Blocks until completion.
  """

  use Mix.Task

  @shortdoc "Generate a children's book"

  @agent_types [:planner, :content, :research, :layout, :media]

  @provider_default_models %{
    "mock" => "mock-model",
    "gemini" => "gemini-2.5-flash",
    "openrouter" => "google/gemma-4-31b-it:free"
  }

  @image_provider_default_models %{
    "mock" => "mock-image-model",
    "gemini" => "imagen-3.0-generate-002",
    "openrouter" => "black-forest-labs/flux-schnell"
  }

  @impl true
  def run(args) do
    {opts, rest, []} =
      OptionParser.parse(args,
        strict: [provider: :string, model: :string, image_provider: :string, image_model: :string]
      )

    prompt = Enum.join(rest, " ")

    if prompt == "" do
      IO.puts(
        "Usage: mix generate \"Your book prompt\" [--provider mock|gemini|openrouter] [--model MODEL]"
      )

      System.halt(1)
    end

    IO.puts("==> Starting slidething...")
    {:ok, _} = Application.ensure_all_started(:slidething)

    if provider = opts[:provider] do
      image_provider = opts[:image_provider] || provider
      apply_provider_override(provider, opts[:model], image_provider, opts[:image_model])
    end

    IO.puts("")
    IO.puts("Prompt: #{prompt}")
    IO.puts("")

    alias Slidething.Agent.API

    {:ok, run_id} = API.start_run(prompt)

    API.subscribe(run_id)

    wait_for_completion()
  end

  defp apply_provider_override(provider, model_override, image_provider, image_model_override) do
    model = model_override || Map.get(@provider_default_models, provider, provider)

    image_model =
      image_model_override ||
        Map.get(@image_provider_default_models, image_provider, image_provider)

    IO.puts("Provider: #{provider}, Model: #{model}")
    IO.puts("Image provider: #{image_provider}, Image model: #{image_model}")

    Enum.each(@agent_types, fn agent ->
      Slidething.Agent.Config.set(agent,
        provider: provider,
        model: model,
        image_provider: image_provider,
        image_model: image_model
      )
    end)
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
