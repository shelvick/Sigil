defmodule Sigil.Diplomacy.Governance do
  @moduledoc """
  TribeCustodian transaction builders and governance operations: standings CRUD,
  leader voting, leadership claims, membership queries, and on-chain governance
  data loading.

  Functions here are delegated from `Sigil.Diplomacy` so the public API is unchanged.
  """

  alias Sigil.Cache
  alias Sigil.Diplomacy
  alias Sigil.Diplomacy.ObjectCodec
  alias Sigil.Sui.{TransactionBuilder, TxCustodian}

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @doc "Builds transaction kind bytes for setting a tribe standing."
  @spec build_set_standing_tx(non_neg_integer(), Diplomacy.standing_value(), Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_standing_tx(target_tribe_id, standing, opts)
      when is_integer(target_tribe_id) and is_integer(standing) and is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_set_standing(character_ref, target_tribe_id, standing, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(
        opts,
        tx_bytes,
        {:set_standing, Diplomacy.source_tribe_id(opts), target_tribe_id, standing}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for creating a custodian."
  @spec build_create_custodian_tx(Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_registry_ref | :no_character_ref | term()}
  def build_create_custodian_tx(opts) when is_list(opts) do
    with {:ok, registry_ref} <- Diplomacy.resolve_registry_ref(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      tx_bytes =
        registry_ref
        |> TxCustodian.build_create_custodian(character_ref, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(opts, tx_bytes, :create_custodian)

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting multiple tribe standings."
  @spec build_batch_set_standings_tx(
          [{non_neg_integer(), Diplomacy.standing_value()}],
          Diplomacy.options()
        ) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_batch_set_standings_tx(updates, opts) when is_list(updates) and is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_batch_set_standings(character_ref, updates, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(
        opts,
        tx_bytes,
        {:batch_set_standings, Diplomacy.source_tribe_id(opts), updates}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting a pilot standing."
  @spec build_set_pilot_standing_tx(String.t(), Diplomacy.standing_value(), Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_pilot_standing_tx(pilot, standing, opts)
      when is_binary(pilot) and is_integer(standing) and is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_set_pilot_standing(
          character_ref,
          ObjectCodec.hex_to_bytes(pilot),
          standing,
          []
        )
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(
        opts,
        tx_bytes,
        {:set_pilot_standing, Diplomacy.source_tribe_id(opts), pilot, standing}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting the default standing."
  @spec build_set_default_standing_tx(Diplomacy.standing_value(), Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_default_standing_tx(standing, opts)
      when is_integer(standing) and is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_set_default_standing(character_ref, standing, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(
        opts,
        tx_bytes,
        {:set_default_standing, Diplomacy.source_tribe_id(opts), standing}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting multiple pilot standings."
  @spec build_batch_set_pilot_standings_tx(
          [{String.t(), Diplomacy.standing_value()}],
          Diplomacy.options()
        ) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_batch_set_pilot_standings_tx(updates, opts)
      when is_list(updates) and is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      encoded_updates =
        Enum.map(updates, fn {pilot, standing} -> {ObjectCodec.hex_to_bytes(pilot), standing} end)

      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_batch_set_pilot_standings(character_ref, encoded_updates, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(
        opts,
        tx_bytes,
        {:batch_set_pilot_standings, Diplomacy.source_tribe_id(opts), updates}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for voting for a leader candidate."
  @spec build_vote_leader_tx(String.t(), Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_vote_leader_tx(candidate, opts) when is_binary(candidate) and is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_vote_leader(character_ref, ObjectCodec.hex_to_bytes(candidate), [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(opts, tx_bytes, {:vote_leader, candidate})
      mark_governance_refresh(opts, tx_bytes)

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for claiming tribe leadership."
  @spec build_claim_leadership_tx(Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_claim_leadership_tx(opts) when is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, character_ref} <- Diplomacy.require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_claim_leadership(character_ref, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Diplomacy.store_pending_tx(opts, tx_bytes, :claim_leadership)
      mark_governance_refresh(opts, tx_bytes)

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Loads and caches governance votes and tallies for the active custodian."
  @spec load_governance_data(Diplomacy.options()) ::
          {:ok, Diplomacy.governance_data()} | {:error, term()}
  def load_governance_data(opts) when is_list(opts) do
    with {:ok, active_custodian} <- Diplomacy.require_active_custodian(opts),
         {:ok, votes} <- load_vote_map(active_custodian.votes_table_id, opts),
         {:ok, tallies} <- load_tally_map(active_custodian.vote_tallies_table_id, opts) do
      governance_data = %{votes: votes, tallies: tallies}

      Cache.put(
        Diplomacy.standings_table(opts),
        {:governance_data, Diplomacy.source_tribe_id(opts)},
        governance_data
      )

      {:ok, governance_data}
    end
  end

  @doc "Returns true when the sender is a member of the active custodian."
  @spec member?(Diplomacy.options()) :: boolean()
  def member?(opts) when is_list(opts) do
    case Diplomacy.get_active_custodian(opts) do
      %{members: members} -> Keyword.get(opts, :sender) in members
      _custodian -> false
    end
  end

  # -- Private helpers --

  @spec mark_governance_refresh(Diplomacy.options(), String.t()) :: :ok
  defp mark_governance_refresh(opts, tx_bytes) do
    Cache.put(
      Diplomacy.standings_table(opts),
      {:governance_refresh, tx_bytes},
      Diplomacy.source_tribe_id(opts)
    )
  end

  @spec load_vote_map(String.t(), Diplomacy.options()) ::
          {:ok, Diplomacy.vote_map()} | {:error, term()}
  defp load_vote_map(table_id, opts) do
    load_dynamic_field_map(table_id, opts, fn entry ->
      with %{name: %{json: voter}, value: %{json: candidate}} <- entry,
           true <- is_binary(voter) and is_binary(candidate) do
        {:ok, {voter, candidate}}
      else
        _invalid -> {:error, :invalid_response}
      end
    end)
  end

  @spec load_tally_map(String.t(), Diplomacy.options()) ::
          {:ok, Diplomacy.tally_map()} | {:error, term()}
  defp load_tally_map(table_id, opts) do
    load_dynamic_field_map(table_id, opts, fn entry ->
      with %{name: %{json: candidate}, value: %{json: tally}} <- entry,
           true <- is_binary(candidate),
           parsed_tally when is_integer(parsed_tally) and parsed_tally >= 0 <- parse_u64(tally) do
        {:ok, {candidate, parsed_tally}}
      else
        _invalid -> {:error, :invalid_response}
      end
    end)
  end

  @spec load_dynamic_field_map(String.t(), Diplomacy.options(), (map() ->
                                                                   {:ok, {term(), term()}}
                                                                   | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  defp load_dynamic_field_map(table_id, opts, entry_parser) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    do_load_dynamic_field_map(client, table_id, req_options, entry_parser, %{})
  end

  @spec do_load_dynamic_field_map(
          module(),
          String.t(),
          keyword(),
          (map() -> {:ok, {term(), term()}} | {:error, term()}),
          map()
        ) ::
          {:ok, map()} | {:error, term()}
  defp do_load_dynamic_field_map(client, table_id, req_options, entry_parser, acc) do
    with {:ok, page} <- client.get_dynamic_fields(table_id, req_options),
         {:ok, page_map} <- build_dynamic_field_page(page.data, entry_parser) do
      merged = Map.merge(acc, page_map)

      case page do
        %{has_next_page: true, end_cursor: cursor} when is_binary(cursor) ->
          do_load_dynamic_field_map(
            client,
            table_id,
            Keyword.put(req_options, :cursor, cursor),
            entry_parser,
            merged
          )

        _page ->
          {:ok, merged}
      end
    end
  end

  @spec build_dynamic_field_page([map()], (map() -> {:ok, {term(), term()}} | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  defp build_dynamic_field_page(entries, entry_parser) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, acc} ->
      case entry_parser.(entry) do
        {:ok, {key, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec parse_u64(non_neg_integer() | String.t()) :: non_neg_integer() | nil
  defp parse_u64(value) when is_integer(value) and value >= 0, do: value

  defp parse_u64(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _invalid -> nil
    end
  end

  defp parse_u64(_value), do: nil
end
