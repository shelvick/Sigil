defmodule Sigil.Diplomacy do
  @moduledoc """
  Diplomatic standings management backed by ETS cache and TribeCustodian operations.
  """

  alias Sigil.Cache
  alias Sigil.Diplomacy.{Discovery, Governance, ObjectCodec, ReputationOps, TransactionOps}

  @diplomacy_topic "diplomacy"

  @typedoc "Standing atom values."
  @type standing_atom() :: :hostile | :unfriendly | :neutral | :friendly | :allied

  @typedoc "Standing integer values (0-4)."
  @type standing_value() :: 0..4

  @typedoc "Discovered tribe custodian information."
  @type custodian_info() :: %{
          required(:object_id) => String.t(),
          required(:object_id_bytes) => <<_::256>>,
          required(:initial_shared_version) => non_neg_integer(),
          required(:tribe_id) => non_neg_integer(),
          required(:current_leader) => String.t(),
          optional(:current_leader_votes) => non_neg_integer(),
          optional(:members) => [String.t()],
          optional(:votes_table_id) => String.t(),
          optional(:vote_tallies_table_id) => String.t(),
          optional(:oracle_address) => String.t() | nil
        }

  @typedoc "Cached governance votes keyed by voter address."
  @type vote_map() :: %{String.t() => String.t()}

  @typedoc "Cached governance tallies keyed by candidate address."
  @type tally_map() :: %{String.t() => non_neg_integer()}

  @typedoc "Cached governance state for a tribe."
  @type governance_data() :: %{votes: vote_map(), tallies: tally_map()}

  @typedoc "Shared object reference for a character."
  @type character_ref() :: %{
          object_id: <<_::256>>,
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Shared object reference for the custodian registry."
  @type registry_ref() :: %{
          object_id: <<_::256>>,
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Tribe standing entry."
  @type tribe_entry() :: %{tribe_id: non_neg_integer(), standing: standing_atom()}

  @typedoc "Pilot standing entry."
  @type pilot_entry() :: %{pilot: String.t(), standing: standing_atom()}

  @typedoc "World API tribe record."
  @type world_tribe() :: %{id: non_neg_integer(), name: String.t(), short_name: String.t()}

  @typedoc "Cached reputation score entry for a tribe-pair."
  @type reputation_score() :: %{
          tribe_id: non_neg_integer(),
          target_tribe_id: non_neg_integer(),
          score: -1000..1000,
          pinned: boolean(),
          pinned_standing: standing_atom() | nil,
          updated_at: DateTime.t() | nil
        }

  @typedoc "Options accepted by diplomacy context functions."
  @type option() ::
          {:tables,
           %{required(:standings) => Cache.table_id(), optional(:reputation) => Cache.table_id()}}
          | {:pubsub, atom() | module()}
          | {:req_options, Sigil.Sui.Client.request_opts()}
          | {:sender, String.t()}
          | {:tribe_id, non_neg_integer()}
          | {:character_id, String.t()}
          | {:character_ref, character_ref()}
          | {:registry_ref, registry_ref()}
          | {:client, module()}

  @type options() :: [option()]

  @doc "Discovers the custodian for the given tribe."
  @spec discover_custodian(non_neg_integer(), options()) ::
          {:ok, custodian_info() | nil} | {:error, Sigil.Sui.Client.error_reason()}
  def discover_custodian(tribe_id, opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(opts),
      do: Discovery.discover_custodian(tribe_id, opts)

  @doc "Resolves a character shared-object reference from options, cache, or chain."
  @spec resolve_character_ref(String.t(), options()) :: {:ok, character_ref()} | {:error, term()}
  def resolve_character_ref(character_id, opts) when is_binary(character_id) and is_list(opts),
    do: Discovery.resolve_character_ref(character_id, opts)

  @doc "Resolves the shared registry reference from options, cache, or chain."
  @spec resolve_registry_ref(options()) :: {:ok, registry_ref()} | {:error, term()}
  def resolve_registry_ref(opts) when is_list(opts), do: Discovery.resolve_registry_ref(opts)

  @doc "Returns the standing atom for a tribe, defaulting to :neutral."
  @spec get_standing(non_neg_integer(), options()) :: standing_atom()
  def get_standing(target_tribe_id, opts) when is_integer(target_tribe_id) and is_list(opts) do
    source = source_tribe_id(opts)

    case Cache.get(standings_table(opts), {:tribe_standing, source, target_tribe_id}) do
      nil -> :neutral
      value -> ObjectCodec.standing_to_atom(value)
    end
  end

  @doc "Returns all cached tribe standings for the active source tribe."
  @spec list_standings(options()) :: [tribe_entry()]
  def list_standings(opts) when is_list(opts) do
    source = source_tribe_id(opts)

    standings_table(opts)
    |> Cache.match({{:tribe_standing, source, :_}, :_})
    |> Enum.map(fn {{:tribe_standing, ^source, target_tribe_id}, value} ->
      %{tribe_id: target_tribe_id, standing: ObjectCodec.standing_to_atom(value)}
    end)
  end

  @doc "Returns all cached pilot standings for the active source tribe."
  @spec list_pilot_standings(options()) :: [pilot_entry()]
  def list_pilot_standings(opts) when is_list(opts) do
    source = source_tribe_id(opts)

    standings_table(opts)
    |> Cache.match({{:pilot_standing, source, :_}, :_})
    |> Enum.map(fn {{:pilot_standing, ^source, pilot}, value} ->
      %{pilot: pilot, standing: ObjectCodec.standing_to_atom(value)}
    end)
  end

  @doc "Returns the standing atom for a pilot, defaulting to :neutral."
  @spec get_pilot_standing(String.t(), options()) :: standing_atom()
  def get_pilot_standing(pilot, opts) when is_binary(pilot) and is_list(opts) do
    source = source_tribe_id(opts)

    case Cache.get(standings_table(opts), {:pilot_standing, source, pilot}) do
      nil -> :neutral
      value -> ObjectCodec.standing_to_atom(value)
    end
  end

  @doc "Returns the default standing, defaulting to :neutral."
  @spec get_default_standing(options()) :: standing_atom()
  def get_default_standing(opts) when is_list(opts) do
    source = source_tribe_id(opts)

    case Cache.get(standings_table(opts), {:default_standing, source}) do
      nil -> :neutral
      value -> ObjectCodec.standing_to_atom(value)
    end
  end

  @doc "Stores the active custodian in ETS under the tribe scope."
  @spec set_active_custodian(custodian_info(), options()) :: :ok
  def set_active_custodian(custodian, opts) when is_map(custodian) and is_list(opts) do
    Cache.put(
      standings_table(opts),
      {:active_custodian, active_tribe_id(custodian, opts)},
      custodian
    )
  end

  @doc "Returns the active custodian for the current tribe, or nil."
  @spec get_active_custodian(options()) :: custodian_info() | nil
  def get_active_custodian(opts) when is_list(opts) do
    Cache.get(standings_table(opts), {:active_custodian, source_tribe_id(opts)})
  end

  @doc "Returns true when the sender is the active custodian leader."
  @spec leader?(options()) :: boolean()
  def leader?(opts) when is_list(opts) do
    case get_active_custodian(opts) do
      %{current_leader: current_leader} -> current_leader == Keyword.get(opts, :sender)
      _custodian -> false
    end
  end

  @doc "Builds transaction kind bytes for setting a tribe standing."
  @spec build_set_standing_tx(non_neg_integer(), standing_value(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_standing_tx(target_tribe_id, standing, opts)
      when is_integer(target_tribe_id) and is_integer(standing) and is_list(opts),
      do: TransactionOps.build_set_standing_tx(target_tribe_id, standing, opts)

  @doc "Builds transaction kind bytes for creating a custodian."
  @spec build_create_custodian_tx(options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_registry_ref | :no_character_ref | term()}
  def build_create_custodian_tx(opts) when is_list(opts),
    do: TransactionOps.build_create_custodian_tx(opts)

  @doc "Builds transaction kind bytes for setting multiple tribe standings."
  @spec build_batch_set_standings_tx([{non_neg_integer(), standing_value()}], options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_batch_set_standings_tx(updates, opts) when is_list(updates) and is_list(opts),
    do: TransactionOps.build_batch_set_standings_tx(updates, opts)

  @doc "Builds transaction kind bytes for setting a pilot standing."
  @spec build_set_pilot_standing_tx(String.t(), standing_value(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_pilot_standing_tx(pilot, standing, opts)
      when is_binary(pilot) and is_integer(standing) and is_list(opts),
      do: TransactionOps.build_set_pilot_standing_tx(pilot, standing, opts)

  @doc "Builds transaction kind bytes for setting the default standing."
  @spec build_set_default_standing_tx(standing_value(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_default_standing_tx(standing, opts) when is_integer(standing) and is_list(opts),
    do: TransactionOps.build_set_default_standing_tx(standing, opts)

  @doc "Builds transaction kind bytes for setting multiple pilot standings."
  @spec build_batch_set_pilot_standings_tx([{String.t(), standing_value()}], options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_batch_set_pilot_standings_tx(updates, opts) when is_list(updates) and is_list(opts),
    do: TransactionOps.build_batch_set_pilot_standings_tx(updates, opts)

  @doc "Builds transaction kind bytes for voting for a leader candidate."
  @spec build_vote_leader_tx(String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  defdelegate build_vote_leader_tx(candidate, opts), to: Governance

  @doc "Builds transaction kind bytes for claiming tribe leadership."
  @spec build_claim_leadership_tx(options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  defdelegate build_claim_leadership_tx(opts), to: Governance

  @doc "Loads and caches governance votes and tallies for the active custodian."
  @spec load_governance_data(options()) :: {:ok, governance_data()} | {:error, term()}
  defdelegate load_governance_data(opts), to: Governance

  @doc "Returns true when the sender is a member of the active custodian."
  @spec member?(options()) :: boolean()
  defdelegate member?(opts), to: Governance

  @doc "Returns the tribe-scoped diplomacy topic."
  @spec topic(non_neg_integer()) :: String.t()
  def topic(tribe_id) when is_integer(tribe_id) and tribe_id >= 0 do
    "diplomacy:#{tribe_id}"
  end

  @doc "Returns the legacy shared diplomacy topic used by standings consumers."
  @spec legacy_topic() :: String.t()
  def legacy_topic, do: @diplomacy_topic

  @doc "Submits a wallet-signed transaction and updates cache on success."
  @spec submit_signed_transaction(String.t(), String.t(), options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}} | {:error, term()}
  def submit_signed_transaction(tx_bytes, signature, opts)
      when is_binary(tx_bytes) and is_binary(signature) and is_list(opts),
      do: TransactionOps.submit_signed_transaction(tx_bytes, signature, opts)

  @doc "Signs and submits a transaction locally."
  @spec sign_and_submit_locally(String.t(), options()) ::
          {:ok, %{digest: String.t()}} | {:error, term()}
  def sign_and_submit_locally(kind_bytes_b64, opts)
      when is_binary(kind_bytes_b64) and is_list(opts),
      do: TransactionOps.sign_and_submit_locally(kind_bytes_b64, opts)

  @doc "Fetches tribe names from the World API and caches them in ETS."
  @spec resolve_tribe_names(options()) :: {:ok, [world_tribe()]} | {:error, term()}
  def resolve_tribe_names(opts) when is_list(opts), do: Discovery.resolve_tribe_names(opts)

  @doc "Returns a cached tribe name or nil."
  @spec get_tribe_name(non_neg_integer(), options()) :: world_tribe() | nil
  def get_tribe_name(tribe_id, opts) when is_integer(tribe_id) and is_list(opts),
    do: Discovery.get_tribe_name(tribe_id, opts)

  @doc "Pins a reputation-derived standing override for a target tribe."
  @spec pin_standing(non_neg_integer(), standing_atom(), options()) :: :ok | {:error, term()}
  def pin_standing(target_tribe_id, standing, opts)
      when is_integer(target_tribe_id) and is_list(opts),
      do: ReputationOps.pin_standing(target_tribe_id, standing, opts)

  @doc "Clears a pinned standing override for a target tribe."
  @spec unpin_standing(non_neg_integer(), options()) :: :ok | {:error, term()}
  def unpin_standing(target_tribe_id, opts) when is_integer(target_tribe_id) and is_list(opts),
    do: ReputationOps.unpin_standing(target_tribe_id, opts)

  @doc "Returns true when the target tribe has a pinned standing override."
  @spec pinned?(non_neg_integer(), options()) :: boolean()
  def pinned?(target_tribe_id, opts) when is_integer(target_tribe_id) and is_list(opts),
    do: ReputationOps.pinned?(target_tribe_id, opts)

  @doc "Returns the cached reputation score entry for the target tribe."
  @spec get_reputation_score(non_neg_integer(), options()) :: reputation_score() | nil
  def get_reputation_score(target_tribe_id, opts)
      when is_integer(target_tribe_id) and is_list(opts),
      do: ReputationOps.get_reputation_score(target_tribe_id, opts)

  @doc "Lists all cached reputation score entries for the active source tribe."
  @spec list_reputation_scores(options()) :: [reputation_score()]
  def list_reputation_scores(opts) when is_list(opts),
    do: ReputationOps.list_reputation_scores(opts)

  @doc "Builds transaction kind bytes for setting the custodian oracle address."
  @spec set_oracle_address(non_neg_integer(), String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :invalid_oracle_address | :no_active_custodian | :no_character_ref | term()}
  def set_oracle_address(tribe_id, oracle_address, opts)
      when is_integer(tribe_id) and is_binary(oracle_address) and is_list(opts),
      do: TransactionOps.set_oracle_address(tribe_id, oracle_address, opts)

  @doc "Builds transaction kind bytes for removing the custodian oracle address."
  @spec remove_oracle_address(non_neg_integer(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def remove_oracle_address(tribe_id, opts) when is_integer(tribe_id) and is_list(opts),
    do: TransactionOps.remove_oracle_address(tribe_id, opts)

  @doc "Returns true when the active custodian has an oracle configured."
  @spec oracle_enabled?(options()) :: boolean()
  def oracle_enabled?(opts) when is_list(opts) do
    case get_active_custodian(opts) do
      %{oracle_address: oracle_address} when is_binary(oracle_address) -> true
      _other -> false
    end
  end

  @doc "Returns the standings ETS table from opts. Used by Diplomacy submodules."
  @spec standings_table(options()) :: Cache.table_id()
  def standings_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:standings)
  end

  @doc "Returns the source tribe ID from opts. Used by Diplomacy submodules."
  @spec source_tribe_id(options()) :: non_neg_integer()
  def source_tribe_id(opts) do
    case Keyword.fetch(opts, :tribe_id) do
      {:ok, tribe_id} -> tribe_id
      :error -> raise KeyError, key: :tribe_id, term: opts
    end
  end

  @spec active_tribe_id(custodian_info(), options()) :: non_neg_integer()
  defp active_tribe_id(custodian, opts),
    do: Map.get(custodian, :tribe_id, Keyword.fetch!(opts, :tribe_id))

  @doc "Fetches the active custodian or returns an error. Used by Diplomacy submodules."
  @spec require_active_custodian(options()) ::
          {:ok, custodian_info()} | {:error, :no_active_custodian}
  def require_active_custodian(opts) do
    case get_active_custodian(opts) do
      nil -> {:error, :no_active_custodian}
      active_custodian -> {:ok, active_custodian}
    end
  end

  @doc "Resolves the character ref from opts or chain. Used by Diplomacy submodules."
  @spec require_character_ref(options()) :: {:ok, character_ref()} | {:error, term()}
  def require_character_ref(opts) do
    cond do
      character_ref = Keyword.get(opts, :character_ref) ->
        {:ok, character_ref}

      character_id = Keyword.get(opts, :character_id) ->
        resolve_character_ref(character_id, opts)

      true ->
        {:error, :no_character_ref}
    end
  end

  @doc "Stores a pending transaction operation in the ETS cache. Used by Diplomacy submodules."
  @spec store_pending_tx(options(), String.t(), term()) :: :ok
  def store_pending_tx(opts, tx_bytes, operation) do
    Cache.put(standings_table(opts), {:pending_tx, tx_bytes}, operation)
  end
end
