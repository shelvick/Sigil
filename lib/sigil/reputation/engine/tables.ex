defmodule Sigil.Reputation.Engine.Tables do
  @moduledoc """
  Table resolution and sandbox wiring helpers for the reputation engine.
  """

  require Logger

  alias Ecto.Adapters.SQL.Sandbox
  alias Sigil.Cache
  alias Sigil.Worlds

  @doc "Resolves runtime tables from state when missing or stale."
  @spec maybe_resolve(map(), [atom()]) :: map()
  def maybe_resolve(%{tables: tables} = state, required_tables) when is_map(tables) do
    if valid_tables?(tables, required_tables) do
      state
    else
      resolve_tables(state, required_tables)
    end
  end

  def maybe_resolve(state, required_tables), do: resolve_tables(state, required_tables)

  @doc "Discovers cache table ids from the application supervisor."
  @spec default_resolve_tables() :: map() | nil
  def default_resolve_tables do
    default_resolve_tables(Worlds.default_world())
  end

  @doc "Discovers cache table ids for a specific world from the application supervisor."
  @spec default_resolve_tables(Worlds.world_name()) :: map() | nil
  def default_resolve_tables(world) when is_binary(world) do
    case Process.whereis(Sigil.Supervisor) do
      pid when is_pid(pid) ->
        children = Supervisor.which_children(pid)

        find_world_cache_tables(children, world) ||
          if(single_world_mode?(), do: find_single_world_cache_tables(children), else: nil)

      _other ->
        nil
    end
  end

  @doc "Allows this process to use a sandbox owner connection when provided."
  @spec maybe_allow_sandbox_owner(module(), pid() | nil) :: :ok
  def maybe_allow_sandbox_owner(_repo_module, nil), do: :ok

  def maybe_allow_sandbox_owner(repo_module, owner) when is_pid(owner) do
    if Code.ensure_loaded?(Sandbox) and function_exported?(Sandbox, :allow, 3) do
      Sandbox.allow(repo_module, owner, self())
    end

    :ok
  rescue
    exception ->
      Logger.warning("Sandbox allow failed: #{Exception.message(exception)}")
      :ok
  end

  @spec resolve_tables(map(), [atom()]) :: map()
  defp resolve_tables(state, required_tables) do
    case state.resolve_tables.() do
      tables when is_map(tables) ->
        if valid_tables?(tables, required_tables) do
          %{state | tables: tables}
        else
          %{state | tables: nil}
        end

      _other ->
        %{state | tables: nil}
    end
  end

  @spec find_world_cache_tables([Supervisor.child_spec()], Worlds.world_name()) :: map() | nil
  defp find_world_cache_tables(children, world) do
    Enum.find_value(children, fn
      {{Sigil.Cache, ^world}, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
        Cache.tables(cache_pid)

      _other ->
        nil
    end)
  end

  @spec find_single_world_cache_tables([Supervisor.child_spec()]) :: map() | nil
  defp find_single_world_cache_tables(children) do
    Enum.find_value(children, fn
      {Sigil.Cache, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
        Cache.tables(cache_pid)

      _other ->
        nil
    end)
  end

  @spec single_world_mode?() :: boolean()
  defp single_world_mode? do
    length(Worlds.active_worlds()) == 1
  end

  @spec valid_tables?(map(), [atom()]) :: boolean()
  defp valid_tables?(tables, required_tables) do
    Enum.all?(required_tables, fn key ->
      case Map.fetch(tables, key) do
        {:ok, tid} -> :ets.info(tid) != :undefined
        :error -> false
      end
    end)
  end
end
