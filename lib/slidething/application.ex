defmodule Slidething.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SlidethingWeb.Telemetry,
        Slidething.Repo,
        {Phoenix.PubSub, name: Slidething.PubSub},
        # Registry for tracking agent processes by {run_id, agent_type, scope}
        {Registry, keys: :unique, name: Slidething.AgentRegistry},
        # Registry for tracking orchestrators by run_id
        {Registry, keys: :unique, name: Slidething.RunRegistry},
        # DynamicSupervisor for per-run supervision trees
        {DynamicSupervisor, name: Slidething.RunSupervisor, strategy: :one_for_one},
        # Task.Supervisor for IO-bound work (LLM calls, image generation, HTTP)
        {Task.Supervisor, name: Slidething.IOTaskSupervisor}
      ] ++
        if Mix.env() == :test do
          []
        else
          [Slidething.Agent.Config]
        end ++
        [SlidethingWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Slidething.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    Slidething.Schema.Bootstrap.ensure_tables()

    if Mix.env() == :test do
      Slidething.AssetStore.clean!()
    else
      Slidething.AssetStore.ensure_dir!()
    end

    {:ok, pid}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SlidethingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
