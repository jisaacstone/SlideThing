defmodule SlidethingWeb.RunController do
  use SlidethingWeb, :controller

  alias Slidething.Agent.API

  def create(conn, %{"prompt" => prompt} = params) do
    book_id = params["book_id"]
    target_type = params["target_type"]
    target_id = params["target_id"]

    case API.start_run(prompt, book_id, target_type, target_id) do
      {:ok, run_id} ->
        conn
        |> put_status(201)
        |> json(%{run_id: run_id})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: inspect(reason)})
    end
  end

  def show(conn, %{"run_id" => run_id}) do
    case API.get_run_status(run_id) do
      :not_found ->
        conn
        |> put_status(404)
        |> json(%{error: "run not found"})

      state ->
        json(conn, %{
          run_id: state.run_id,
          status: state.status,
          phase: state.running_phases |> MapSet.to_list() |> List.first(),
          prompt: state.prompt,
          book_id: state.book_id
        })
    end
  end
end
