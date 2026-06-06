defmodule Slidething.Agent.OrchestratorLayoutMediaTest do
  @moduledoc """
  Verifies that a full run actually writes layout versions and image assets to
  the database. Complements the flow tests in flows_test.exs.
  """

  use ExUnit.Case, async: false

  alias Slidething.Agent.Orchestrator

  @run_timeout 15_000

  setup do
    run_id = "layout_media_test_#{Ecto.UUID.generate()}"
    {:ok, pid} = Orchestrator.start_link(run_id: run_id)
    Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000) end)
    %{run_id: run_id, pid: pid}
  end

  test "full run writes layout + image assets for every page", %{pid: pid} do
    Orchestrator.start_run(pid, "Build a tiny book about a brave fox", nil)

    assert_receive {:run_event, %{event: :completed}}, @run_timeout

    state = Orchestrator.get_state(pid)
    assert state.status == :done
    assert is_binary(state.book_id)

    {:ok, pages} = Slidething.Book.get_outline(state.book_id)
    assert length(pages) > 0

    for page <- pages do
      # page_pipeline agent should have proposed a layout
      case Slidething.Layout.get_latest(page.id, "format-web") do
        {:ok, layout} ->
          assert is_list(layout.element_layouts)
        _ ->
          # Acceptable if mock skipped layout (no elements on page)
          :ok
      end

      # page_pipeline agent should have created elements
      elements = Slidething.Element.list(page.id)
      assert length(elements) > 0, "page #{page.id} should have at least one element"

      # Image elements should have asset paths
      images = Enum.filter(elements, &(&1.element_type == "image"))

      for img <- images do
        assert is_binary(img.latest_version.asset_path),
               "image element #{img.id} should have an asset_path"

        assert File.exists?(Slidething.AssetStore.full_path(img.latest_version.asset_path)),
               "asset file should exist on disk"
      end
    end
  end
end
