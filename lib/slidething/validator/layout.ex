defmodule Slidething.Validator.Layout do
  alias Slidething.Agent.ValidationIssue
  alias Slidething.Layout

  @spec validate(String.t(), String.t()) :: [ValidationIssue.t()]
  def validate(page_id, format_id) do
    case Layout.get_with_format(page_id, format_id) do
      {:error, :not_found} ->
        []

      {:ok, %{element_layouts: layouts, format: format}} ->
        check_missing_layouts(layouts, page_id) ++
          check_zero_area(layouts) ++
          check_overflow(layouts) ++
          check_intersections(layouts) ++
          check_safe_margin(layouts, format) ++
          check_text_height(layouts, page_id)
    end
  end

  # ── Individual checks ───────────────────────────────────────────────────────

  defp check_missing_layouts(layouts, page_id) do
    laid_out = MapSet.new(layouts, & &1["element_id"])

    for el <- Slidething.Element.list(page_id),
        not MapSet.member?(laid_out, el.id) do
      %ValidationIssue{
        severity: :error,
        source: :layout,
        target_id: el.id,
        rule: "missing_layout",
        message: "Element has no layout entry and will not render",
        measured_value: %{element_type: el.element_type},
        expected_value: "every element must have a layout entry"
      }
    end
  end

  defp check_zero_area(layouts) do
    for el <- layouts,
        el["width"] <= 0 or el["height"] <= 0 do
      %ValidationIssue{
        severity: :error,
        source: :layout,
        target_id: el["element_id"],
        rule: "zero_area",
        message: "Element has zero or negative dimensions",
        measured_value: %{width: el["width"], height: el["height"]},
        expected_value: "width > 0 and height > 0"
      }
    end
  end

  defp check_overflow(layouts) do
    for el <- layouts,
        el["width"] > 0 and el["height"] > 0,
        el["x"] < 0 or el["y"] < 0 or
          el["x"] + el["width"] > 1.0 or
          el["y"] + el["height"] > 1.0 do
      %ValidationIssue{
        severity: :error,
        source: :layout,
        target_id: el["element_id"],
        rule: "overflow",
        message: "Element extends outside page bounds",
        measured_value: %{x: el["x"], y: el["y"], width: el["width"], height: el["height"]},
        expected_value: "x >= 0, y >= 0, x+width <= 1, y+height <= 1"
      }
    end
  end

  defp check_intersections(layouts) do
    valid = Enum.filter(layouts, &(&1["width"] > 0 and &1["height"] > 0))

    for {a, i} <- Enum.with_index(valid),
        {b, j} <- Enum.with_index(valid),
        j > i,
        overlaps?(a, b) do
      %ValidationIssue{
        severity: :error,
        source: :layout,
        target_id: "#{a["element_id"]}:#{b["element_id"]}",
        rule: "intersection",
        message: "Elements overlap",
        measured_value: %{
          a: %{x: a["x"], y: a["y"], width: a["width"], height: a["height"]},
          b: %{x: b["x"], y: b["y"], width: b["width"], height: b["height"]}
        },
        expected_value: "no overlap between elements"
      }
    end
  end

  defp check_safe_margin(_layouts, %{safe_margin_mm: nil}), do: []

  defp check_safe_margin(_layouts, %{safe_margin_mm: m}) when m <= 0, do: []

  defp check_safe_margin(layouts, format) do
    mm = mm_per_unit(format)
    mx = format.safe_margin_mm / (format.width * mm)
    my = format.safe_margin_mm / (format.height * mm)

    for el <- layouts,
        el["width"] > 0 and el["height"] > 0,
        el["x"] < mx or el["y"] < my or
          el["x"] + el["width"] > 1.0 - mx or
          el["y"] + el["height"] > 1.0 - my do
      %ValidationIssue{
        severity: :warning,
        source: :layout,
        target_id: el["element_id"],
        rule: "safe_margin",
        message: "Element encroaches on safe margin zone",
        measured_value: %{x: el["x"], y: el["y"], width: el["width"], height: el["height"]},
        expected_value: %{margin_x: mx, margin_y: my}
      }
    end
  end

  defp check_text_height(layouts, page_id) do
    elements = Slidething.Element.list(page_id)

    for layout <- layouts,
        el = Enum.find(elements, &(&1.id == layout["element_id"])),
        el != nil,
        el.element_type in ["text", "title", "caption"],
        content = el.content || "",
        String.length(content) > 150,
        layout["height"] < 0.4 do
      %ValidationIssue{
        severity: :warning,
        source: :layout,
        target_id: layout["element_id"],
        rule: "text_height",
        message:
          "Text (#{String.length(content)} chars) likely overflows height=#{layout["height"]}; suggest >= 0.4",
        measured_value: %{height: layout["height"], chars: String.length(content)},
        expected_value: "height >= 0.4 for content > 150 chars"
      }
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp overlaps?(a, b) do
    not (a["x"] + a["width"] <= b["x"] or
           b["x"] + b["width"] <= a["x"] or
           a["y"] + a["height"] <= b["y"] or
           b["y"] + b["height"] <= a["y"])
  end

  defp mm_per_unit(%{unit: "cm"}), do: 10.0
  defp mm_per_unit(%{unit: "in"}), do: 25.4
  defp mm_per_unit(%{unit: "mm"}), do: 1.0
  defp mm_per_unit(%{unit: "px", dpi: dpi}), do: 25.4 / dpi
  defp mm_per_unit(_), do: 10.0
end
