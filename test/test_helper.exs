ExUnit.start()

unless Process.whereis(Slidething.Agent.Config) do
  Slidething.Agent.Config.start_link(config_path: "config/agents.json")
end

Slidething.Agent.Config.list_specs()
|> Enum.each(fn {name, _spec} ->
  Slidething.Agent.Config.set(name, provider: "mock")
end)
