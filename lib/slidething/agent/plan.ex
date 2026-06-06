defmodule Slidething.Agent.Phase do
  @moduledoc """
  A single phase in a GeneratedPlan.

  step_type:
    :planner   — LLM call that outputs context (no tool calls, no DB writes)
    :agent     — LLM agent that executes tools and produces book content
    :validator — deterministic or LLM checks; outputs issues, no writes

  scope:
    :book        — one task for the whole book
    :per_page    — one task per page (all run in parallel)
    :per_element — one task per matching element (all run in parallel)

  condition: optional atom evaluated at runtime before starting the phase.
    Supported values: :has_layout_issues, :has_content_issues
    nil means always run (if deps are met).

  depends_on: list of phase names that must complete before this phase starts.
  max_retries: how many times to retry on agent failure (default 2).
  """

  @enforce_keys [:name, :step_type, :agent_type, :scope]
  defstruct [
    :name,
    :step_type,
    :agent_type,
    :scope,
    :context,
    :condition,
    depends_on: [],
    max_retries: 2,
    config: %{}
  ]

  @type step_type :: :planner | :agent | :validator
  @type scope :: :book | :per_page | :per_element
  @type condition :: nil | :has_layout_issues | :has_content_issues
  @type agent_type :: :planner | :content | :layout | :media | :research | :validator

  @type t :: %__MODULE__{
          name: String.t(),
          step_type: step_type(),
          agent_type: agent_type(),
          scope: scope(),
          context: map() | nil,
          condition: condition(),
          depends_on: [String.t()],
          max_retries: non_neg_integer(),
          config: map()
        }

  @valid_step_types [:planner, :agent, :validator, :coordinator]
  @valid_scopes [:book, :per_page, :per_element]
  @valid_conditions [nil, :has_layout_issues, :has_content_issues]

  def valid_step_types, do: @valid_step_types
  def valid_scopes, do: @valid_scopes
  def valid_conditions, do: @valid_conditions
end

defmodule Slidething.Agent.GeneratedPlan do
  @moduledoc """
  The output of the Planner LLM call.
  Contains book + page structure to create, and a list of phases to execute.
  """

  defstruct [:context, :phases]

  @type t :: %__MODULE__{
          context: String.t() | nil,
          phases: [Slidething.Agent.Phase.t()]
        }

  @doc "Parse from decoded JSON map."
  def from_map(map) do
    context = map["context"]

    phases = case map["phases"] do
      nil -> []
      ps when is_list(ps) -> Enum.map(ps, &phase_from_map/1)
      _ -> []
    end

    %__MODULE__{context: context, phases: phases}
  end

  def phase_from_map(p) do
    %Slidething.Agent.Phase{
      name:        p["name"],
      step_type:   atomize(p["step_type"]),
      agent_type:  atomize(p["agent_type"]),
      scope:       atomize(p["scope"]),
      context:     p["context"],
      condition:   atomize(p["condition"]),
      depends_on:  p["depends_on"] || [],
      max_retries: p["max_retries"] || 2,
      config:      p["config"] || %{}
    }
  end

  defp atomize(nil), do: nil
  defp atomize(s) when is_binary(s), do: String.to_atom(s)
  defp atomize(a) when is_atom(a), do: a
end

defmodule Slidething.Agent.PlanContext do
  @moduledoc """
  Context produced by a planner phase and passed to downstream phases.
  Stored in orchestrator state keyed by phase name.
  """

  defstruct [:phase_name, :scope, :data]

  @type t :: %__MODULE__{
          phase_name: String.t(),
          scope: term(),
          data: map() | String.t()
        }
end

