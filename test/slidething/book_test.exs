defmodule Slidething.BookTest do
  use ExUnit.Case, async: false

  alias Slidething.Book

  setup do
    {:ok, %{book_id: book_id}} = Book.create("Test Book", %{"theme" => "adventure"})
    %{book_id: book_id}
  end

  describe "create/2" do
    test "creates book with ID prefix" do
      {:ok, book} = Book.create("My Story")
      assert is_binary(book.book_id)
      assert String.starts_with?(book.book_id, "book_")
      assert book.title == "My Story"
      assert book.metadata == %{}
    end

    test "stores metadata" do
      {:ok, book} = Book.create("Themed", %{"style" => "whimsical", "audience" => "ages 4-8"})
      assert book.metadata["style"] == "whimsical"
      assert book.metadata["audience"] == "ages 4-8"
    end
  end

  describe "create_pages/2" do
    test "creates pages by count", %{book_id: book_id} do
      {:ok, ids} = Book.create_pages(book_id, 5)
      assert length(ids) == 5

      {:ok, book} = Book.get(book_id)
      assert length(book.pages) == 5
    end

    test "creates pages by list with positions and metadata", %{book_id: book_id} do
      entries = [
        %{position: 3, metadata: %{"desc" => "Third"}},
        %{position: 1, metadata: %{"desc" => "First"}}
      ]

      {:ok, ids} = Book.create_pages(book_id, entries)
      assert length(ids) == 2

      {:ok, book} = Book.get(book_id)
      assert length(book.pages) == 2
      assert Enum.at(book.pages, 0).position == 1
      assert Enum.at(book.pages, 1).position == 3
    end
  end

  describe "get/1" do
    test "returns book with pages", %{book_id: book_id} do
      {:ok, [page_id]} = Book.create_pages(book_id, 1)

      {:ok, book} = Book.get(book_id)

      assert book.title == "Test Book"
      assert book.metadata["theme"] == "adventure"
      assert length(book.pages) == 1
      assert Enum.at(book.pages, 0).id == page_id
    end

    test "returns error for nonexistent book" do
      assert {:error, :not_found} = Book.get("book_nonexistent")
    end
  end

  describe "get_outline/1" do
    test "returns page IDs and positions", %{book_id: book_id} do
      {:ok, _ids} = Book.create_pages(book_id, 3)

      {:ok, pages} = Book.get_outline(book_id)

      assert length(pages) == 3
      assert Enum.at(pages, 0).position == 1
      assert String.starts_with?(Enum.at(pages, 0).id, "page_")
    end
  end

  describe "get_page/1" do
    test "returns a single page", %{book_id: book_id} do
      {:ok, [page_id]} = Book.create_pages(book_id, 1)

      {:ok, page} = Book.get_page(page_id)

      assert page.id == page_id
      assert page.book_id == book_id
      assert page.position == 1
    end

    test "returns error for nonexistent page" do
      assert {:error, :not_found} = Book.get_page("page_nonexistent")
    end
  end

  describe "update_metadata/2" do
    test "updates book metadata", %{book_id: book_id} do
      Book.update_metadata(book_id, %{"mood" => "happy"})

      {:ok, book} = Book.get(book_id)
      assert book.metadata["mood"] == "happy"
      refute book.metadata["theme"], "update_metadata replaces, does not merge"
    end
  end

  describe "update_page_metadata/2" do
    test "updates page metadata", %{book_id: book_id} do
      {:ok, [page_id]} = Book.create_pages(book_id, 1)

      Book.update_page_metadata(page_id, %{"status" => "reviewed"})

      {:ok, page} = Book.get_page(page_id)
      assert page.metadata["status"] == "reviewed"
    end
  end

  describe "formats" do
    test "links and retrieves formats", %{book_id: book_id} do
      Book.add_format(book_id, "format-web")
      Book.add_format(book_id, "format-print")

      formats = Book.get_formats(book_id)
      assert length(formats) == 2
      assert Enum.map(formats, & &1.id) |> Enum.sort() == ["format-print", "format-web"]
    end

    test "no duplicate format links", %{book_id: book_id} do
      Book.add_format(book_id, "format-web")
      Book.add_format(book_id, "format-web")

      formats = Book.get_formats(book_id)
      assert length(formats) == 1
    end
  end
end