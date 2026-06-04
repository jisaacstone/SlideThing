defmodule Slidething.Agent.Config do
  @moduledoc """
  Loads and caches agent configuration from agents.json.

  Provides AgentSpec lookups keyed by agent name (atom).
  """

  use GenServer

  alias Slidething.Agent.AgentSpec

  defstruct [:config_path, :agents]

  @type t :: %__MODULE__{
          config_path: String.t(),
          agents: %{atom() => AgentSpec.t()}
        }

  # Client API

  def start_link(opts) do
    config_path =
      Keyword.get(opts, :config_path) ||
        Application.get_env(:slidething, :agent_config_path, "config/agents.json")

    GenServer.start_link(__MODULE__, config_path, name: __MODULE__)
  end

  @doc """
  Returns the full AgentSpec for the given agent name, or nil.
  """
  def agent_spec(agent_name) when is_atom(agent_name) do
    GenServer.call(__MODULE__, {:agent_spec, agent_name})
  end

  @doc """
  Returns all loaded agent specs as a map of atom → AgentSpec.
  """
  def list_specs do
    GenServer.call(__MODULE__, :list_agent_specs)
  end

  @doc """
  Updates a single agent's config at runtime. Merges keyword/map fields into the AgentSpec.

  ## Examples
      iex> Slidething.Agent.Config.set(:content, provider: "gemini", model: "gemini-2.5-flash")
      :ok
      iex> Slidething.Agent.Config.set(:nonexistent, provider: "mock")
      {:error, :unknown_agent}
  """
  def set(agent_name, fields) when is_atom(agent_name) do
    GenServer.call(__MODULE__, {:set, agent_name, fields})
  end

  @doc """
  Reloads agent config from disk, resetting all runtime changes.
  """
  def reset do
    GenServer.call(__MODULE__, :reload)
  end

  @doc """
  Returns all loaded agent specs.
  """
  def list_agent_specs do
    GenServer.call(__MODULE__, :list_agent_specs)
  end

  # Server callbacks

  @impl true
  def init(config_path) do
    state = load_config(config_path)
    {:ok, state}
  end

  @impl true
  def handle_call({:agent_spec, agent_name}, _from, state) do
    {:reply, Map.get(state.agents, agent_name), state}
  end

  @impl true
  def handle_call(:list_agent_specs, _from, state) do
    {:reply, state.agents, state}
  end

  @impl true
  def handle_call({:set, agent_name, fields}, _from, state) do
    case Map.fetch(state.agents, agent_name) do
      {:ok, spec} ->
        updated = update_spec(spec, fields)
        {:reply, :ok, %{state | agents: Map.put(state.agents, agent_name, updated)}}

      :error ->
        {:reply, {:error, :unknown_agent}, state}
    end
  end

  @impl true
  def handle_call(:reload, _from, state) do
    new_state = load_config(state.config_path)
    {:reply, :ok, new_state}
  end

  # Private

  defp load_config(config_path) do
    base = read_and_parse("config/agents.json")
    base_agents = base["agents"]

    spec_map =
      Map.new(base_agents, fn {name, attrs} ->
        spec = attrs_to_spec(String.to_atom(name), attrs)
        {spec.name, spec}
      end)

    if config_path == "config/agents.json" do
      %__MODULE__{config_path: config_path, agents: spec_map}
    else
      override = read_and_parse(config_path)
      override_agents = override["agents"] || %{}
      merged = merge_overrides(spec_map, override_agents)
      %__MODULE__{config_path: config_path, agents: merged}
    end
  end

  defp merge_overrides(spec_map, override_agents) do
    Map.new(spec_map, fn {name, spec} ->
      overrides = override_agents[Atom.to_string(name)] || %{}

      provider = override_field(overrides, "provider", spec.provider)
      model = override_field(overrides, "model", spec.model)
      image_provider = override_field(overrides, "image_provider", spec.image_provider)
      image_model = override_field(overrides, "image_model", spec.image_model)

      {name,
       %{
         spec
         | provider: provider,
           model: model,
           image_provider: image_provider,
           image_model: image_model
       }}
    end)
  end

  defp override_field(overrides, key, default) do
    case Map.get(overrides, key) do
      v when is_binary(v) -> v
      _ -> default
    end
  end

  defp read_and_parse(config_path) do
    case File.read(config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} -> config
          {:error, error} -> raise "Failed to parse #{config_path}: #{inspect(error)}"
        end

      {:error, reason} ->
        raise "Failed to read #{config_path}: #{reason}"
    end
  end

  defp attrs_to_spec(name, attrs) do
    %AgentSpec{
      name: name,
      provider: Map.get(attrs, "provider", "mock"),
      model: Map.get(attrs, "model", "mock-model"),
      temperature: Map.get(attrs, "temperature", 0.7),
      max_tokens: Map.get(attrs, "max_tokens", 4000),
      max_iterations: Map.get(attrs, "max_iterations", 10),
      system_prompt: Map.get(attrs, "system_prompt", "You are a helpful assistant."),
      tools: Enum.map(Map.get(attrs, "tools", []), &String.to_atom/1),
      image_provider: Map.get(attrs, "image_provider", "mock"),
      image_model: Map.get(attrs, "image_model", "mock-image-model")
    }
  end

  defp update_spec(spec, fields) when is_list(fields) do
    update_spec(spec, Map.new(fields))
  end

  defp update_spec(spec, fields) do
    Map.merge(spec, convert_spec_fields(fields))
  end

  defp convert_spec_fields(fields) do
    Map.new(fields, fn
      {:tools, tools} when is_list(tools) ->
        {:tools, Enum.map(tools, &string_to_atom/1)}

      {key, value} ->
        {string_to_atom(key), value}
    end)
  end

  defp string_to_atom(val) when is_atom(val), do: val
  defp string_to_atom(val) when is_binary(val), do: String.to_atom(val)
end