defmodule SlidethingWeb.Router do
  use SlidethingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SlidethingWeb do
    pipe_through :api
  end
end
