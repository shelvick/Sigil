defmodule SigilWeb.CacheResolver do
  @moduledoc """
  Resolves supervised cache and monitor processes from `Sigil.Supervisor`.

  Shared by both Plug and LiveView code paths to avoid duplicating supervisor
  child-lookup logic.
  """

  alias Sigil.Cache
  alias Sigil.Worlds

  @doc """
  Resolves ETS cache tables for the default world.
  """
  @spec application_cache_tables() :: map() | nil
  def application_cache_tables do
    application_cache_tables(Worlds.default_world())
  end

  @doc """
  Resolves ETS cache tables for a specific world.

  Returns `nil` when the supervisor or world-scoped cache child is unavailable.
  """
  @spec application_cache_tables(Worlds.world_name()) :: map() | nil
  def application_cache_tables(world) when is_binary(world) do
    case supervisor_children() do
      nil ->
        nil

      children ->
        find_world_cache_tables(children, world) ||
          if(single_world_mode?(), do: find_any_cache_tables(children), else: nil)
    end
  end

  @doc """
  Resolves the monitor supervisor pid for the default world.
  """
  @spec application_monitor_supervisor() :: pid() | nil
  def application_monitor_supervisor do
    application_monitor_supervisor(Worlds.default_world())
  end

  @doc """
  Resolves the monitor supervisor pid for a specific world.
  """
  @spec application_monitor_supervisor(Worlds.world_name()) :: pid() | nil
  def application_monitor_supervisor(world) when is_binary(world) do
    case supervisor_children() do
      nil ->
        nil

      children ->
        find_world_monitor_supervisor(children, world) ||
          if(single_world_mode?(), do: find_any_monitor_supervisor(children), else: nil)
    end
  end

  @doc """
  Resolves the monitor registry name for a specific world.
  """
  @spec application_monitor_registry(Worlds.world_name()) :: atom() | nil
  def application_monitor_registry(world) when is_binary(world) do
    case supervisor_children() do
      nil ->
        nil

      children ->
        find_world_monitor_registry(children, world) ||
          if(single_world_mode?(), do: find_any_monitor_registry(children), else: nil)
    end
  end

  @doc """
  Resolves the application-level StaticData pid.
  """
  @spec application_static_data() :: pid() | nil
  def application_static_data do
    case supervisor_children() do
      nil ->
        nil

      children ->
        Enum.find_value(children, fn
          {Sigil.StaticData, static_data_pid, _kind, _modules} when is_pid(static_data_pid) ->
            static_data_pid

          _other ->
            nil
        end)
    end
  end

  @typep supervisor_child() ::
           {term(), :restarting | :undefined | pid(), :supervisor | :worker,
            :dynamic | [module()]}

  @spec find_world_cache_tables([supervisor_child()], Worlds.world_name()) :: map() | nil
  defp find_world_cache_tables(children, world) do
    Enum.find_value(children, fn
      {{Sigil.Cache, ^world}, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
        Cache.tables(cache_pid)

      _other ->
        nil
    end)
  end

  @spec find_any_cache_tables([supervisor_child()]) :: map() | nil
  defp find_any_cache_tables(children) do
    Enum.find_value(children, fn
      {Sigil.Cache, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
        Cache.tables(cache_pid)

      _other ->
        nil
    end)
  end

  @spec find_world_monitor_supervisor([supervisor_child()], Worlds.world_name()) :: pid() | nil
  defp find_world_monitor_supervisor(children, world) do
    Enum.find_value(children, fn
      {{Sigil.GameState.MonitorSupervisor, ^world}, monitor_pid, _kind, _modules}
      when is_pid(monitor_pid) ->
        monitor_pid

      _other ->
        nil
    end)
  end

  @spec find_any_monitor_supervisor([supervisor_child()]) :: pid() | nil
  defp find_any_monitor_supervisor(children) do
    Enum.find_value(children, fn
      {Sigil.GameState.MonitorSupervisor, monitor_pid, _kind, _modules}
      when is_pid(monitor_pid) ->
        monitor_pid

      _other ->
        nil
    end)
  end

  @spec find_world_monitor_registry([supervisor_child()], Worlds.world_name()) :: atom() | nil
  defp find_world_monitor_registry(children, world) do
    Enum.find_value(children, fn
      {{:monitor_registry, ^world, monitor_registry}, registry_pid, _kind, [Registry]}
      when is_atom(monitor_registry) and is_pid(registry_pid) ->
        monitor_registry

      _other ->
        nil
    end)
  end

  @spec find_any_monitor_registry([supervisor_child()]) :: atom() | nil
  defp find_any_monitor_registry(children) do
    Enum.find_value(children, fn
      {monitor_registry, registry_pid, _kind, [Registry]}
      when is_atom(monitor_registry) and is_pid(registry_pid) ->
        monitor_registry

      _other ->
        nil
    end)
  end

  @spec single_world_mode?() :: boolean()
  defp single_world_mode? do
    length(Worlds.active_worlds()) == 1
  end

  @spec supervisor_children() :: [supervisor_child()] | nil
  defp supervisor_children do
    case Process.whereis(Sigil.Supervisor) do
      pid when is_pid(pid) -> Supervisor.which_children(pid)
      nil -> nil
    end
  end
end
