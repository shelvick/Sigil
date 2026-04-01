defmodule Sigil.GameState.AssemblyEventRouter do
  @moduledoc """
  Routes assembly chain events from PubSub to the matching assembly monitor process.
  """

  use GenServer

  alias Sigil.GameState.AssemblyEventParser
  alias Sigil.Worlds

  @default_pubsub Sigil.PubSub
  @default_topic "chain_events"

  @typedoc "Runtime state for the assembly event router."
  @type state() :: %{
          pubsub: atom() | module(),
          world: Worlds.world_name(),
          topic: String.t(),
          registry: atom(),
          parser_module: module()
        }

  @typedoc "Start option accepted by the assembly event router."
  @type option() ::
          {:pubsub, atom() | module()}
          | {:world, Worlds.world_name()}
          | {:topic, String.t()}
          | {:registry, atom()}
          | {:parser_module, module()}

  @type options() :: [option()]

  @doc "Starts the assembly event router."
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Returns the singleton child spec used by the application supervisor."
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @impl true
  @spec init(options()) :: {:ok, state(), {:continue, :subscribe}}
  def init(opts) do
    world = Keyword.get(opts, :world, Worlds.default_world())

    {:ok,
     %{
       pubsub: Keyword.get(opts, :pubsub, @default_pubsub),
       world: world,
       topic: Keyword.get(opts, :topic, Worlds.topic(world, @default_topic)),
       registry: Keyword.fetch!(opts, :registry),
       parser_module: Keyword.get(opts, :parser_module, AssemblyEventParser)
     }, {:continue, :subscribe}}
  end

  @impl true
  @spec handle_continue(:subscribe, state()) :: {:noreply, state()}
  def handle_continue(:subscribe, state) do
    :ok = Phoenix.PubSub.subscribe(state.pubsub, state.topic)
    {:noreply, state}
  end

  @impl true
  @spec handle_info(term(), state()) :: {:noreply, state()}
  def handle_info({:chain_event, event_type, raw_data, checkpoint_seq}, state) do
    with true <- state.parser_module.assembly_event?(event_type),
         {:ok, assembly_id} <- state.parser_module.extract_assembly_id(event_type, raw_data),
         [{monitor, _value}] <- Registry.lookup(state.registry, assembly_id) do
      send(monitor, {:assembly_event, event_type, assembly_id, checkpoint_seq})
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
