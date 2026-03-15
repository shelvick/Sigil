defmodule FrontierOSWeb.CacheResolver do
  @moduledoc """
  Resolves the ETS cache tables from the supervised `FrontierOS.Cache` process.

  Provides a single shared implementation used by both `WalletSession` (LiveView)
  and `SessionController` (Plug) to locate the application-level cache tables
  without duplicating the supervisor lookup logic.
  """

  alias FrontierOS.Cache

  @doc """
  Resolves the application-level ETS cache tables map.

  Locates `FrontierOS.Cache` within the supervised children of
  `FrontierOS.Supervisor` and returns its tables map.  Returns `nil` when
  the supervisor or cache process is not running.
  """
  @spec application_cache_tables() :: map() | nil
  def application_cache_tables do
    case Process.whereis(FrontierOS.Supervisor) do
      pid when is_pid(pid) ->
        pid
        |> Supervisor.which_children()
        |> Enum.find_value(fn
          {FrontierOS.Cache, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
            Cache.tables(cache_pid)

          _other ->
            nil
        end)

      nil ->
        nil
    end
  end
end
