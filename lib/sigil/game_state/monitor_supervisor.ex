defmodule Sigil.GameState.MonitorSupervisor do
  @moduledoc """
  DynamicSupervisor for per-assembly monitors.
  """

  use DynamicSupervisor

  require Logger

  alias Sigil.GameState.AssemblyMonitor
  alias Sigil.Worlds

  @default_pubsub Sigil.PubSub
  @monitor_lifecycle_topic "monitors:lifecycle"

  @typedoc "Options accepted by the monitor supervisor."
  @type option() ::
          {:registry, atom()}
          | {:pubsub, atom() | module()}
          | {:world, Worlds.world_name()}

  @type options() :: [option()]

  @doc """
  Starts the monitor supervisor.
  """
  @spec start_link(options()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts)
  end

  @doc """
  Starts one assembly monitor under the supervisor.
  """
  @spec start_monitor(pid(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_monitor(supervisor, opts) when is_pid(supervisor) and is_list(opts) do
    case DynamicSupervisor.start_child(supervisor, {AssemblyMonitor, opts}) do
      {:ok, _monitor} = result ->
        maybe_broadcast_monitor_started(opts)
        result

      other ->
        other
    end
  end

  @doc """
  Stops a monitored assembly process.
  """
  @spec stop_monitor(pid(), String.t(), atom()) :: :ok | {:error, :not_found}
  def stop_monitor(supervisor, assembly_id, registry)
      when is_pid(supervisor) and is_binary(assembly_id) and is_atom(registry) do
    case get_monitor(registry, assembly_id) do
      {:ok, monitor} ->
        :ok = DynamicSupervisor.terminate_child(supervisor, monitor)
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Ensures monitors exist for the provided assembly ids.
  """
  @spec ensure_monitors(pid(), [String.t()], keyword()) :: :ok
  def ensure_monitors(supervisor, assembly_ids, opts)
      when is_pid(supervisor) and is_list(assembly_ids) and is_list(opts) do
    registry = Keyword.fetch!(opts, :registry)

    Enum.each(assembly_ids, fn assembly_id ->
      case get_monitor(registry, assembly_id) do
        {:ok, _monitor} ->
          :ok

        {:error, :not_found} ->
          monitor_opts = Keyword.put(opts, :assembly_id, assembly_id)

          case start_monitor(supervisor, monitor_opts) do
            {:ok, _monitor} ->
              :ok

            {:error, {:already_started, _monitor}} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "failed to start assembly monitor for #{assembly_id}: #{inspect(reason)}"
              )
          end
      end
    end)

    :ok
  end

  @doc """
  Looks up a monitor pid by assembly id.
  """
  @spec get_monitor(atom(), String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_monitor(registry, assembly_id) when is_atom(registry) and is_binary(assembly_id) do
    case Registry.lookup(registry, assembly_id) do
      [{monitor, _value}] -> {:ok, monitor}
      [] -> {:error, :not_found}
    end
  end

  @spec maybe_broadcast_monitor_started(keyword()) :: :ok
  defp maybe_broadcast_monitor_started(opts) do
    with assembly_id when is_binary(assembly_id) <- Keyword.get(opts, :assembly_id) do
      pubsub = Keyword.get(opts, :pubsub, @default_pubsub)
      world = Keyword.get(opts, :world, Worlds.default_world())

      Phoenix.PubSub.broadcast(
        pubsub,
        Worlds.topic(world, @monitor_lifecycle_topic),
        {:monitor_started, assembly_id}
      )
    end

    :ok
  end

  @doc """
  Lists registered monitors.
  """
  @spec list_monitors(atom()) :: [{String.t(), pid()}]
  def list_monitors(registry) when is_atom(registry) do
    Registry.select(registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @impl true
  @spec init(options()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(opts) do
    _registry = Keyword.fetch!(opts, :registry)
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
