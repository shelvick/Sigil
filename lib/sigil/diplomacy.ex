defmodule Sigil.Diplomacy do
  @moduledoc """
  Diplomatic standings management backed by ETS cache and StandingsTable on-chain operations.
  """

  alias Sigil.Cache
  alias Sigil.Diplomacy.LocalSigner
  alias Sigil.Sui.{Client, TransactionBuilder, TxDiplomacy}

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @diplomacy_topic "diplomacy"

  @standings %{0 => :hostile, 1 => :unfriendly, 2 => :neutral, 3 => :friendly, 4 => :allied}

  @typedoc "Standing atom values."
  @type standing_atom() :: :hostile | :unfriendly | :neutral | :friendly | :allied

  @typedoc "Standing integer values (0-4)."
  @type standing_value() :: 0..4

  @typedoc "Table discovery info for a StandingsTable on-chain object."
  @type table_info() :: %{
          object_id: String.t(),
          object_id_bytes: <<_::256>>,
          initial_shared_version: non_neg_integer(),
          owner: String.t()
        }

  @typedoc "Tribe standing entry."
  @type tribe_entry() :: %{tribe_id: non_neg_integer(), standing: standing_atom()}

  @typedoc "Pilot standing entry."
  @type pilot_entry() :: %{pilot: String.t(), standing: standing_atom()}

  @typedoc "World API tribe record."
  @type world_tribe() :: %{id: non_neg_integer(), name: String.t(), short_name: String.t()}

  @typedoc "Options accepted by diplomacy context functions."
  @type option() ::
          {:tables, %{standings: Cache.table_id()}}
          | {:pubsub, atom() | module()}
          | {:req_options, Client.request_opts()}
          | {:sender, String.t()}
          | {:client, module()}

  @type options() :: [option()]

  # ---------------------------------------------------------------------------
  # Table Discovery
  # ---------------------------------------------------------------------------

  @doc "Discovers StandingsTable objects owned by the given address."
  @spec discover_tables(String.t(), options()) ::
          {:ok, [table_info()]} | {:error, Client.error_reason()}
  def discover_tables(address, opts) when is_binary(address) and is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, %{data: objects}} <-
           client.get_objects([type: standings_table_type()], req_options) do
      objects = Enum.filter(objects, fn obj -> obj["owner"] == address end)

      tables_found =
        objects
        |> Enum.map(fn obj ->
          object_id = obj["id"]

          # Try parsing initial_shared_version from the object JSON first
          # (works with mock data and some GraphQL responses). Fall back to
          # RPC query for shared objects on a real chain.
          version =
            parse_shared_version(obj) || LocalSigner.fetch_initial_shared_version(object_id)

          %{
            object_id: object_id,
            object_id_bytes: hex_to_bytes(object_id),
            initial_shared_version: version,
            owner: obj["owner"] || address
          }
        end)

      # Auto-select if exactly one table
      if length(tables_found) == 1 do
        sender = Keyword.get(opts, :sender, address)
        set_active_table(hd(tables_found), Keyword.put(opts, :sender, sender))
      end

      broadcast(opts, {:table_discovered, tables_found})

      {:ok, tables_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Standings Reads
  # ---------------------------------------------------------------------------

  @doc "Returns the standing atom for a tribe, defaulting to :neutral."
  @spec get_standing(non_neg_integer(), options()) :: standing_atom()
  def get_standing(tribe_id, opts) when is_integer(tribe_id) and is_list(opts) do
    case Cache.get(standings_table(opts), {:tribe_standing, tribe_id}) do
      nil -> :neutral
      value -> standing_to_atom(value)
    end
  end

  @doc "Returns all cached tribe standings."
  @spec list_standings(options()) :: [tribe_entry()]
  def list_standings(opts) when is_list(opts) do
    table = standings_table(opts)

    table
    |> Cache.match({{:tribe_standing, :_}, :_})
    |> Enum.map(fn {{:tribe_standing, tribe_id}, value} ->
      %{tribe_id: tribe_id, standing: standing_to_atom(value)}
    end)
  end

  @doc "Returns all cached pilot standings."
  @spec list_pilot_standings(options()) :: [pilot_entry()]
  def list_pilot_standings(opts) when is_list(opts) do
    table = standings_table(opts)

    table
    |> Cache.match({{:pilot_standing, :_}, :_})
    |> Enum.map(fn {{:pilot_standing, pilot}, value} ->
      %{pilot: pilot, standing: standing_to_atom(value)}
    end)
  end

  @doc "Returns the standing atom for a pilot, defaulting to :neutral."
  @spec get_pilot_standing(String.t(), options()) :: standing_atom()
  def get_pilot_standing(pilot, opts) when is_binary(pilot) and is_list(opts) do
    case Cache.get(standings_table(opts), {:pilot_standing, pilot}) do
      nil -> :neutral
      value -> standing_to_atom(value)
    end
  end

  @doc "Returns the default standing, defaulting to :neutral."
  @spec get_default_standing(options()) :: standing_atom()
  def get_default_standing(opts) when is_list(opts) do
    case Cache.get(standings_table(opts), :default_standing) do
      nil -> :neutral
      value -> standing_to_atom(value)
    end
  end

  # -- Active Table Selection --

  @doc "Stores the selected table in ETS under the sender scope."
  @spec set_active_table(table_info(), options()) :: :ok
  def set_active_table(table, opts) when is_map(table) and is_list(opts) do
    sender = Keyword.fetch!(opts, :sender)
    Cache.put(standings_table(opts), {:active_table, sender}, table)
  end

  @doc "Returns the currently active table for the sender, or nil."
  @spec get_active_table(options()) :: table_info() | nil
  def get_active_table(opts) when is_list(opts) do
    sender = Keyword.fetch!(opts, :sender)
    Cache.get(standings_table(opts), {:active_table, sender})
  end

  # ---------------------------------------------------------------------------
  # Transaction Building
  # ---------------------------------------------------------------------------

  @doc "Builds transaction kind bytes for set_standing (wallet handles gas)."
  @spec build_set_standing_tx(non_neg_integer(), standing_value(), options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_active_table}
  def build_set_standing_tx(tribe_id, standing, opts)
      when is_integer(tribe_id) and is_integer(standing) and is_list(opts) do
    with {:ok, active_table} <- require_active_table(opts) do
      table_ref = to_table_ref(active_table)

      tx_bytes =
        table_ref
        |> TxDiplomacy.build_set_standing(tribe_id, standing, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:set_standing, tribe_id, standing})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for create_table (wallet handles gas)."
  @spec build_create_table_tx(options()) :: {:ok, %{tx_bytes: String.t()}}
  def build_create_table_tx(opts) when is_list(opts) do
    tx_bytes =
      []
      |> TxDiplomacy.build_create_table()
      |> TransactionBuilder.build_kind!()
      |> Base.encode64()

    store_pending_tx(opts, tx_bytes, :create_table)

    {:ok, %{tx_bytes: tx_bytes}}
  end

  @doc "Builds transaction kind bytes for batch_set_standings (wallet handles gas)."
  @spec build_batch_set_standings_tx([{non_neg_integer(), standing_value()}], options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_active_table}
  def build_batch_set_standings_tx(updates, opts)
      when is_list(updates) and is_list(opts) do
    with {:ok, active_table} <- require_active_table(opts) do
      table_ref = to_table_ref(active_table)

      tx_bytes =
        table_ref
        |> TxDiplomacy.build_batch_set_standings(updates, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:batch_set_standings, updates})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for set_pilot_standing (wallet handles gas)."
  @spec build_set_pilot_standing_tx(String.t(), standing_value(), options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_active_table}
  def build_set_pilot_standing_tx(pilot, standing, opts)
      when is_binary(pilot) and is_integer(standing) and is_list(opts) do
    with {:ok, active_table} <- require_active_table(opts) do
      table_ref = to_table_ref(active_table)

      tx_bytes =
        table_ref
        |> TxDiplomacy.build_set_pilot_standing(hex_to_bytes(pilot), standing, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:set_pilot_standing, pilot, standing})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for set_default_standing (wallet handles gas)."
  @spec build_set_default_standing_tx(standing_value(), options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_active_table}
  def build_set_default_standing_tx(standing, opts)
      when is_integer(standing) and is_list(opts) do
    with {:ok, active_table} <- require_active_table(opts) do
      table_ref = to_table_ref(active_table)

      tx_bytes =
        table_ref
        |> TxDiplomacy.build_set_default_standing(standing, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:set_default_standing, standing})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for batch_set_pilot_standings (wallet handles gas)."
  @spec build_batch_set_pilot_standings_tx([{String.t(), standing_value()}], options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_active_table}
  def build_batch_set_pilot_standings_tx(updates, opts)
      when is_list(updates) and is_list(opts) do
    with {:ok, active_table} <- require_active_table(opts) do
      table_ref = to_table_ref(active_table)

      encoded_updates =
        Enum.map(updates, fn {pilot, standing} -> {hex_to_bytes(pilot), standing} end)

      tx_bytes =
        table_ref
        |> TxDiplomacy.build_batch_set_pilot_standings(encoded_updates, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:batch_set_pilot_standings, updates})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  # ---------------------------------------------------------------------------
  # Transaction Submission
  # ---------------------------------------------------------------------------

  @doc "Submits a wallet-signed transaction and updates cache on success."
  @spec submit_signed_transaction(String.t(), String.t(), options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}}
          | {:error, Client.error_reason()}
  def submit_signed_transaction(tx_bytes, signature, opts)
      when is_binary(tx_bytes) and is_binary(signature) and is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    case client.execute_transaction(tx_bytes, [signature], req_options) do
      {:ok, %{"status" => "SUCCESS", "transaction" => %{"digest" => digest}} = effects} ->
        apply_pending_tx(opts, tx_bytes)
        {:ok, %{digest: digest, effects_bcs: effects["bcs"]}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Signs and submits a transaction locally (no wallet involved).

  For localnet development only. Delegates to `Diplomacy.LocalSigner`.
  """
  @spec sign_and_submit_locally(String.t(), options()) ::
          {:ok, %{digest: String.t()}} | {:error, term()}
  def sign_and_submit_locally(kind_bytes_b64, opts)
      when is_binary(kind_bytes_b64) and is_list(opts) do
    case LocalSigner.sign_and_submit(kind_bytes_b64) do
      {:ok, digest} ->
        apply_pending_tx(opts, kind_bytes_b64)
        {:ok, %{digest: digest}}

      {:error, _reason} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Tribe Name Resolution
  # ---------------------------------------------------------------------------

  @doc "Fetches tribe names from the World API and caches them in ETS."
  @spec resolve_tribe_names(options()) :: {:ok, [world_tribe()]} | {:error, term()}
  def resolve_tribe_names(opts) when is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    world_client = Application.fetch_env!(:sigil, :world_client)

    with {:ok, tribe_records} <- world_client.fetch_tribes(req_options) do
      tribes =
        Enum.map(tribe_records, fn record ->
          tribe = %{
            id: record["id"],
            name: record["name"],
            short_name: record["short_name"]
          }

          Cache.put(standings_table(opts), {:world_tribe, tribe.id}, tribe)
          tribe
        end)

      {:ok, tribes}
    end
  end

  @doc "Returns a cached tribe name or nil."
  @spec get_tribe_name(non_neg_integer(), options()) :: world_tribe() | nil
  def get_tribe_name(tribe_id, opts) when is_integer(tribe_id) and is_list(opts) do
    Cache.get(standings_table(opts), {:world_tribe, tribe_id})
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  @spec standings_table(options()) :: Cache.table_id()
  defp standings_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:standings)
  end

  @spec broadcast(options(), term()) :: :ok | {:error, term()}
  defp broadcast(opts, event) do
    pubsub = Keyword.get(opts, :pubsub, Sigil.PubSub)
    Phoenix.PubSub.broadcast(pubsub, @diplomacy_topic, event)
  end

  @spec parse_shared_version(map()) :: non_neg_integer() | nil
  defp parse_shared_version(%{"initial_shared_version" => v}) when is_integer(v), do: v

  defp parse_shared_version(%{"shared" => %{"initialSharedVersion" => v}}) when is_binary(v),
    do: String.to_integer(v)

  defp parse_shared_version(%{"initialSharedVersion" => v}) when is_binary(v),
    do: String.to_integer(v)

  defp parse_shared_version(_), do: nil

  @spec standing_to_atom(standing_value()) :: standing_atom()
  defp standing_to_atom(value) when is_map_key(@standings, value), do: @standings[value]

  @spec hex_to_bytes(String.t()) :: binary()
  defp hex_to_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  @spec to_table_ref(table_info()) :: TxDiplomacy.table_ref()
  defp to_table_ref(table) do
    %{
      object_id: table.object_id_bytes,
      initial_shared_version: table.initial_shared_version
    }
  end

  @spec require_active_table(options()) :: {:ok, table_info()} | {:error, :no_active_table}
  defp require_active_table(opts) do
    sender = Keyword.fetch!(opts, :sender)

    case Cache.get(standings_table(opts), {:active_table, sender}) do
      nil -> {:error, :no_active_table}
      table -> {:ok, table}
    end
  end

  @spec store_pending_tx(options(), String.t(), term()) :: :ok
  defp store_pending_tx(opts, tx_bytes, operation) do
    Cache.put(standings_table(opts), {:pending_tx, tx_bytes}, operation)
  end

  @spec apply_pending_tx(options(), String.t()) :: :ok
  defp apply_pending_tx(opts, tx_bytes) do
    table = standings_table(opts)

    case Cache.take(table, {:pending_tx, tx_bytes}) do
      {:set_standing, tribe_id, standing} ->
        Cache.put(table, {:tribe_standing, tribe_id}, standing)

        broadcast(
          opts,
          {:standing_updated, %{tribe_id: tribe_id, standing: standing_to_atom(standing)}}
        )

      {:set_pilot_standing, pilot, standing} ->
        Cache.put(table, {:pilot_standing, pilot}, standing)

        broadcast(
          opts,
          {:pilot_standing_updated, %{pilot: pilot, standing: standing_to_atom(standing)}}
        )

      {:set_default_standing, standing} ->
        Cache.put(table, :default_standing, standing)
        broadcast(opts, {:default_standing_updated, standing_to_atom(standing)})

      {:batch_set_standings, updates} ->
        Enum.each(updates, fn {tribe_id, standing} ->
          Cache.put(table, {:tribe_standing, tribe_id}, standing)

          broadcast(
            opts,
            {:standing_updated, %{tribe_id: tribe_id, standing: standing_to_atom(standing)}}
          )
        end)

      {:batch_set_pilot_standings, updates} ->
        Enum.each(updates, fn {pilot, standing} ->
          Cache.put(table, {:pilot_standing, pilot}, standing)

          broadcast(
            opts,
            {:pilot_standing_updated, %{pilot: pilot, standing: standing_to_atom(standing)}}
          )
        end)

      :create_table ->
        :ok

      nil ->
        :ok
    end

    :ok
  end

  @spec standings_table_type() :: String.t()
  defp standings_table_type do
    "#{sigil_package_id()}::standings_table::StandingsTable"
  end

  @spec sigil_package_id() :: String.t()
  defp sigil_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{sigil_package_id: id} = Map.fetch!(worlds, world)
    id
  end
end
