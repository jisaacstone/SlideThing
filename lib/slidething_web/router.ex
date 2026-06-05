defmodule SlidethingWeb.Router do
  use SlidethingWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SlidethingWeb do
    pipe_through :browser
    get "/", PageController, :root
  end

  scope "/api", SlidethingWeb do
    pipe_through :api

    # Agent runs
    post "/runs", RunController, :create
    get  "/runs/:run_id", RunController, :show

    # Books
    get    "/books", BookController, :list
    post   "/books", BookController, :create
    delete "/books/:book_id", BookController, :delete
    get    "/books/:book_id", BookController, :show
    get    "/books/:book_id/prompts", PromptController, :list

    # Pages
    post   "/books/:book_id/pages", BookController, :create_page
    get    "/pages/:page_id", PageController, :show
    delete "/pages/:page_id", PageController, :delete

    # Elements
    get    "/pages/:page_id/elements", ElementController, :list
    get    "/elements/:element_id", ElementController, :show
    patch  "/elements/:element_id", ElementController, :update_content

    # Layouts
    get    "/pages/:page_id/layouts", LayoutController, :list
    get    "/pages/:page_id/layouts/:format_id", LayoutController, :show
    patch  "/pages/:page_id/layouts", LayoutController, :move_element

    # Formats
    get    "/books/:book_id/formats", FormatController, :list
    get    "/formats", FormatController, :list_all

    # Assets
    get    "/assets/*filename", AssetController, :show
  end
end