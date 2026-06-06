defmodule Slidething.Tool.RegistryTest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.ToolResult

  setup do
    {:ok, %{book_id: book_id}} = Slidething.Book.create("Test Book")
    {:ok, [page_id]} = Slidething.Book.create_pages(book_id, 1)
    %{book_id: book_id, page_id: page_id}
  end

  describe "create_book" do
    test "creates a book and returns success", %{book_id: _book_id} do
      result =
        Slidething.Tool.Registry.execute(:create_book, %{
          "title" => "My Story",
          "metadata" => %{"theme" => "adventure"}
        })

      assert %ToolResult{success: true, tool: :create_book} = result
      assert is_binary(result.data.book_id)
      assert result.data.title == "My Story"
      assert result.data.metadata["theme"] == "adventure"
    end

    test "handles missing metadata", %{book_id: _} do
      result = Slidething.Tool.Registry.execute(:create_book, %{"title" => "Minimal"})

      assert %ToolResult{success: true} = result
      assert result.data.title == "Minimal"
    end
  end

  describe "create_pages" do
    test "creates pages by list", %{book_id: book_id} do
      pages = [
        %{"position" => 1, "metadata" => %{"desc" => "Page 1"}},
        %{"position" => 2, "metadata" => %{"desc" => "Page 2"}}
      ]

      result =
        Slidething.Tool.Registry.execute(:create_pages, %{"book_id" => book_id, "pages" => pages})

      assert %ToolResult{success: true} = result
      assert result.data.count == 2
      assert length(result.data.page_ids) == 2
    end

    test "creates pages by count", %{book_id: book_id} do
      result =
        Slidething.Tool.Registry.execute(:create_pages, %{"book_id" => book_id, "count" => 3})

      assert %ToolResult{success: true} = result
      assert result.data.count == 3
    end
  end

  describe "get_book" do
    test "returns existing book", %{book_id: book_id} do
      result = Slidething.Tool.Registry.execute(:get_book, %{"book_id" => book_id})

      assert %ToolResult{success: true} = result
      assert result.data.title == "Test Book"
      assert is_list(result.data.pages)
    end

    test "fails for nonexistent book" do
      result = Slidething.Tool.Registry.execute(:get_book, %{"book_id" => "book_nonexistent"})

      assert %ToolResult{success: false} = result
      assert String.contains?(result.error, "not_found")
    end
  end

  describe "get_outline" do
    test "returns page outline", %{book_id: book_id, page_id: page_id} do
      result = Slidething.Tool.Registry.execute(:get_outline, %{"book_id" => book_id})

      assert %ToolResult{success: true} = result
      assert is_list(result.data.pages)
      assert length(result.data.pages) == 1
      assert Enum.at(result.data.pages, 0).id == page_id
    end
  end

  describe "create_element" do
    test "creates a title element", %{page_id: page_id} do
      result =
        Slidething.Tool.Registry.execute(:create_element, %{
          "page_id" => page_id,
          "element_type" => "title",
          "content" => "My Title"
        })

      assert %ToolResult{success: true} = result
      assert result.data.element_type == "title"
      assert result.data.content == "My Title"
      assert result.data.page_id == page_id
    end

    test "creates a text element", %{page_id: page_id} do
      result =
        Slidething.Tool.Registry.execute(:create_element, %{
          "page_id" => page_id,
          "element_type" => "text",
          "content" => "Once upon a time..."
        })

      assert %ToolResult{success: true} = result
      assert result.data.element_type == "text"
    end
  end

  describe "get_page_elements" do
    test "lists elements on a page", %{page_id: page_id} do
      Slidething.Tool.Registry.execute(:create_element, %{
        "page_id" => page_id,
        "element_type" => "title",
        "content" => "Title"
      })

      result = Slidething.Tool.Registry.execute(:get_page_elements, %{"page_id" => page_id})

      assert %ToolResult{success: true} = result
      assert length(result.data.elements) == 1
      assert Enum.at(result.data.elements, 0).element_type == "title"
    end

    test "empty page returns empty list", %{page_id: page_id} do
      result = Slidething.Tool.Registry.execute(:get_page_elements, %{"page_id" => page_id})

      assert %ToolResult{success: true} = result
      assert result.data.elements == []
    end
  end

  describe "update_element" do
    test "updates element content", %{page_id: page_id} do
      {:ok, elem} = Slidething.Element.create(page_id, "text", "Original")
      element_id = elem.element_id

      result =
        Slidething.Tool.Registry.execute(:update_element, %{
          "element_id" => element_id,
          "content" => "Updated"
        })

      assert %ToolResult{success: true} = result
      assert result.data.content == "Updated"
      assert result.data.version == 2
    end

    test "fails for nonexistent element" do
      result =
        Slidething.Tool.Registry.execute(:update_element, %{
          "element_id" => "elem_nonexistent",
          "content" => "Test"
        })

      assert %ToolResult{success: false} = result
      assert String.contains?(result.error, "not_found")
    end
  end

  describe "update_book_metadata" do
    test "updates book-level metadata", %{book_id: book_id} do
      result =
        Slidething.Tool.Registry.execute(:update_book_metadata, %{
          "book_id" => book_id,
          "metadata" => %{"theme" => "friendship"}
        })

      assert %ToolResult{success: true} = result
      assert result.data.updated == book_id
    end
  end

  describe "update_page_metadata" do
    test "updates page-level metadata", %{page_id: page_id} do
      result =
        Slidething.Tool.Registry.execute(:update_page_metadata, %{
          "page_id" => page_id,
          "metadata" => %{"status" => "complete"}
        })

      assert %ToolResult{success: true} = result
      assert result.data.updated == page_id
    end
  end

  describe "get_format" do
    test "returns print format" do
      result = Slidething.Tool.Registry.execute(:get_format, %{"format_id" => "format-print"})

      assert %ToolResult{success: true} = result
      assert result.data.name == "Children Book Square (Print)"
      assert result.data.width == 20.0
    end

    test "fails for nonexistent format" do
      result = Slidething.Tool.Registry.execute(:get_format, %{"format_id" => "nonexistent"})

      assert %ToolResult{success: false} = result
    end
  end

  describe "generate_image" do
    test "stores a mock image and returns its asset_path" do
      result =
        Slidething.Tool.Registry.execute(:generate_image, %{
          "prompt" => "A penguin flying"
        })

      assert %ToolResult{success: true} = result
      assert result.data.prompt == "A penguin flying"
      assert result.data.aspect_ratio == "1:1"
      assert is_binary(result.data.asset_path)
      assert String.ends_with?(result.data.asset_path, ".png")
      assert File.exists?(Slidething.AssetStore.full_path(result.data.asset_path))
    end

    test "respects custom aspect_ratio" do
      result =
        Slidething.Tool.Registry.execute(:generate_image, %{
          "prompt" => "Test",
          "aspect_ratio" => "16:9"
        })

      assert %ToolResult{success: true} = result
      assert result.data.aspect_ratio == "16:9"
    end
  end

  describe "store_asset" do
    test "attaches asset to element as a new version", %{page_id: page_id} do
      {:ok, elem} = Slidething.Element.create(page_id, "image", "a duck")

      result =
        Slidething.Tool.Registry.execute(:store_asset, %{
          "element_id" => elem.element_id,
          "asset_path" => "abc.png",
          "prompt" => "a duck swimming"
        })

      assert %ToolResult{success: true} = result
      assert result.data.version == 2

      {:ok, fetched} = Slidething.Element.get(elem.element_id)
      latest = List.last(fetched.versions)
      assert latest.asset_path == "abc.png"
    end
  end

  describe "propose_layout" do
    test "persists a layout version for the page", %{page_id: page_id} do
      {:ok, e1} = Slidething.Element.create(page_id, "title", "Hello")
      {:ok, e2} = Slidething.Element.create(page_id, "image", "duck prompt")

      result =
        Slidething.Tool.Registry.execute(:propose_layout, %{
          "page_id" => page_id,
          "format_id" => "format-web",
          "element_layouts" => [
            %{
              "element_id" => e1.element_id,
              "x" => 0.1,
              "y" => 0.1,
              "width" => 0.8,
              "height" => 0.1
            },
            %{
              "element_id" => e2.element_id,
              "x" => 0.1,
              "y" => 0.3,
              "width" => 0.8,
              "height" => 0.6
            }
          ]
        })

      assert %ToolResult{success: true} = result
      assert result.data.version == 1
      assert result.data.page_id == page_id

      {:ok, layout} = Slidething.Layout.get_latest(page_id, "format-web")
      assert length(layout.element_layouts) == 2
    end
  end

  describe "unknown tool" do
    test "returns failure for unrecognized tool" do
      result = Slidething.Tool.Registry.execute(:nonexistent_tool, %{})

      assert %ToolResult{success: false} = result
      assert String.contains?(result.error, "Unknown tool")
    end
  end

  describe "error handling" do
    test "rescues runtime errors and returns ToolResult with error" do
      result = Slidething.Tool.Registry.execute(:get_book, %{"book_id" => nil})

      assert %ToolResult{success: false} = result
      assert result.error != nil
    end
  end
end