defmodule Slidething.Agent.PlanValidator do
  @moduledoc "Validates a list of Phase structs before execution."

  alias Slidething.Agent.Phase

  @doc "Raises if the plan is invalid. Returns :ok otherwise."
  def validate_plan!(phases) do
    :ok = check_names_present(phases)
    :ok = check_no_duplicate_names(phases)
    :ok = check_dep_refs(phases)
    :ok = check_no_cycles(phases)
    :ok = check_valid_fields(phases)
    :ok
  end

  defp check_names_present(phases) do
    Enum.each(phases, fn p ->
      if is_nil(p.name) or p.name == "",
        do: raise("Phase is missing a name: #{inspect(p)}")
    end)
    :ok
  end

  defp check_no_duplicate_names(phases) do
    names = Enum.map(phases, & &1.name)
    dupes = names -- Enum.uniq(names)
    if dupes != [], do: raise("Duplicate phase names: #{inspect(dupes)}")
    :ok
  end

  defp check_dep_refs(phases) do
    names = MapSet.new(phases, & &1.name)
    Enum.each(phases, fn p ->
      Enum.each(p.depends_on, fn dep ->
        unless MapSet.member?(names, dep),
          do: raise("Phase '#{p.name}' depends on unknown phase '#{dep}'")
      end)
    end)
    :ok
  end

  defp check_no_cycles(phases) do
    graph = Map.new(phases, fn p -> {p.name, p.depends_on} end)
    Enum.each(phases, fn p ->
      if has_cycle?(p.name, graph, MapSet.new()),
        do: raise("Cycle detected involving phase '#{p.name}'")
    end)
    :ok
  end

  defp has_cycle?(name, graph, visited) do
    if MapSet.member?(visited, name) do
      true
    else
      visited = MapSet.put(visited, name)
      Enum.any?(Map.get(graph, name, []), &has_cycle?(&1, graph, visited))
    end
  end

  defp check_valid_fields(phases) do
    Enum.each(phases, fn p ->
      unless p.step_type in Phase.valid_step_types(),
        do: raise("Phase '#{p.name}' has invalid step_type: #{p.step_type}")
      unless p.scope in Phase.valid_scopes(),
        do: raise("Phase '#{p.name}' has invalid scope: #{p.scope}")
      unless p.condition in Phase.valid_conditions(),
        do: raise("Phase '#{p.name}' has invalid condition: #{p.condition}")
    end)
    :ok
  end
end

defmodule Slidething.Agent.PlanExecutor do
  @moduledoc """
  Stateless helpers for plan execution.
  Determines which phases are ready to run given current completion + condition state.
  """

  alias Slidething.Agent.Phase

  @doc """
  Returns phases that are ready to start:
  - All depends_on phases are in completed_phases
  - The phase itself is not already completed or running
  - If it has a condition, the condition evaluates true against orchestrator state
  """
  def find_ready_phases(phases, completed_phases, running_phases, orchestrator_state) do
    phases
    |> Enum.reject(fn p ->
      MapSet.member?(completed_phases, p.name) or
        MapSet.member?(running_phases, p.name)
    end)
    |> Enum.filter(fn p ->
      Enum.all?(p.depends_on, &MapSet.member?(completed_phases, &1)) and
        condition_met?(p.condition, orchestrator_state)
    end)
  end

  @doc "Evaluate a condition atom against orchestrator state."
  def condition_met?(nil, _state), do: true

  def condition_met?(:has_layout_issues, state) do
    issues = Map.get(state, :validation_issues, %{})
    Enum.any?(issues, fn {_phase, phase_issues} ->
      is_list(phase_issues) and phase_issues != []
    end)
  end

  def condition_met?(:has_content_issues, state) do
    issues = Map.get(state, :validation_issues, %{})
    Enum.any?(issues, fn {phase_name, phase_issues} ->
      String.contains?(to_string(phase_name), "content") and
        is_list(phase_issues) and phase_issues != []
    end)
  end

  def condition_met?(condition, _state) do
    raise "Unknown condition: #{inspect(condition)}"
  end

  @doc "True when all non-conditional phases are done and no conditional phases remain runnable."
  def all_phases_complete?(phases, completed_phases, orchestrator_state) do
    required = Enum.reject(phases, fn p ->
      not is_nil(p.condition) and not condition_met?(p.condition, orchestrator_state)
    end)
    Enum.all?(required, fn p -> MapSet.member?(completed_phases, p.name) end)
  end

  @doc "Build context string to inject into a phase's task description."
  def build_phase_context(phase, phase_context_map) do
    Enum.flat_map(phase.depends_on, fn dep_name ->
      case Map.get(phase_context_map, dep_name) do
        nil -> []
        ctx -> ["=== Output from phase '#{dep_name}' ===\n#{format_context_data(ctx.data)}"]
      end
    end)
    |> Enum.join("\n\n")
  end

  defp format_context_data(data) when is_binary(data), do: data
  defp format_context_data(data), do: Jason.encode!(data, pretty: true)
