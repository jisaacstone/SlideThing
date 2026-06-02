defmodule SlidethingWeb.UserSocket do
  use Phoenix.Socket

  channel "run:*", SlidethingWeb.RunChannel
  channel "book:*", SlidethingWeb.PageChannel

  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  def id(_socket), do: nil
end