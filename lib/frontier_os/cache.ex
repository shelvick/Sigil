defmodule FrontierOS.Cache do
  @moduledoc """
  Process-owned ETS cache with explicit table access.
  """

  use GenServer

  @typedoc """
  ETS table identifier returned by `:ets.new/2`.
  """
  @type table_id() :: :ets.tid()

  @typedoc """
  State held by the cache process.
  """
  @type state() :: %{tables: %{atom() => table_id()}}

  @typedoc """
  Options accepted by `start_link/1`.
  """
  @type option() :: {:tables, [atom()]}

  @doc """
  Returns a child spec with a unique id so tests can start multiple cache instances.
  """
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Starts a cache process that owns one ETS table per requested name.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Returns the ETS tables owned by the cache process.
  """
  @spec tables(pid()) :: %{atom() => table_id()}
  def tables(cache_pid) do
    GenServer.call(cache_pid, :tables)
  end

  @doc """
  Stores a value under the given key in an ETS table.
  """
  @spec put(table_id(), term(), term()) :: :ok
  def put(table, key, value) do
    true = :ets.insert(table, {key, value})
    :ok
  end

  @doc """
  Fetches a value by key from an ETS table.
  """
  @spec get(table_id(), term()) :: term() | nil
  def get(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Deletes a value by key from an ETS table.
  """
  @spec delete(table_id(), term()) :: :ok
  def delete(table, key) do
    true = :ets.delete(table, key)
    :ok
  end

  @doc """
  Returns all values stored in an ETS table.
  """
  @spec all(table_id()) :: [term()]
  def all(table) do
    table
    |> :ets.tab2list()
    |> Enum.map(fn {_key, value} -> value end)
  end

  @doc """
  Returns all ETS entries matching the given pattern.
  """
  @spec match(table_id(), tuple()) :: [tuple()]
  def match(table, pattern) do
    :ets.match_object(table, pattern)
  end

  @impl true
  @spec init([option()]) :: {:ok, state()}
  def init(opts) do
    tables =
      opts
      |> Keyword.get(:tables, [])
      |> Enum.reduce(%{}, fn table_name, acc ->
        Map.put(acc, table_name, :ets.new(__MODULE__, [:set, :public, read_concurrency: true]))
      end)

    {:ok, %{tables: tables}}
  end

  @impl true
  @spec handle_call(:tables, GenServer.from(), state()) ::
          {:reply, %{atom() => table_id()}, state()}
  def handle_call(:tables, _from, state) do
    {:reply, state.tables, state}
  end
end