end

defmodule Slidething.Agent.PlanPatcher do
  @moduledoc """
  Applies coordinator-issued plan patches to a live phases list.

  Supported operations:
    %{"op" => "add",    "phase"  => phase_map}
    %{"op" => "remove", "name"   => phase_name}
    %{"op" => "update", "name"   => phase_name, "fields" => %{...}}

  Constraints enforced here (PlanValidator re-validates the result separately):
  - Coordinator phases cannot be added — prevents runaway meta-loops
  - Added phase names must not already exist in the plan
  - Cannot remove an already-completed phase
  - Only safe fields (max_retries, condition, config) can be updated
  """

  alias Slidething.Agent.GeneratedPlan

  @doc "Apply a list of patch maps to phases. Returns {:ok, new_phases} | {:error, reason}."
  def apply(phases, patches, completed_phases \\ MapSet.new()) do
    Enum.reduce_while(patches, {:ok, phases}, fn patch, {:ok, acc} ->
      case apply_one(acc, patch, completed_phases) do
        {:ok, new} -> {:cont, {:ok, new}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp apply_one(phases, %{"op" => "add", "phase" => phase_map}, _completed) do
    phase = GeneratedPlan.phase_from_map(phase_map)

    cond do
      phase.step_type == :coordinator ->
        {:error, "coordinator phases cannot add other coordinator phases"}

      Enum.any?(phases, &(&1.name == phase.name)) ->
        {:error, "phase '#{phase.name}' already exists"}

      is_nil(phase.name) or phase.name == "" ->
        {:error, "added phase is missing a name"}

      true ->
        {:ok, phases ++ [phase]}
    end
  end

  defp apply_one(phases, %{"op" => "remove", "name" => name}, completed) do
    if MapSet.member?(completed, name) do
      {:error, "cannot remove already-completed phase '#{name}'"}
    else
      {:ok, Enum.reject(phases, &(&1.name == name))}
    end
  end

  defp apply_one(phases, %{"op" => "update", "name" => name, "fields" => fields}, _completed) do
    if Enum.any?(phases, &(&1.name == name)) do
      new_phases = Enum.map(phases, fn p ->
        if p.name == name, do: safe_update(p, fields), else: p
      end)
      {:ok, new_phases}
    else
      {:error, "cannot update unknown phase '#{name}'"}
    end
  end

  defp apply_one(_phases, %{"op" => op}, _completed),
    do: {:error, "unknown patch op '#{op}'"}

  defp apply_one(_phases, patch, _completed),
    do: {:error, "malformed patch: #{inspect(patch)}"}

  # Only allow updating fields that don't affect control flow structurally.
  defp safe_update(phase, fields) do
    Enum.reduce(fields, phase, fn
      {"max_retries", v}, p when is_integer(v) and v >= 0 -> %{p | max_retries: v}
      {"condition", nil}, p -> %{p | condition: nil}
      {"condition", v}, p when is_binary(v) -> %{p | condition: String.to_atom(v)}
      {"config", v}, p when is_map(v) -> %{p | config: v}
      {k, _}, p ->
        require Logger
        Logger.warning("[PlanPatcher] Ignoring disallowed update field '#{k}'")
        p
    end)
  end
end
