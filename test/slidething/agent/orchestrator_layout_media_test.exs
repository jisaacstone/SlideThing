defmodule Slidething.Agent.OrchestratorLayoutMediaTest do
  use ExUnit.Case, async: false

  alias Slidething.Agent.Orchestrator

  setup do
    run_id = "test_run_#{:rand.uniform(100_000)}"
    {:ok, orchestrator_pid} = Orchestrator.start_link(run_id: run_id)
    %{run_id: run_id, orchestrator_pid: orchestrator_pid}
  end

  test "runs planner → content → layout → media → done and writes layout + asset", %{
    orchestrator_pid: orchestrator_pid,
    run_id: run_id
  } do
    Phoenix.PubSub.subscribe(Slidething.PubSub, "events:#{run_id}")

    Orchestrator.start_run(orchestrator_pid, "Build a tiny book", nil)

    assert_receive {:run_event, %{event: :phase_started, data: %{phase: :layout}}}, 5000
    assert_receive {:run_event, %{event: :phase_completed, data: %{phase: :layout}}}, 5000
    assert_receive {:run_event, %{event: :phase_started, data: %{phase: :media}}}, 5000
    assert_receive {:run_event, %{event: :completed}}, 10_000

    state = Orchestrator.get_state(orchestrator_pid)
    assert state.status == :done
    assert is_binary(state.book_id)

    {:ok, pages} = Slidething.Book.get_outline(state.book_id)
    assert length(pages) > 0

    for page <- pages do
      assert {:ok, layout} = Slidething.Layout.get_latest(page.id, "format-web")
      assert length(layout.element_layouts) > 0

      images =
        page.id
        |> Slidething.Element.list()
        |> Enum.filter(&(&1.element_type == "image"))

      assert length(images) > 0

      for img <- images do
        assert is_binary(img.latest_version.asset_path)

        assert File.exists?(
                 Slidething.AssetStore.full_path(img.latest_version.asset_path)
               )
      end
    end
  end
end
