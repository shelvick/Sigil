defmodule FrontierOS.ApplicationTest do
  @moduledoc """
  Captures the packet 3 supervision-tree contract for the application.
  """

  use ExUnit.Case, async: true

  alias FrontierOS.Cache
  alias FrontierOS.StaticDataTestFixtures, as: Fixtures

  test "application starts all required children" do
    snapshot = running_application_snapshot!()

    assert inspect(FrontierOSWeb.Telemetry) in snapshot.child_ids
    assert inspect(FrontierOS.Repo) in snapshot.child_ids
    assert inspect(Phoenix.PubSub.Supervisor) in snapshot.child_ids
    assert inspect(FrontierOS.Cache) in snapshot.child_ids
    assert inspect(FrontierOSWeb.Endpoint) in snapshot.child_ids
  end

  test "supervision tree includes Cache process" do
    snapshot = running_application_snapshot!()

    assert inspect(FrontierOS.Cache) in snapshot.child_ids
  end

  test "supervision tree includes StaticData when enabled" do
    snapshot = configured_application_snapshot!(start_static_data: true)

    assert snapshot.static_data_running
  end

  test "StaticData excluded from children when start_static_data is false" do
    snapshot = configured_application_snapshot!(start_static_data: false)

    assert inspect(FrontierOS.Cache) in snapshot.child_ids
    refute snapshot.static_data_running
    refute inspect(FrontierOS.StaticData) in snapshot.child_ids
  end

  test "Cache child precedes Endpoint in supervision tree" do
    snapshot = running_application_snapshot!()
    child_ids_in_start_order = Enum.reverse(snapshot.child_ids)

    assert index_of(child_ids_in_start_order, inspect(FrontierOS.Cache)) <
             index_of(child_ids_in_start_order, inspect(FrontierOSWeb.Endpoint))
  end

  test "application cache includes nonce table" do
    {_id, cache_pid, _kind, _modules} =
      Supervisor.which_children(FrontierOS.Supervisor)
      |> Enum.find(fn
        {FrontierOS.Cache, pid, _kind, _modules} -> is_pid(pid)
        _other -> false
      end)

    tables = Cache.tables(cache_pid)

    assert :nonces in Map.keys(tables)
  end

  defp configured_application_snapshot!(opts) do
    config_dir = temp_dir!("application_probe")
    static_data_dir = temp_dir!("application_probe_static_data")

    config_path =
      Fixtures.write_application_probe_config!(
        config_dir,
        opts
        |> Keyword.put(:static_data_dir, static_data_dir)
        |> Keyword.put(:world_client, FrontierOS.ApplicationTestWorldClient)
      )

    script = """
    {:ok, _apps} = Application.ensure_all_started(:frontier_os)

    snapshot = %{
      child_ids:
        FrontierOS.Supervisor
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _child_pid, _kind, _modules} -> inspect(id) end),
      static_data_running:
        FrontierOS.Supervisor
        |> Supervisor.which_children()
        |> Enum.any?(fn
          {FrontierOS.StaticData, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end)
    }

    IO.write(Jason.encode!(snapshot))
    Application.stop(:frontier_os)
    """

    {output, status} =
      System.cmd("mix", Fixtures.mix_run_args(config_path, script, no_start: true),
        cd: project_root(),
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status == 0, output

    decoded =
      output
      |> extract_json!()
      |> Jason.decode!()

    %{
      child_ids: decoded["child_ids"],
      static_data_running: decoded["static_data_running"]
    }
  end

  defp running_application_snapshot! do
    children = Supervisor.which_children(FrontierOS.Supervisor)

    %{
      child_ids: Enum.map(children, fn {id, _child_pid, _kind, _modules} -> inspect(id) end),
      static_data_running:
        Enum.any?(children, fn
          {FrontierOS.StaticData, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end)
    }
  end

  defp temp_dir!(prefix) do
    dir = Fixtures.ensure_tmp_dir!(prefix)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp project_root do
    Path.expand("../..", __DIR__)
  end

  defp extract_json!(output) do
    case Regex.run(~r/(\{.*\})/s, output, capture: :all_but_first) do
      [json] -> json
      _other -> raise ExUnit.AssertionError, message: output
    end
  end

  defp index_of(items, item), do: Enum.find_index(items, &(&1 == item))
end
