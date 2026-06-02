defmodule SlidethingWeb.PromptController do
  use SlidethingWeb, :controller

  alias Slidething.Prompt

  def list(conn, %{"book_id" => book_id} = params) do
    target_id = params["target_id"]

    case Prompt.list(book_id, target_id) do
      {:ok, prompts} ->
        json(conn, prompts)
    end
  end
end