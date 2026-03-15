defmodule FrontierOS.GameState.PollerTest do
  @moduledoc """
  Covers the state poller specification for periodic assembly refreshes.
  """

  use ExUnit.Case, async: true

  alias FrontierOS.{Cache, GameState.Poller}

  setup do
    cache_pid = start_supervised!({Cache, tables: [:assemblies]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub}
  end

  test "polls assemblies periodically on configured interval", %{tables: tables, pubsub: pubsub} do
    parent = self()

    sync_fun = fn assembly_id, _opts ->
      send(parent, {:sync_called, assembly_id})
      {:ok, :synced}
    end

    _poller =
      start_poller!(
        assembly_ids: ["gate-1", "node-1"],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 30,
        sync_fun: sync_fun
      )

    counts =
      Enum.reduce(1..4, %{}, fn _, acc ->
        assert_receive {:sync_called, assembly_id}, 300
        Map.update(acc, assembly_id, 1, &(&1 + 1))
      end)

    assert counts["gate-1"] == 2
    assert counts["node-1"] == 2
  end

  test "calls sync_assembly for each assembly ID", %{tables: tables, pubsub: pubsub} do
    parent = self()

    sync_fun = fn assembly_id, opts ->
      send(
        parent,
        {:sync_called, assembly_id, Keyword.fetch!(opts, :tables), Keyword.fetch!(opts, :pubsub)}
      )

      {:ok, :synced}
    end

    poller =
      start_poller!(
        assembly_ids: ["assembly-a", "assembly-b", "assembly-c"],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 1_000,
        sync_fun: sync_fun
      )

    send(poller, :poll)

    assert_receive {:sync_called, "assembly-a", ^tables, ^pubsub}, 100
    assert_receive {:sync_called, "assembly-b", ^tables, ^pubsub}, 100
    assert_receive {:sync_called, "assembly-c", ^tables, ^pubsub}, 100
  end

  test "continues polling remaining assemblies after sync failure", %{
    tables: tables,
    pubsub: pubsub
  } do
    parent = self()

    sync_fun = fn
      "assembly-a", _opts ->
        send(parent, {:sync_failed, "assembly-a"})
        {:error, :timeout}

      "assembly-b", _opts ->
        send(parent, {:sync_called, "assembly-b"})
        {:ok, :synced}
    end

    poller =
      start_poller!(
        assembly_ids: ["assembly-a", "assembly-b"],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 20,
        sync_fun: sync_fun
      )

    send(poller, :poll)

    assert_receive {:sync_failed, "assembly-a"}, 100
    assert_receive {:sync_called, "assembly-b"}, 100
    assert_receive {:sync_failed, "assembly-a"}, 100
    assert Process.alive?(poller)
  end

  test "update_assembly_ids changes the polled assembly list", %{tables: tables, pubsub: pubsub} do
    parent = self()

    sync_fun = fn assembly_id, _opts ->
      send(parent, {:sync_called, assembly_id})
      {:ok, :synced}
    end

    poller =
      start_poller!(
        assembly_ids: ["old-assembly"],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 1_000,
        sync_fun: sync_fun
      )

    assert :ok = Poller.update_assembly_ids(poller, ["new-assembly"])
    send(poller, :poll)

    assert_receive {:sync_called, "new-assembly"}, 100
    refute_receive {:sync_called, "old-assembly"}, 50
  end

  test "handles empty assembly list gracefully", %{tables: tables, pubsub: pubsub} do
    parent = self()

    sync_fun = fn assembly_id, _opts ->
      send(parent, {:sync_called, assembly_id})
      {:ok, :synced}
    end

    poller =
      start_poller!(
        assembly_ids: [],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 20,
        sync_fun: sync_fun
      )

    refute_receive {:sync_called, _assembly_id}, 80
    assert Process.alive?(poller)
  end

  test "poller dies when linked caller terminates", %{tables: tables, pubsub: pubsub} do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, poller} =
          Poller.start_link(
            assembly_ids: ["assembly-a"],
            tables: tables,
            pubsub: pubsub,
            interval_ms: 1_000,
            sync_fun: fn _assembly_id, _opts -> {:ok, :synced} end
          )

        send(parent, {:poller_started, poller, self()})

        receive do
          :block -> :ok
        end
      end)

    assert_receive {:poller_started, poller, ^owner}, 100
    poller_ref = Process.monitor(poller)

    Process.exit(owner, :kill)

    assert_receive {:DOWN, ^poller_ref, :process, ^poller, _reason}, 100
  end

  test "stop/1 terminates the poller", %{tables: tables, pubsub: pubsub} do
    poller =
      start_poller!(
        assembly_ids: ["assembly-a"],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 1_000,
        sync_fun: fn _assembly_id, _opts -> {:ok, :synced} end
      )

    ref = Process.monitor(poller)
    assert :ok = Poller.stop(poller)
    assert_receive {:DOWN, ^ref, :process, ^poller, reason}, 100
    assert reason in [:normal, :shutdown, {:shutdown, :normal}]
  end

  test "poller is not a named process", %{tables: tables, pubsub: pubsub} do
    poller =
      start_poller!(
        assembly_ids: ["assembly-a"],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 1_000,
        sync_fun: fn _assembly_id, _opts -> {:ok, :synced} end
      )

    assert Process.info(poller, :registered_name) == {:registered_name, []}
  end

  test "child_spec generates unique id" do
    spec_one = Poller.child_spec([])
    spec_two = Poller.child_spec([])

    assert spec_one.start == {Poller, :start_link, [[]]}
    assert spec_two.start == {Poller, :start_link, [[]]}
    refute spec_one.id == spec_two.id
  end

  test "respects configured interval_ms", %{tables: tables, pubsub: pubsub} do
    parent = self()

    sync_fun = fn assembly_id, _opts ->
      send(parent, {:sync_called, assembly_id, System.monotonic_time(:millisecond)})
      {:ok, :synced}
    end

    _poller =
      start_poller!(
        assembly_ids: ["assembly-a"],
        tables: tables,
        pubsub: pubsub,
        interval_ms: 15,
        sync_fun: sync_fun
      )

    assert_receive {:sync_called, "assembly-a", first_at}, 80
    assert_receive {:sync_called, "assembly-a", second_at}, 80
    assert second_at - first_at <= 80
  end

  defp start_poller!(opts) do
    {:ok, poller} = Poller.start_link(opts)

    on_exit(fn ->
      if Process.alive?(poller) do
        try do
          GenServer.stop(poller, :normal, :infinity)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    poller
  end

  defp unique_pubsub_name do
    :"poller_pubsub_#{System.unique_integer([:positive])}"
  end
end
