defmodule Slidething.Agent.InstructionBuilder do
  @moduledoc """
  Builds task instruction strings for agent phases.

  Each agent receives a single task description string built from:
  - The phase name and user intent
  - Scope context (which page/element to work on)
  - Outputs from upstream planner phases
  - Existing DB state (elements on page, book metadata, etc.)
  """

  alias Slidething.Agent.PlanExecutor

  @doc """
  Build the task instruction string for a single agent task.

  phase: the Phase being executed
  scope: :book | {:page, page_id} | {:element, element_id}
  user_prompt: the original user prompt string
  phase_context_map: %{phase_name => PlanContext.t()} from upstream planner phases
  book_id: current book_id
  """
  def build(phase, scope, user_prompt, phase_context_map, book_id) do
    parts =
      [
        "User request: #{user_prompt}",
        scope_description(scope, book_id),
        phase_context(phase, phase_context_map),
        phase_planner_context(phase)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    Enum.join(parts, "\n\n")
  end

  @doc """
  Build instruction for a coordinator phase.
  Loads all page elements so the coordinator can review the full book.
  """
  def build_coordinator(phase, user_prompt, phase_context_map, book_id, page_ids) do
    parts =
      [
        "User request: #{user_prompt}",
        scope_description(:book, book_id),
        all_pages_summary(page_ids),
        phase_context(phase, phase_context_map),
        coordinator_instructions()
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    Enum.join(parts, "\n\n")
  end

  @doc """
  Build instruction for a planner phase (produces context, not content).
  """
  def build_planner(phase, scope, user_prompt, phase_context_map, book_id) do
    parts =
      [
        "User request: #{user_prompt}",
        planner_scope_description(scope, book_id),
        phase_context(phase, phase_context_map)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    Enum.join(parts, "\n\n")
  end

  # Private

  defp scope_description(:book, book_id) do
    case Slidething.Book.get(book_id) do
      {:ok, book} ->
        meta = book.metadata || %{}
        theme = meta["theme"] || meta[:theme]
        audience = meta["target_audience"] || meta[:target_audience]

        desc = ["Book ID: #{book_id}", "Title: #{book.title}"]
        desc = if theme, do: desc ++ ["Theme: #{theme}"], else: desc
        desc = if audience, do: desc ++ ["Target audience: #{audience}"], else: desc
        Enum.join(desc, "\n")

      _ ->
        "Book ID: #{book_id}"
    end
  end

  defp scope_description({:page, page_id}, book_id) do
    base = "Page ID: #{page_id}"

    elements_desc =
      case Slidething.Element.list(page_id) do
        [] ->
          nil

        elements ->
          lines =
            Enum.map(elements, fn el ->
              version = el[:latest_version] || %{}
              content = version[:content] || version["content"] || "(no content)"
              "  - [#{el.element_type}] #{el.id}: #{String.slice(to_string(content), 0, 80)}"
            end)

          "Existing elements on page:\n" <> Enum.join(lines, "\n")
      end

    scope_description(:book, book_id) <>
      "\n" <>
      base <>
      if(elements_desc, do: "\n" <> elements_desc, else: "")
  end

  defp scope_description({:element, element_id}, book_id) do
    base = "Element ID: #{element_id}"

    element_desc =
      case Slidething.Element.get(element_id, history: 1) do
        {:ok, el} ->
          version = el[:latest_version] || %{}
          content = version[:content] || version["content"]
          asset_path = version[:asset_path] || version["asset_path"]
          type_line = "Type: #{el.element_type}"

          content_line =
            if content, do: "Content: #{String.slice(to_string(content), 0, 200)}", else: nil

          asset_line = if asset_path, do: "Asset path: #{asset_path}", else: nil
          [type_line, content_line, asset_line] |> Enum.reject(&is_nil/1) |> Enum.join("\n")

        _ ->
          nil
      end

    scope_description(:book, book_id) <>
      "\n" <>
      base <>
      if(element_desc, do: "\n" <> element_desc, else: "")
  end

  defp planner_scope_description(:book, book_id) do
    scope_description(:book, book_id)
  end

  defp planner_scope_description({:page, page_id}, book_id) do
    scope_description({:page, page_id}, book_id)
  end

  defp planner_scope_description(_scope, book_id) do
    scope_description(:book, book_id)
  end

  defp phase_context(phase, phase_context_map) do
    context_str = PlanExecutor.build_phase_context(phase, phase_context_map)
    if context_str == "", do: nil, else: context_str
  end

  defp phase_planner_context(%{context: nil}), do: nil
  defp phase_planner_context(%{context: ctx}) when map_size(ctx) == 0, do: nil

  defp phase_planner_context(%{context: ctx}) do
    "=== Planner notes for this step ===\n#{Jason.encode!(ctx, pretty: true)}"
  end

  defp all_pages_summary([]), do: nil

  defp all_pages_summary(page_ids) do
    pages_text =
      Enum.map(page_ids, fn page_id ->
        elements = Slidething.Element.list(page_id)

        elements_text =
          Enum.map(elements, fn el ->
            version = el[:latest_version] || %{}
            content = version[:content] || version["content"] || "(empty)"
            asset = version[:asset_path] || version["asset_path"]

            line =
              "    [#{el.element_type}] #{el.id}: #{String.slice(to_string(content), 0, 200)}"

            if asset, do: line <> " (image: #{asset})", else: line
          end)
          |> Enum.join("\n")

        "  Page #{page_id}:\n#{if elements_text == "", do: "    (no elements)", else: elements_text}"
      end)
      |> Enum.join("\n")

    "Current book content:\n#{pages_text}"
  end

  defp coordinator_instructions do
    """
    Review the book content above for coherence, consistency, and quality.

    Output JSON with exactly these two keys:
      "context": { your assessment as a map }
      "plan_patches": [ list of patch operations, or [] if no changes needed ]

    Patch operations:
      { "op": "add",    "phase": { name, step_type, agent_type, scope, depends_on, condition, max_retries } }
      { "op": "remove", "name": "phase_name" }
      { "op": "update", "name": "phase_name", "fields": { max_retries, condition, config } }

    Rules:
    - Do NOT add coordinator phases.
    - Added phase names must be unique.
    - Use "add" to insert targeted revision passes for specific pages.
    - Output JSON only. No prose, no markdown fences.
    """
  end
end
