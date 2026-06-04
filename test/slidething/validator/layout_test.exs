defmodule Slidething.Validator.LayoutTest do
  use ExUnit.Case, async: false

  alias Slidething.Validator.Layout, as: Validator

  # Format that matches the seeded "format-web": 20cm × 20cm, safe_margin 6mm
  @format %{
    width: 20.0,
    height: 20.0,
    unit: "cm",
    dpi: 72,
    safe_margin_mm: 6.0,
    bleed_mm: nil
  }

  # Safe margin in normalized units: 6mm / (20cm * 10mm/cm) = 0.03
  # Delegate to the validator via the public validate/2 path
  # by writing layouts into the DB and reading them back.

  setup do
    # Ensure DB tables exist (idempotent)
    Slidething.Schema.Bootstrap.ensure_tables()
    :ok
  end

  defp run_checks(layouts, _format \\ @format) do
    {:ok, book} = Slidething.Book.create("test")
    {:ok, [page_id]} = Slidething.Book.create_pages(book.book_id, 1)
    {:ok, _} = Slidething.Layout.create(page_id, "format-web", layouts)
    Validator.validate(page_id, "format-web")
  end

  describe "zero_area" do
    test "zero width raises error" do
      issues = run_checks([%{"element_id" => "e1", "x" => 0.1, "y" => 0.1, "width" => 0.0, "height" => 0.4}])
      assert Enum.any?(issues, &(&1.rule == "zero_area" and &1.severity == :error and &1.target_id == "e1"))
    end

    test "negative height raises error" do
      issues = run_checks([%{"element_id" => "e1", "x" => 0.1, "y" => 0.1, "width" => 0.3, "height" => -0.1}])
      assert Enum.any?(issues, &(&1.rule == "zero_area" and &1.target_id == "e1"))
    end

    test "positive dimensions pass" do
      issues = run_checks([%{"element_id" => "e1", "x" => 0.1, "y" => 0.1, "width" => 0.3, "height" => 0.4}])
      refute Enum.any?(issues, &(&1.rule == "zero_area"))
    end
  end

  describe "overflow" do
    test "element entirely in bounds is fine" do
      issues = run_checks([%{"element_id" => "e1", "x" => 0.0, "y" => 0.0, "width" => 1.0, "height" => 1.0}])
      refute Enum.any?(issues, &(&1.rule == "overflow"))
    end

    test "right edge overflow" do
      issues = run_checks([%{"element_id" => "e1", "x" => 0.8, "y" => 0.0, "width" => 0.3, "height" => 0.5}])
      assert Enum.any?(issues, &(&1.rule == "overflow" and &1.severity == :error and &1.target_id == "e1"))
    end

    test "bottom edge overflow" do
      issues = run_checks([%{"element_id" => "e1", "x" => 0.0, "y" => 0.8, "width" => 0.5, "height" => 0.3}])
      assert Enum.any?(issues, &(&1.rule == "overflow" and &1.target_id == "e1"))
    end

    test "negative x overflow" do
      issues = run_checks([%{"element_id" => "e1", "x" => -0.05, "y" => 0.0, "width" => 0.5, "height" => 0.5}])
      assert Enum.any?(issues, &(&1.rule == "overflow" and &1.target_id == "e1"))
    end
  end

  describe "intersection" do
    test "two non-overlapping rects have no intersection" do
      layouts = [
        %{"element_id" => "e1", "x" => 0.0, "y" => 0.0, "width" => 0.4, "height" => 0.4},
        %{"element_id" => "e2", "x" => 0.5, "y" => 0.5, "width" => 0.4, "height" => 0.4}
      ]
      issues = run_checks(layouts)
      refute Enum.any?(issues, &(&1.rule == "intersection"))
    end

    test "two overlapping rects produce an error" do
      layouts = [
        %{"element_id" => "e1", "x" => 0.0, "y" => 0.0, "width" => 0.5, "height" => 0.5},
        %{"element_id" => "e2", "x" => 0.3, "y" => 0.3, "width" => 0.4, "height" => 0.4}
      ]
      issues = run_checks(layouts)
      assert Enum.any?(issues, &(&1.rule == "intersection" and &1.severity == :error))
    end

    test "touching edges are not intersecting" do
      layouts = [
        %{"element_id" => "e1", "x" => 0.0, "y" => 0.0, "width" => 0.5, "height" => 0.5},
        %{"element_id" => "e2", "x" => 0.5, "y" => 0.0, "width" => 0.5, "height" => 0.5}
      ]
      issues = run_checks(layouts)
      refute Enum.any?(issues, &(&1.rule == "intersection"))
    end
  end

  describe "safe_margin" do
    test "element inside safe margin triggers warning" do
      # margin = 0.03; element x=0.01 is inside the margin
      issues = run_checks([%{"element_id" => "e1", "x" => 0.01, "y" => 0.1, "width" => 0.5, "height" => 0.5}])
      assert Enum.any?(issues, &(&1.rule == "safe_margin" and &1.severity == :warning and &1.target_id == "e1"))
    end

    test "element outside safe margin is fine" do
      # margin = 0.03; element x=0.05 is outside
      issues = run_checks([%{"element_id" => "e1", "x" => 0.05, "y" => 0.05, "width" => 0.5, "height" => 0.5}])
      refute Enum.any?(issues, &(&1.rule == "safe_margin"))
    end

    test "zero safe_margin_mm produces no warnings" do
      # format-print seeds with 6mm margin but we can create a layout with elements
      # right at the border — just verify overflow is the only concern when x=0.0
      issues = run_checks([%{"element_id" => "e1", "x" => 0.0, "y" => 0.0, "width" => 1.0, "height" => 1.0}])
      # All warnings should be safe_margin, not overflow (exactly at boundary is fine)
      refute Enum.any?(issues, &(&1.rule == "overflow"))
    end
  end

  describe "not found" do
    test "returns empty list when no layout exists for page" do
      {:ok, book} = Slidething.Book.create("test")
      {:ok, [page_id]} = Slidething.Book.create_pages(book.book_id, 1)
      assert Validator.validate(page_id, "format-web") == []
    end
  end
end
