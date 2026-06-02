defmodule SlidethingWeb.PageChannel do
  use SlidethingWeb, :channel

  alias Slidething.Book
  alias Slidething.Element
  alias Slidething.Layout

  @impl true
  def join("book:" <> book_id, _payload, socket) do
    Phoenix.PubSub.subscribe(Slidething.PubSub, "book_events:#{book_id}")

    {:ok, assign(socket, :book_id, book_id)}
  end

  @impl true
  def handle_in("get_book", _payload, socket) do
    book_id = socket.assigns.book_id

    case Book.get(book_id) do
      {:ok, book} ->
        {:reply, {:ok, book}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("get_page", %{"page_id" => page_id}, socket) do
    case Book.get_page(page_id) do
      {:ok, page} ->
        elements = Element.list(page_id)

        {:ok, layouts} = Layout.get_all(page_id)

        {:reply, {:ok, Map.put(page, :elements, elements) |> Map.put(:layouts, layouts)}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("get_pages", _payload, socket) do
    book_id = socket.assigns.book_id

    {:ok, pages} = Book.get_outline(book_id)

    full_pages =
      Enum.map(pages, fn page ->
        elements = Element.list(page.id)
        {:ok, layouts} = Layout.get_all(page.id)

        Map.put(page, :elements, elements) |> Map.put(:layouts, layouts)
      end)

    {:reply, {:ok, full_pages}, socket}
  end

  @impl true
  def handle_in("get_element", %{"element_id" => element_id}, socket) do
    case Element.get(element_id) do
      {:ok, element} ->
        {:reply, {:ok, element}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("get_layout", %{"page_id" => page_id, "format_id" => format_id}, socket) do
    case Layout.get(page_id, format_id) do
      {:ok, layout} ->
        {:reply, {:ok, layout}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_info({:page_event, event}, socket) do
    push(socket, "page_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:book_event, event}, socket) do
    push(socket, "book_event", event)
    {:noreply, socket}
  end
end