defmodule Slidething.LayoutTest do
  use ExUnit.Case, async: false

  alias Slidething.Layout

  setup do
    {:ok, %{book_id: book_id}} = Slidething.Book.create("Layout Test Book")
    {:ok, [page_id]} = Slidething.Book.create_pages(book_id, 1)
    %{book_id: book_id, page_id: page_id}
  end

  describe "create/4 + get_latest/2" do
    test "stores element_layouts and round-trips them", %{page_id: page_id} do
      layouts = [
        %{"element_id" => "elem_a", "x" => 0.0, "y" => 0.0, "width" => 1.0, "height" => 0.3},
        %{"element_id" => "elem_b", "x" => 0.0, "y" => 0.3, "width" => 1.0, "height" => 0.7}
      ]

      {:ok, %{version: 1}} = Layout.create(page_id, "format-web", layouts)

      {:ok, latest} = Layout.get_latest(page_id, "format-web")
      assert latest.version == 1
      assert length(latest.element_layouts) == 2
      assert Enum.at(latest.element_layouts, 0)["element_id"] == "elem_a"
    end

    test "bumps version on subsequent writes", %{page_id: page_id} do
      {:ok, %{version: 1}} = Layout.create(page_id, "format-web", [])
      {:ok, %{version: 2}} = Layout.create(page_id, "format-web", [])
      {:ok, latest} = Layout.get_latest(page_id, "format-web")
      assert latest.version == 2
    end

    test "returns :not_found when no layout exists", %{page_id: page_id} do
      assert {:error, :not_found} = Layout.get_latest(page_id, "format-web")
    end
  end
end
