defmodule SlidethingWeb.RunChannel do
  use SlidethingWeb, :channel

  alias Slidething.Agent.API

  @impl true
  def join("run:" <> run_id, _payload, socket) do
    Phoenix.PubSub.subscribe(Slidething.PubSub, "run_events:#{run_id}")
    Phoenix.PubSub.subscribe(Slidething.PubSub, "agent_events:#{run_id}")

    {:ok, assign(socket, :run_id, run_id)}
  end

  @impl true
  def handle_in("prompt", %{"prompt" => prompt}, socket) do
    book_id = Map.get(socket.assigns, :book_id)

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