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
      assert elem.version == 1
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

  describe "get/2" do
    test "returns element with its versions", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "Original")

      {:ok, elem} = Element.get(created.element_id)

      assert elem.id == created.element_id
      assert elem.element_type == "text"
      assert length(elem.versions) == 1
      assert Enum.at(elem.versions, 0).content == "Original"
    end

    test "returns all versions when history option is used", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "Version 1")
      {:ok, _} = Element.update(created.element_id, "Version 2")
      {:ok, _} = Element.update(created.element_id, "Version 3")

      {:ok, elem} = Element.get(created.element_id, history: 5)

      assert length(elem.versions) == 3
      assert Enum.at(elem.versions, 0).content == "Version 1"
      assert Enum.at(elem.versions, 1).content == "Version 2"
      assert Enum.at(elem.versions, 2).content == "Version 3"
    end

    test "returns specific version", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "Original")
      {:ok, _} = Element.update(created.element_id, "Updated")

      {:ok, elem} = Element.get(created.element_id, version: 1)

      assert length(elem.versions) == 1
      assert Enum.at(elem.versions, 0).content == "Original"
    end

    test "returns error for nonexistent element" do
      assert {:error, :not_found} = Element.get("elem_nonexistent")
    end
  end

  describe "update/3" do
    test "creates a new version with updated content", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "First draft")

      {:ok, updated} = Element.update(created.element_id, "Second draft")

      assert updated.element_id == created.element_id
      assert updated.version == 2
      assert updated.content == "Second draft"

      {:ok, elem} = Element.get(created.element_id, history: 5)
      assert length(elem.versions) == 2
    end

    test "returns error for nonexistent element" do
      assert {:error, :not_found} = Element.update("elem_nonexistent", "test")
    end
  end

  describe "list/1" do
    test "returns elements with latest versions", %{page_id: page_id} do
      {:ok, _} = Element.create(page_id, "title", "My Title")
      {:ok, _} = Element.create(page_id, "text", "Body text")

      elements = Element.list(page_id)

      assert length(elements) == 2

      types = Enum.map(elements, & &1.element_type)
      assert "title" in types
      assert "text" in types
    end

    test "returns empty list for page with no elements", %{page_id: page_id} do
      elements = Element.list(page_id)
      assert elements == []
    end
  end

  describe "list_with_history/1" do
    test "includes version history", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "V1")
      {:ok, _} = Element.update(created.element_id, "V2")

      elements = Element.list_with_history(page_id)

      assert length(elements) == 1
      assert length(Enum.at(elements, 0).versions) == 2
    end
  end

  describe "delete/1" do
    test "deletes element and its versions", %{page_id: page_id} do
      {:ok, created} = Element.create(page_id, "text", "To be deleted")

      Element.delete(created.element_id)

      assert {:error, :not_found} = Element.get(created.element_id)
    end
  end
end
