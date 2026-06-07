import Config

config :slidething, Slidething.Repo,
  database: "priv/repo/slidething_dev.db",
  pool_size: 5,
  show_sensitive_data_on_connection_error: true

config :slidething, SlidethingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "6HZRL06k+Dx9bCp6rzjivlHiA2G4YlxnvB17E+53eBwIxQjPO/JNXOpeD7x3qmUb",
  watchers: [
    node: [
      "node_modules/.bin/vite",
      "--host",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :slidething, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :slidething,
       :agent_config_path,
       System.get_env("SLIDETHING_AGENT_CONFIG") || "config/agents.json"
