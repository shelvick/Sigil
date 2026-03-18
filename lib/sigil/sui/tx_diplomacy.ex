defmodule Sigil.Sui.TxDiplomacy do
  @moduledoc """
  Builds programmable transaction options for StandingsTable operations.
  """

  alias Sigil.Sui.BCS
  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TransactionBuilder.PTB

  @module_name "standings_table"

  @typedoc "Shared object reference for an existing StandingsTable."
  @type table_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Base transaction options required by the transaction builder."
  @type tx_opts() :: [
          sender: PTB.bytes32(),
          gas_payment: [PTB.object_ref()],
          gas_price: non_neg_integer(),
          gas_budget: non_neg_integer()
        ]

  @typedoc "StandingsTable standing tier."
  @type standing() :: 0..4

  @doc "Builds transaction options for `standings_table::create`."
  @spec build_create_table(tx_opts()) :: TransactionBuilder.build_opts()
  def build_create_table(tx_opts) when is_list(tx_opts) do
    tx_opts ++ [inputs: [], commands: [move_call("create", [])]]
  end

  @doc "Builds transaction options for `standings_table::set_standing`."
  @spec build_set_standing(table_ref(), non_neg_integer(), standing(), tx_opts()) ::
          TransactionBuilder.build_opts()
  def build_set_standing(table_ref, tribe_id, standing, tx_opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(tx_opts) do
    validate_standing!(standing)

    inputs = [
      shared_table_input(table_ref),
      {:pure, BCS.encode_u32(tribe_id)},
      {:pure, BCS.encode_u8(standing)}
    ]

    tx_opts ++ [inputs: inputs, commands: [move_call("set_standing", input_arguments(inputs))]]
  end

  @doc "Builds transaction options for `standings_table::set_default_standing`."
  @spec build_set_default_standing(table_ref(), standing(), tx_opts()) ::
          TransactionBuilder.build_opts()
  def build_set_default_standing(table_ref, standing, tx_opts) when is_list(tx_opts) do
    validate_standing!(standing)

    inputs = [
      shared_table_input(table_ref),
      {:pure, BCS.encode_u8(standing)}
    ]

    tx_opts ++
      [inputs: inputs, commands: [move_call("set_default_standing", input_arguments(inputs))]]
  end

  @doc "Builds transaction options for `standings_table::set_pilot_standing`."
  @spec build_set_pilot_standing(table_ref(), PTB.bytes32(), standing(), tx_opts()) ::
          TransactionBuilder.build_opts()
  def build_set_pilot_standing(table_ref, <<_::binary-size(32)>> = pilot, standing, tx_opts)
      when is_list(tx_opts) do
    validate_standing!(standing)

    inputs = [
      shared_table_input(table_ref),
      {:pure, BCS.encode_address(pilot)},
      {:pure, BCS.encode_u8(standing)}
    ]

    tx_opts ++
      [inputs: inputs, commands: [move_call("set_pilot_standing", input_arguments(inputs))]]
  end

  @doc "Builds transaction options for `standings_table::batch_set_standings`."
  @spec build_batch_set_standings(table_ref(), [{non_neg_integer(), standing()}], tx_opts()) ::
          TransactionBuilder.build_opts()
  def build_batch_set_standings(table_ref, updates, tx_opts)
      when is_list(updates) and is_list(tx_opts) do
    ensure_non_empty_batch!(updates)

    {tribe_ids, standings} = Enum.unzip(updates)
    Enum.each(standings, &validate_standing!/1)

    inputs = [
      shared_table_input(table_ref),
      {:pure, BCS.encode_vector(tribe_ids, &BCS.encode_u32/1)},
      {:pure, BCS.encode_vector(standings, &BCS.encode_u8/1)}
    ]

    tx_opts ++
      [inputs: inputs, commands: [move_call("batch_set_standings", input_arguments(inputs))]]
  end

  @doc "Builds transaction options for `standings_table::batch_set_pilot_standings`."
  @spec build_batch_set_pilot_standings(table_ref(), [{PTB.bytes32(), standing()}], tx_opts()) ::
          TransactionBuilder.build_opts()
  def build_batch_set_pilot_standings(table_ref, updates, tx_opts)
      when is_list(updates) and is_list(tx_opts) do
    ensure_non_empty_batch!(updates)

    {pilots, standings} = Enum.unzip(updates)
    Enum.each(standings, &validate_standing!/1)

    inputs = [
      shared_table_input(table_ref),
      {:pure, BCS.encode_vector(pilots, &BCS.encode_address/1)},
      {:pure, BCS.encode_vector(standings, &BCS.encode_u8/1)}
    ]

    tx_opts ++
      [
        inputs: inputs,
        commands: [move_call("batch_set_pilot_standings", input_arguments(inputs))]
      ]
  end

  defp move_call(function, arguments) do
    {:move_call, sigil_package_id_bytes(), @module_name, function, [], arguments}
  end

  @spec sigil_package_id_bytes() :: binary()
  defp sigil_package_id_bytes do
    "0x" <> hex = sigil_package_id()
    Base.decode16!(hex, case: :mixed)
  end

  @spec sigil_package_id() :: String.t()
  defp sigil_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{sigil_package_id: id} = Map.fetch!(worlds, world)
    id
  end

  defp input_arguments(inputs) do
    inputs
    |> Enum.with_index()
    |> Enum.map(fn {_input, index} -> {:input, index} end)
  end

  defp shared_table_input(%{object_id: object_id, initial_shared_version: version})
       when is_integer(version) and version >= 0 do
    {:object, {:shared, object_id, version, true}}
  end

  defp validate_standing!(standing) when standing in 0..4, do: :ok

  defp validate_standing!(_standing) do
    raise ArgumentError, "standing must be between 0 and 4"
  end

  defp ensure_non_empty_batch!([]), do: raise(ArgumentError, "batch updates must not be empty")
  defp ensure_non_empty_batch!(_updates), do: :ok
end
