defmodule Slidething.ElementTest do
  use ExUnit.Case, async: false

  alias Slidething.Element

  setup do
    {:ok, %{book_id: book_id}} = Slidething.Book.create("Element Test Book")
    {:ok, [page_id]} = Slidething.Book.create_pages(book_id, 1)
    %{book_id: book_id, page_id: page_id}
  end

  describe "create/4" do
    test "creates a title element", %{page_id: page_id} do
      {:ok, elem} = Element.create(page_id, "title", "My Title")

      assert is_binary(elem.element_id)
      assert elem.element_type == "title"
      assert elem.content == "My Title"
      assert elem.page_id == page_id
    end

    test "creates an image element", %{page_id: page_id} do
      {:ok, elem} = Element.create(page_id, "image", "a prompt for drawing")

      assert elem.element_type == "image"
      assert elem.content == "a prompt for drawing"
    end

    test "creates element with optional prompt", %{page_id: page_id} do
      {:ok, elem} = Element.create(page_id, "text", "Some text", prompt: "make it big")

      assert elem.content == "Some text"
    end
  end

  describe "get/1" do
    test "returns element with content", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "Original")

      {:ok, elem} = Element.get(created.element_id)

      assert elem.id == created.element_id
      assert elem.element_type == "text"
      assert elem.content == "Original"
      refute Map.has_key?(elem, :versions)
      refute Map.has_key?(elem, :latest_version)
    end

    test "returns error for nonexistent element" do
      assert {:error, :not_found} = Element.get("elem_nonexistent")
    end
  end

  describe "update/3" do
    test "overwrites content", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "First draft")

      {:ok, updated} = Element.update(created.element_id, "Second draft")

      assert updated.element_id == created.element_id
      assert updated.content == "Second draft"

      {:ok, elem} = Element.get(created.element_id)
      assert elem.content == "Second draft"
    end

    test "returns error for nonexistent element" do
      assert {:error, :not_found} = Element.update("elem_nonexistent", "test")
    end
  end

  describe "list/1" do
    test "returns elements with content at top level", %{page_id: page_id} do
      {:ok, _} = Element.create(page_id, "title", "My Title")
      {:ok, _} = Element.create(page_id, "text", "Body text")

      elements = Element.list(page_id)

      assert length(elements) == 2

      title_el = Enum.find(elements, &(&1.element_type == "title"))
      assert title_el.content == "My Title"
      refute Map.has_key?(title_el, :latest_version)

      text_el = Enum.find(elements, &(&1.element_type == "text"))
      assert text_el.content == "Body text"
    end

    test "returns empty list for page with no elements", %{page_id: page_id} do
      elements = Element.list(page_id)
      assert elements == []
    end
  end

  describe "delete/1" do
    test "deletes element and its content", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "To be deleted")

      Element.delete(created.element_id)

      assert {:error, :not_found} = Element.get(created.element_id)
    end
  end
end
