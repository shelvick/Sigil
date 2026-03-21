defmodule Sigil.GameState.AssemblyMonitor do
  @moduledoc """
  Polls a single assembly, tracks changes, and broadcasts monitor updates.
  """

  use GenServer

  require Logger

  alias Sigil.Assemblies
  alias Sigil.GameState.FuelAnalytics
  alias Sigil.Sui.Client
  alias Sigil.Sui.Types.{Gate, NetworkNode, StorageUnit, Turret}

  @default_interval_ms 30_000
  @default_max_snapshots 60
  @default_pubsub Sigil.PubSub
  @not_found_limit 5

  @typedoc "Change emitted when an assembly field changes between polls."
  @type change() ::
          {:status_changed, atom(), atom()}
          | {:fuel_changed, non_neg_integer(), non_neg_integer()}
          | {:fuel_burning_changed, boolean(), boolean()}
          | {:extension_changed, String.t() | nil, String.t() | nil}

  @typedoc "PubSub payload broadcast by the monitor."
  @type monitor_payload() :: %{
          changes: [change()],
          assembly: Assemblies.assembly(),
          depletion: FuelAnalytics.depletion_result() | nil
        }

  @typedoc "Runtime state for a single assembly monitor."
  @type state() :: %{
          assembly_id: String.t(),
          tables: Assemblies.tables(),
          pubsub: atom() | module(),
          registry: atom(),
          interval_ms: pos_integer(),
          req_options: Client.request_opts(),
          sync_fun: function(),
          max_snapshots: non_neg_integer(),
          previous_assembly: Assemblies.assembly() | nil,
          fuel_snapshots: [FuelAnalytics.fuel_snapshot()],
          depletion: FuelAnalytics.depletion_result() | nil,
          consecutive_not_found: non_neg_integer()
        }

  @typedoc "Options accepted by the assembly monitor."
  @type option() ::
          {:assembly_id, String.t()}
          | {:tables, Assemblies.tables()}
          | {:pubsub, atom() | module()}
          | {:registry, atom()}
          | {:interval_ms, pos_integer()}
          | {:req_options, Client.request_opts()}
          | {:sync_fun, function()}
          | {:max_snapshots, non_neg_integer()}

  @type options() :: [option()]

  @doc """
  Returns a unique child spec so multiple monitors can run concurrently.
  """
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  @doc """
  Starts a linked monitor for one assembly id.
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Returns the current monitor state.
  """
  @spec get_state(pid()) :: state()
  def get_state(pid) when is_pid(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Stops a running monitor.
  """
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid)
  end

  @impl true
  @spec init(options()) :: {:ok, state()}
  def init(opts) do
    registry = Keyword.fetch!(opts, :registry)
    assembly_id = Keyword.fetch!(opts, :assembly_id)
    {:ok, _owner} = Registry.register(registry, assembly_id, nil)

    state = %{
      assembly_id: assembly_id,
      tables: Keyword.fetch!(opts, :tables),
      pubsub: Keyword.get(opts, :pubsub, @default_pubsub),
      registry: registry,
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      req_options: Keyword.get(opts, :req_options, []),
      sync_fun: Keyword.get(opts, :sync_fun, &Assemblies.sync_assembly/2),
      max_snapshots: Keyword.get(opts, :max_snapshots, @default_max_snapshots),
      previous_assembly: nil,
      fuel_snapshots: [],
      depletion: nil,
      consecutive_not_found: 0
    }

    schedule_poll(state.interval_ms)
    {:ok, state}
  end

  @impl true
  @spec handle_call(:get_state, GenServer.from(), state()) :: {:reply, state(), state()}
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  @spec handle_info(:poll, state()) :: {:noreply, state()} | {:stop, :normal, state()}
  def handle_info(:poll, state) do
    case sync_assembly(state) do
      {:ok, assembly} ->
        changes = detect_changes(state.previous_assembly, assembly)
        depletion = compute_depletion(assembly)

        fuel_snapshots =
          update_fuel_snapshots(state.fuel_snapshots, assembly, state.max_snapshots)

        payload = %{changes: changes, assembly: assembly, depletion: depletion}

        Phoenix.PubSub.broadcast(
          state.pubsub,
          assembly_topic(state.assembly_id),
          {:assembly_monitor, state.assembly_id, payload}
        )

        next_state = %{
          state
          | previous_assembly: assembly,
            depletion: depletion,
            fuel_snapshots: fuel_snapshots,
            consecutive_not_found: 0
        }

        schedule_poll(next_state.interval_ms)
        {:noreply, next_state}

      {:error, :not_found} ->
        next_state = %{state | consecutive_not_found: state.consecutive_not_found + 1}

        if next_state.consecutive_not_found >= @not_found_limit do
          {:stop, :normal, next_state}
        else
          schedule_poll(next_state.interval_ms)
          {:noreply, next_state}
        end

      {:error, reason} ->
        Logger.warning(
          "assembly monitor sync failed for #{state.assembly_id}: #{inspect(reason)}"
        )

        schedule_poll(state.interval_ms)
        {:noreply, state}
    end
  rescue
    error ->
      Logger.warning(
        "assembly monitor sync crashed for #{state.assembly_id}: #{Exception.message(error)}"
      )

      schedule_poll(state.interval_ms)
      {:noreply, state}
  end

  @spec sync_assembly(state()) :: {:ok, Assemblies.assembly()} | {:error, term()}
  defp sync_assembly(state) do
    state.sync_fun.(state.assembly_id, sync_opts(state))
  end

  @spec sync_opts(state()) :: keyword()
  defp sync_opts(state) do
    [tables: state.tables, pubsub: state.pubsub, req_options: state.req_options]
  end

  @spec compute_depletion(Assemblies.assembly()) :: FuelAnalytics.depletion_result() | nil
  defp compute_depletion(%NetworkNode{fuel: fuel}), do: FuelAnalytics.compute_depletion(fuel)
  defp compute_depletion(_assembly), do: nil

  @spec update_fuel_snapshots(
          [FuelAnalytics.fuel_snapshot()],
          Assemblies.assembly(),
          non_neg_integer()
        ) ::
          [FuelAnalytics.fuel_snapshot()]
  defp update_fuel_snapshots(fuel_snapshots, %NetworkNode{fuel: fuel}, max_snapshots) do
    FuelAnalytics.ring_buffer_push(
      fuel_snapshots,
      {System.os_time(:millisecond), fuel.quantity},
      max_snapshots
    )
  end

  defp update_fuel_snapshots(fuel_snapshots, _assembly, _max_snapshots), do: fuel_snapshots

  @spec detect_changes(Assemblies.assembly() | nil, Assemblies.assembly()) :: [change()]
  defp detect_changes(nil, _assembly), do: []

  defp detect_changes(previous_assembly, assembly) do
    []
    |> maybe_add_status_change(previous_assembly, assembly)
    |> maybe_add_extension_change(previous_assembly, assembly)
    |> maybe_add_fuel_change(previous_assembly, assembly)
    |> maybe_add_fuel_burning_change(previous_assembly, assembly)
  end

  @spec maybe_add_status_change([change()], Assemblies.assembly(), Assemblies.assembly()) :: [
          change()
        ]
  defp maybe_add_status_change(changes, previous_assembly, assembly) do
    previous_status = previous_assembly.status.status
    current_status = assembly.status.status

    if previous_status == current_status do
      changes
    else
      changes ++ [{:status_changed, previous_status, current_status}]
    end
  end

  @spec maybe_add_extension_change([change()], Assemblies.assembly(), Assemblies.assembly()) :: [
          change()
        ]
  defp maybe_add_extension_change(changes, %module{extension: previous}, %module{
         extension: current
       })
       when module in [Gate, StorageUnit, Turret] do
    if previous == current do
      changes
    else
      changes ++ [{:extension_changed, previous, current}]
    end
  end

  defp maybe_add_extension_change(changes, _previous_assembly, _assembly), do: changes

  @spec maybe_add_fuel_change([change()], Assemblies.assembly(), Assemblies.assembly()) :: [
          change()
        ]
  defp maybe_add_fuel_change(
         changes,
         %NetworkNode{fuel: %{quantity: previous_quantity}},
         %NetworkNode{fuel: %{quantity: current_quantity}}
       ) do
    if previous_quantity == current_quantity do
      changes
    else
      changes ++ [{:fuel_changed, previous_quantity, current_quantity}]
    end
  end

  defp maybe_add_fuel_change(changes, _previous_assembly, _assembly), do: changes

  @spec maybe_add_fuel_burning_change([change()], Assemblies.assembly(), Assemblies.assembly()) ::
          [change()]
  defp maybe_add_fuel_burning_change(
         changes,
         %NetworkNode{fuel: %{is_burning: previous_burning}},
         %NetworkNode{fuel: %{is_burning: current_burning}}
       ) do
    if previous_burning == current_burning do
      changes
    else
      changes ++ [{:fuel_burning_changed, previous_burning, current_burning}]
    end
  end

  defp maybe_add_fuel_burning_change(changes, _previous_assembly, _assembly), do: changes

  @spec schedule_poll(pos_integer()) :: reference()
  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: "assembly:#{assembly_id}"
end
