defmodule Slidething.Tool.Registry do
  @moduledoc """
  Tool execution registry. Dispatches tool calls to real implementations.
  Replaces the hardcoded execute_tool/2 in agent GenServer.
  """

  require Logger

  alias Slidething.Agent.ToolResult

  @doc """
  Execute a tool by atom name. Returns %ToolResult{}.
  """
  def execute(tool, args) do
    try do
      result = do_execute(tool, args)
      %ToolResult{tool: tool, success: true, data: result}
    rescue
      e ->
        Logger.error("[Tool.Registry] #{tool} failed: #{inspect(e)}")
        %ToolResult{tool: tool, success: false, error: Exception.message(e)}
    end
  end

  # Planner tools
  defp do_execute(:create_book, %{"title" => title} = args) do
    metadata = args["metadata"] || %{}
    {:ok, data} = Slidething.Book.create(title, metadata)
    Slidething.Book.add_format(data.book_id, "format-web")
    data
  end

  defp do_execute(:create_pages, %{"book_id" => book_id, "pages" => pages}) do
    entries =
      Enum.map(pages, fn p ->
        pos = p["position"] || (is_list(pages) && Enum.find_index(pages, &(&1 == p)) + 1) || 1
        %{position: pos, metadata: p["metadata"] || %{}}
      end)

    {:ok, ids} = Slidething.Book.create_pages(book_id, entries)
    %{page_ids: ids, count: length(ids)}
  end

  defp do_execute(:create_pages, %{"book_id" => book_id, "count" => count}) do
    {:ok, ids} = Slidething.Book.create_pages(book_id, count)
    %{page_ids: ids, count: length(ids)}
  end

  defp do_execute(:get_book, %{"book_id" => book_id}) do
    case Slidething.Book.get(book_id) do
      {:ok, data} -> data
      {:error, reason} -> raise "Book not found: #{reason}"
    end
  end

  defp do_execute(:get_outline, %{"book_id" => book_id}) do
    {:ok, pages} = Slidething.Book.get_outline(book_id)
    %{pages: pages}
  end

  defp do_execute(:get_recent_prompts, %{"target_type" => target_type, "target_id" => target_id} = args) do
    limit = args["limit"] || 5
    prompts = Slidething.Prompt.list_recent(target_type, target_id, limit)
    %{prompts: prompts}
  end

  # Content tools
  defp do_execute(:get_page_elements, %{"page_id" => page_id}) do
    elements = Slidething.Element.list(page_id)
    %{elements: elements}
  end

  defp do_execute(:get_element, %{"element_id" => element_id}) do
    case Slidething.Element.get(element_id, history: 5) do
      {:ok, data} -> data
      {:error, reason} -> raise "Element not found: #{reason}"
    end
  end

  defp do_execute(:create_element, %{"page_id" => page_id, "element_type" => element_type, "content" => content} = args) do
    prompt = args["prompt"]
    {:ok, data} = Slidething.Element.create(page_id, element_type, content, prompt: prompt)
    data
  end

  defp do_execute(:update_element, %{"element_id" => element_id, "content" => content} = args) do
    prompt = args["prompt"]
    case Slidething.Element.update(element_id, content, prompt: prompt) do
      {:ok, data} -> data
      {:error, reason} -> raise "Update failed: #{reason}"
    end
  end

  defp do_execute(:delete_element, %{"element_id" => element_id}) do
    Slidething.Element.delete(element_id)
    %{deleted: element_id}
  end

  # Research tools
  defp do_execute(:update_book_metadata, %{"book_id" => book_id, "metadata" => metadata}) do
    Slidething.Book.update_metadata(book_id, metadata)
    %{updated: book_id}
  end

  defp do_execute(:update_page_metadata, %{"page_id" => page_id, "metadata" => metadata}) do
    Slidething.Book.update_page_metadata(page_id, metadata)
    %{updated: page_id}
  end

  # Media tools
  defp do_execute(:get_format, %{"format_id" => format_id}) do
    result =
      Slidething.Repo
      |> Ecto.Adapters.SQL.query!("SELECT id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm FROM formats WHERE id = ?", [format_id])

    case result.rows do
      [] -> raise "Format not found: #{format_id}"
      [[id, name, unit, width, height, dpi, bleed_mm, safe_margin_mm]] ->
        %{
          id: id, name: name, unit: unit, width: width, height: height,
          dpi: dpi, bleed_mm: bleed_mm, safe_margin_mm: safe_margin_mm
        }
    end
  end

  defp do_execute(:generate_image, %{"prompt" => prompt} = args) do
    aspect = args["aspect_ratio"] || "1:1"
    spec = Slidething.Agent.Config.agent_spec(:media)
    provider = (spec && spec.image_provider) || "mock"
    model = (spec && spec.image_model) || "mock-image-model"

    Logger.info("[Tool.Registry] generate_image provider=#{provider} model=#{model} aspect=#{aspect}: #{String.slice(prompt, 0, 80)}")

    case Slidething.Image.Client.generate(provider, model, prompt, aspect) do
      {:ok, asset_path} ->
        %{asset_path: asset_path, prompt: prompt, aspect_ratio: aspect}

      {:error, reason} ->
        raise "Image generation failed: #{inspect(reason)}"
    end
  end

  defp do_execute(:store_asset, %{"element_id" => element_id, "asset_path" => asset_path} = args) do
    prompt = args["prompt"]
    case Slidething.Element.update(element_id, nil, asset_path: asset_path, prompt: prompt) do
      {:ok, data} -> data
      {:error, reason} -> raise "Asset store failed: #{reason}"
    end
  end

  # Layout tools
  defp do_execute(:propose_layout, %{"page_id" => page_id, "format_id" => format_id, "element_layouts" => layouts} = args) do
    run_id = args["run_id"]
    {:ok, data} = Slidething.Layout.create(page_id, format_id, layouts, run_id: run_id)
    data
  end

  # Validation tool (callable by page_pipeline agents)
  defp do_execute(:validate_page, args) do
    page_id = args["page_id"] || args[:page_id]
    format_id = args["format_id"] || args[:format_id] || "format-web"

    if is_nil(page_id), do: raise("validate_page requires page_id")

    issues = Slidething.Validator.Layout.validate(page_id, format_id)

    issue_maps =
      Enum.map(issues, fn i ->
        %{
          severity: i.severity,
          rule: i.rule,
          target_id: i.target_id,
          message: i.message,
          measured_value: i.measured_value
        }
      end)

    %{issue_count: length(issue_maps), issues: issue_maps}
  end

  # Planner output tool
  defp do_execute(:submit_plan, %{"plan" => plan}) when is_map(plan) do
    plan
  end

  # Unknown tool
  defp do_execute(tool, _args) do
    Logger.warning("[Tool.Registry] Unknown tool: #{tool}")
    raise "Unknown tool: #{tool}"
  end
end