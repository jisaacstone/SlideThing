import Config

config :slidething, Slidething.Repo,
  database: "priv/repo/slidething_test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :slidething, SlidethingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ajB8VE0P8X7FnxOcsQiWl8xAA3ALB1BozKqBMViY62nIq7yofJ2eO8aPZltMmPjD",
  server: false

config :slidething, :media_dir, "/tmp/slidething_test_media"

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix,
  sort_verified_routes_query_params: true
