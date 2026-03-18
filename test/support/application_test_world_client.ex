defmodule Sigil.ApplicationTestWorldClient do
  @moduledoc """
  Returns static-data fixture payloads for spawned application snapshot probes.
  """

  @behaviour Sigil.StaticData.WorldClient

  alias Sigil.StaticDataTestFixtures, as: Fixtures

  @doc "Returns item type fixtures for application probe subprocesses."
  @impl true
  @spec fetch_types(keyword()) ::
          {:ok, [map()]} | {:error, Sigil.StaticData.WorldClient.error_reason()}
  def fetch_types(_opts), do: {:ok, Fixtures.item_type_records()}

  @doc "Returns solar system fixtures for application probe subprocesses."
  @impl true
  @spec fetch_solar_systems(keyword()) ::
          {:ok, [map()]} | {:error, Sigil.StaticData.WorldClient.error_reason()}
  def fetch_solar_systems(_opts), do: {:ok, Fixtures.solar_system_records()}

  @doc "Returns constellation fixtures for application probe subprocesses."
  @impl true
  @spec fetch_constellations(keyword()) ::
          {:ok, [map()]} | {:error, Sigil.StaticData.WorldClient.error_reason()}
  def fetch_constellations(_opts), do: {:ok, Fixtures.constellation_records()}

  @doc "Returns empty tribe list for application probe subprocesses."
  @impl true
  @spec fetch_tribes(keyword()) ::
          {:ok, [map()]} | {:error, Sigil.StaticData.WorldClient.error_reason()}
  def fetch_tribes(_opts), do: {:ok, []}
end

defmodule Sigil.DiplomacyTestWorldClient do
  @moduledoc """
  Returns caller-supplied tribe records for diplomacy probe subprocesses.
  """

  @doc "Returns the tribe records provided under the `:tribes` request option."
  @spec fetch_tribes(keyword()) :: {:ok, [map()]}
  def fetch_tribes(opts), do: {:ok, Keyword.fetch!(opts, :tribes)}
end

defmodule Sigil.DiplomacyTestSuiClient do
  @moduledoc """
  Returns deterministic Sui responses for diplomacy probe subprocesses.
  """

  @behaviour Sigil.Sui.Client

  @standings_table_type "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1::standings_table::StandingsTable"
  @sui_coin_type "0x2::coin::Coin<0x2::sui::SUI>"

  @doc "Returns `:not_found` because diplomacy probes do not fetch individual objects."
  @impl true
  @spec get_object(String.t(), keyword()) :: {:error, :not_found}
  def get_object(_id, _opts), do: {:error, :not_found}

  @doc "Returns deterministic table and gas coin pages for diplomacy probe subprocesses."
  @impl true
  @spec get_objects(Sigil.Sui.Client.object_filter(), keyword()) ::
          {:ok, Sigil.Sui.Client.objects_page()}
  def get_objects([type: @standings_table_type], opts) do
    owner = Keyword.get(opts, :table_owner, "0x" <> String.duplicate("aa", 32))
    table_id = Keyword.fetch!(opts, :table_id)
    table_version = Keyword.fetch!(opts, :table_version)

    {:ok,
     %{
       data: [
         %{
           "id" => table_id,
           "address" => table_id,
           "owner" => owner,
           "initialSharedVersion" => Integer.to_string(table_version),
           "shared" => %{"initialSharedVersion" => Integer.to_string(table_version)}
         }
       ],
       has_next_page: false,
       end_cursor: nil
     }}
  end

  def get_objects([type: @sui_coin_type, owner: _owner, limit: 1], opts) do
    gas_coin_id = Keyword.get(opts, :gas_coin_id, "0x" <> String.duplicate("bb", 32))

    {:ok,
     %{
       data: [%{"id" => gas_coin_id}],
       has_next_page: false,
       end_cursor: nil
     }}
  end

  def get_objects(_filters, _opts), do: {:ok, %{data: [], has_next_page: false, end_cursor: nil}}

  @doc "Returns a gas coin object ref for diplomacy probe subprocesses."
  @impl true
  @spec get_object_with_ref(String.t(), keyword()) ::
          {:ok, Sigil.Sui.Client.object_with_ref()}
  def get_object_with_ref(coin_id, opts) do
    gas_version = Keyword.get(opts, :gas_version, 7)

    padded = coin_id |> String.trim_leading("0x") |> String.pad_leading(64, "0")
    {:ok, id_bytes} = Base.decode16(padded, case: :mixed)

    {:ok,
     %{
       json: %{"id" => coin_id, "balance" => "500000000"},
       ref: {id_bytes, gas_version, <<0::256>>}
     }}
  end

  @doc "Returns a successful transaction execution payload for diplomacy probe subprocesses."
  @impl true
  @spec execute_transaction(String.t(), [String.t()], keyword()) ::
          {:ok, Sigil.Sui.Client.tx_effects()}
  def execute_transaction(_tx_bytes, _signatures, opts) do
    {:ok,
     %{
       "status" => "SUCCESS",
       "transaction" => %{"digest" => Keyword.get(opts, :tx_digest, "probe-digest")},
       "gasEffects" => %{"gasSummary" => %{"computationCost" => "1"}}
     }}
  end

  @doc "Returns `:not_found` because diplomacy probes do not verify zkLogin signatures."
  @impl true
  @spec verify_zklogin_signature(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:error, :not_found}
  def verify_zklogin_signature(_bytes, _signature, _intent_scope, _author, _opts),
    do: {:error, :not_found}
end
