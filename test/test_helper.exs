ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Slidething.Repo, :manual)

unless Process.whereis(Slidething.Agent.Config) do
  Slidething.Agent.Config.start_link(config_path: "config/agents.json")
end
