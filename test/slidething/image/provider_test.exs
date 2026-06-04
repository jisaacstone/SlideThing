defmodule Slidething.Image.ProviderTest do
  use ExUnit.Case, async: true

  alias Slidething.Image.Provider

  describe "snap_aspect/1" do
    test "snaps near 1.0 to 1:1" do
      assert Provider.snap_aspect(1.0) == "1:1"
      assert Provider.snap_aspect(1.05) == "1:1"
      assert Provider.snap_aspect(0.95) == "1:1"
    end

    test "snaps wide ratios to 16:9 or 4:3" do
      assert Provider.snap_aspect(16 / 9) == "16:9"
      assert Provider.snap_aspect(4 / 3) == "4:3"
    end

    test "snaps tall ratios to 9:16 or 3:4" do
      assert Provider.snap_aspect(9 / 16) == "9:16"
      assert Provider.snap_aspect(3 / 4) == "3:4"
    end

    test "defaults to 1:1 for invalid input" do
      assert Provider.snap_aspect(nil) == "1:1"
      assert Provider.snap_aspect(-1.0) == "1:1"
      assert Provider.snap_aspect(0) == "1:1"
    end
  end
end
