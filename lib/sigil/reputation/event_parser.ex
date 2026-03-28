defmodule Sigil.Reputation.EventParser do
  @moduledoc """
  Parses raw chain events into normalized reputation event structs.
  """

  alias Sigil.Accounts.Account
  alias Sigil.Cache
  alias Sigil.Reputation.Events.{AggressorEvent, JumpEvent, KillmailEvent}
  alias Sigil.Sui.Types.{Character, Gate, Turret}

  @typedoc "ETS tables required for tribe resolution."
  @type tables() :: %{
          characters: Cache.table_id(),
          assemblies: Cache.table_id(),
          gate_network: Cache.table_id(),
          accounts: Cache.table_id()
        }

  @typedoc "Options accepted by the parser."
  @type parse_opt() ::
          {:tables, tables()}
          | {:checkpoint_seq, non_neg_integer()}
          | {:now_fun, (-> DateTime.t())}

  @type parse_opts() :: [parse_opt()]

  @typedoc "Normalized event structs emitted by the parser."
  @type event_struct() :: KillmailEvent.t() | JumpEvent.t() | AggressorEvent.t()

  @typedoc "Parser error reasons for malformed or unsupported events."
  @type reason() ::
          :nil_event_data
          | {:invalid_field, atom()}
          | {:missing_field, atom()}
          | {:unknown_event_type, atom()}

  @doc """
  Parses a single raw event into a normalized reputation event struct.
  """
  @spec parse_event(atom(), map() | nil, parse_opts()) ::
          {:ok, event_struct()} | {:error, reason()}
  def parse_event(_event_type, nil, _opts), do: {:error, :nil_event_data}

  def parse_event(:killmail_created, raw_data, opts) when is_map(raw_data) do
    with {:ok, killer_character_id} <- fetch_required(raw_data, "killer", :killer),
         {:ok, victim_character_id} <- fetch_required(raw_data, "victim", :victim),
         {:ok, loss_type} <- fetch_required(raw_data, "loss_type", :loss_type),
         {:ok, solar_system_id} <- fetch_optional_binary(raw_data, "solar_system", :solar_system) do
      tables = Keyword.fetch!(opts, :tables)

      {:ok,
       %KillmailEvent{
         killer_character_id: killer_character_id,
         victim_character_id: victim_character_id,
         killer_tribe_id: resolve_character_tribe(killer_character_id, tables),
         victim_tribe_id: resolve_character_tribe(victim_character_id, tables),
         solar_system_id: solar_system_id,
         loss_type: loss_type,
         timestamp: now(opts),
         checkpoint_seq: checkpoint_seq(opts)
       }}
    end
  end

  def parse_event(:jump, raw_data, opts) when is_map(raw_data) do
    with {:ok, character_id} <- fetch_required(raw_data, "character", :character),
         {:ok, source_gate_id} <- fetch_required(raw_data, "source_gate", :source_gate),
         {:ok, destination_gate_id} <-
           fetch_required(raw_data, "destination_gate", :destination_gate) do
      tables = Keyword.fetch!(opts, :tables)

      {:ok,
       %JumpEvent{
         character_id: character_id,
         character_tribe_id: resolve_character_tribe(character_id, tables),
         source_gate_id: source_gate_id,
         source_gate_owner_tribe_id: resolve_gate_owner_tribe(source_gate_id, tables),
         destination_gate_id: destination_gate_id,
         timestamp: now(opts),
         checkpoint_seq: checkpoint_seq(opts)
       }}
    end
  end

  def parse_event(:priority_list_updated, raw_data, opts) when is_map(raw_data) do
    with {:ok, turret_id} <- fetch_required(raw_data, "turret", :turret),
         {:ok, aggressor_character_id} <- fetch_required(raw_data, "aggressor", :aggressor) do
      tables = Keyword.fetch!(opts, :tables)

      {:ok,
       %AggressorEvent{
         turret_id: turret_id,
         turret_owner_tribe_id: resolve_turret_owner_tribe(turret_id, tables),
         aggressor_character_id: aggressor_character_id,
         aggressor_tribe_id: resolve_character_tribe(aggressor_character_id, tables),
         timestamp: now(opts),
         checkpoint_seq: checkpoint_seq(opts)
       }}
    end
  end

  def parse_event(event_type, _raw_data, _opts), do: {:error, {:unknown_event_type, event_type}}

  @doc """
  Parses a checkpoint batch, skipping events that fail validation.
  """
  @spec parse_checkpoint_events([{atom(), map() | nil, non_neg_integer()}], parse_opts()) :: [
          event_struct()
        ]
  def parse_checkpoint_events(events, opts) when is_list(events) do
    events
    |> Enum.reduce([], fn {event_type, raw_data, checkpoint_seq}, acc ->
      case parse_event(event_type, raw_data, Keyword.put(opts, :checkpoint_seq, checkpoint_seq)) do
        {:ok, event} -> [event | acc]
        {:error, _reason} -> acc
      end
    end)
    |> Enum.reverse()
  end

  @spec fetch_required(map(), String.t(), atom()) ::
          {:ok, String.t()} | {:error, {:missing_field, atom()}}
  defp fetch_required(raw_data, key, field_name) do
    case Map.fetch(raw_data, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      :error -> {:error, {:missing_field, field_name}}
      {:ok, _value} -> {:error, {:missing_field, field_name}}
    end
  end

  @spec fetch_optional_binary(map(), String.t(), atom()) ::
          {:ok, String.t() | nil} | {:error, {:invalid_field, atom()}}
  defp fetch_optional_binary(raw_data, key, field_name) do
    case Map.fetch(raw_data, key) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:ok, _value} -> {:error, {:invalid_field, field_name}}
    end
  end

  @spec resolve_character_tribe(String.t(), tables()) :: non_neg_integer() | nil
  defp resolve_character_tribe(character_id, tables) do
    case Cache.get(tables.characters, character_id) do
      %Character{tribe_id: tribe_id} -> tribe_id
      _other -> nil
    end
  end

  @spec resolve_gate_owner_tribe(String.t(), tables()) :: non_neg_integer() | nil
  defp resolve_gate_owner_tribe(gate_id, tables) do
    case Cache.get(tables.gate_network, gate_id) do
      %Gate{owner_cap_id: owner_cap_id} ->
        owner_cap_id
        |> owner_address_from_assembly(tables)
        |> tribe_id_for_owner(tables)

      _other ->
        gate_id
        |> owner_address_from_assembly(tables)
        |> tribe_id_for_owner(tables)
    end
  end

  @spec resolve_turret_owner_tribe(String.t(), tables()) :: non_neg_integer() | nil
  defp resolve_turret_owner_tribe(turret_id, tables) do
    case Cache.get(tables.assemblies, turret_id) do
      {owner_address, %Turret{}} ->
        tribe_id_for_owner(owner_address, tables)

      {_owner_address, _assembly} = owner_entry ->
        owner_entry |> owner_address() |> tribe_id_for_owner(tables)

      _other ->
        nil
    end
  end

  @spec owner_address_from_assembly(String.t(), tables()) :: String.t() | nil
  defp owner_address_from_assembly(assembly_key, tables) do
    tables.assemblies
    |> Cache.get(assembly_key)
    |> owner_address()
  end

  @spec owner_address({String.t(), term()} | term()) :: String.t() | nil
  defp owner_address({owner_address, _assembly}) when is_binary(owner_address), do: owner_address
  defp owner_address(_other), do: nil

  @spec tribe_id_for_owner(String.t() | nil, tables()) :: non_neg_integer() | nil
  defp tribe_id_for_owner(nil, _tables), do: nil

  defp tribe_id_for_owner(owner_address, tables) do
    case Cache.get(tables.accounts, owner_address) do
      %Account{tribe_id: tribe_id} -> tribe_id
      %{tribe_id: tribe_id} when is_integer(tribe_id) -> tribe_id
      _other -> nil
    end
  end

  @spec checkpoint_seq(parse_opts()) :: non_neg_integer()
  defp checkpoint_seq(opts), do: Keyword.get(opts, :checkpoint_seq, 0)

  @spec now(parse_opts()) :: DateTime.t()
  defp now(opts) do
    opts
    |> Keyword.get(:now_fun, &DateTime.utc_now/0)
    |> then(& &1.())
  end
end
