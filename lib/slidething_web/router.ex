defmodule SlidethingWeb.Router do
  use SlidethingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SlidethingWeb do
    pipe_through :api

    # Agent runs
    post "/runs", RunController, :create
    get  "/runs/:run_id", RunController, :show

    # Books
    get    "/books", BookController, :list
    post   "/books", BookController, :create
    get    "/books/:book_id", BookController, :show

    # Pages
    get    "/pages/:page_id", PageController, :show

    # Elements
    get    "/pages/:page_id/elements", ElementController, :list
    get    "/elements/:element_id", ElementController, :show

    # Layouts
    get    "/pages/:page_id/layouts", LayoutController, :list
    get    "/pages/:page_id/layouts/:format_id", LayoutController, :show

    # Formats
    get    "/books/:book_id/formats", FormatController, :list
    get    "/formats", FormatController, :list_all

    # Assets
    get    "/assets/*filename", AssetController, :show
  end
end