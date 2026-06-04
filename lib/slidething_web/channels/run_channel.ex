defmodule SlidethingWeb.RunChannel do
  use SlidethingWeb, :channel

  alias Slidething.Agent.API

  @impl true
  def join("run:" <> run_id, _payload, socket) do
    API.subscribe(run_id)
    {:ok, assign(socket, :run_id, run_id)}
  end

  @impl true
  def handle_in("prompt", %{"prompt" => prompt} = payload, socket) do
    book_id = payload["book_id"]

    case API.start_run(prompt, book_id) do
      {:ok, run_id} ->
        {:reply, {:ok, %{run_id: run_id}}, assign(socket, :run_id, run_id)}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_info({:run_event, event}, socket) do
    push(socket, "run_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_event, event}, socket) do
    push(socket, "agent_event", event)
    {:noreply, socket}
  end
end