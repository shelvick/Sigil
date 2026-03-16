defmodule Sigil.CacheTest do
  @moduledoc """
  Covers the packet 1 ETS cache contract from the approved spec.
  """

  use ExUnit.Case, async: true

  alias Sigil.Cache

  describe "direct ETS operations" do
    test "put/3 stores a value retrievable by get/2" do
      tid = cache_table!(:entries)

      assert :ok = Cache.put(tid, :assembly_1, %{status: :online})
      assert %{status: :online} = Cache.get(tid, :assembly_1)
    end

    test "get/2 returns nil for missing key" do
      tid = cache_table!(:entries)

      assert Cache.get(tid, :missing) == nil
    end

    test "delete/2 removes entry from cache" do
      tid = cache_table!(:entries)

      assert :ok = Cache.put(tid, :character_1, %{name: "Nova"})
      assert :ok = Cache.delete(tid, :character_1)
      assert Cache.get(tid, :character_1) == nil
    end

    test "take/2 returns and removes the stored entry" do
      tid = cache_table!(:entries)

      assert :ok = Cache.put(tid, :nonce_1, %{address: "0xabc"})
      assert %{address: "0xabc"} = Cache.take(tid, :nonce_1)
      assert Cache.get(tid, :nonce_1) == nil
      assert Cache.take(tid, :missing_nonce) == nil
    end

    test "put/3 overwrites existing value" do
      tid = cache_table!(:entries)

      assert :ok = Cache.put(tid, :account_1, %{balance: 10})
      assert :ok = Cache.put(tid, :account_1, %{balance: 25})
      assert %{balance: 25} = Cache.get(tid, :account_1)
    end

    test "all/1 returns all stored values" do
      tid = cache_table!(:entries)

      assert :ok = Cache.put(tid, :tribe_1, "Aurora")
      assert :ok = Cache.put(tid, :tribe_2, "Helios")

      assert Cache.all(tid) |> Enum.sort() == ["Aurora", "Helios"]
    end

    test "all/1 returns empty list for empty table" do
      tid = cache_table!(:entries)

      assert Cache.all(tid) == []
    end

    test "match/2 returns entries matching pattern" do
      tid = cache_table!(:entries)

      assert :ok = Cache.put(tid, :alpha, :tribe)
      assert :ok = Cache.put(tid, :beta, :tribe)
      assert :ok = Cache.put(tid, :gamma, :assembly)

      assert Cache.match(tid, {:"$1", :tribe}) |> Enum.sort() == [alpha: :tribe, beta: :tribe]
    end
  end

  describe "GenServer lifecycle" do
    test "start_link/1 creates named tables accessible via tables/1" do
      pid = start_cache!([:assemblies, :characters])
      tables = Cache.tables(pid)

      assert Map.keys(tables) |> Enum.sort() == [:assemblies, :characters]

      assert Enum.all?(tables, fn
               {:assemblies, tid} ->
                 :set == :ets.info(tid, :type) and :public == :ets.info(tid, :protection) and
                   true == :ets.info(tid, :read_concurrency)

               {:characters, tid} ->
                 :set == :ets.info(tid, :type) and :public == :ets.info(tid, :protection) and
                   true == :ets.info(tid, :read_concurrency)
             end)
    end

    test "separate Cache instances have isolated tables" do
      left_pid = start_cache!([:assemblies])
      right_pid = start_cache!([:assemblies])
      left_tid = Map.fetch!(Cache.tables(left_pid), :assemblies)
      right_tid = Map.fetch!(Cache.tables(right_pid), :assemblies)

      assert :ok = Cache.put(left_tid, :assembly_1, %{pilot: "left"})

      assert %{pilot: "left"} = Cache.get(left_tid, :assembly_1)
      assert Cache.get(right_tid, :assembly_1) == nil
    end

    test "ETS tables are destroyed when GenServer stops" do
      pid = start_cache!([:assemblies])
      tid = Map.fetch!(Cache.tables(pid), :assemblies)
      monitor_ref = Process.monitor(pid)

      assert :ok = GenServer.stop(pid, :normal, :infinity)

      assert_receive {:DOWN, ^monitor_ref, :process, ^pid, reason}
      assert clean_shutdown?(reason)

      assert_raise ArgumentError, fn ->
        Cache.get(tid, :assembly_1)
      end
    end

    test "start_link/1 with empty tables list returns empty map" do
      pid = start_cache!([])

      assert Cache.tables(pid) == %{}
    end
  end

  defp cache_table!(table_name) do
    table_name
    |> List.wrap()
    |> start_cache!()
    |> Cache.tables()
    |> Map.fetch!(table_name)
  end

  defp start_cache!(table_names) do
    start_supervised!({Cache, tables: table_names})
  end

  defp clean_shutdown?(:normal), do: true
  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _reason}), do: true
  defp clean_shutdown?(:noproc), do: true
  defp clean_shutdown?(_reason), do: false
end
