defmodule Slidething.Repo do
  use Ecto.Repo,
    otp_app: :slidething,
    adapter: Ecto.Adapters.SQLite3
end
