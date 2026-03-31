defmodule Sigil.Diplomacy.TransactionOps do
  @moduledoc """
  Transaction building and submission helpers for diplomacy operations.
  """

  alias Sigil.Cache
  alias Sigil.Diplomacy.{LocalSigner, ObjectCodec, PendingOps}
  alias Sigil.Sui.{TransactionBuilder, TxCustodian}

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @doc "Builds transaction kind bytes for setting a tribe standing."
  @spec build_set_standing_tx(
          non_neg_integer(),
          Sigil.Diplomacy.standing_value(),
          Sigil.Diplomacy.options()
        ) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_standing_tx(target_tribe_id, standing, opts)
      when is_integer(target_tribe_id) and is_integer(standing) and is_list(opts) do
    with {:ok, active_custodian} <- require_active_custodian(opts),
         {:ok, character_ref} <- require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_set_standing(character_ref, target_tribe_id, standing, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(
        opts,
        tx_bytes,
        {:set_standing, source_tribe_id(opts), target_tribe_id, standing}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for creating a custodian."
  @spec build_create_custodian_tx(Sigil.Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}} | {:error, :no_registry_ref | :no_character_ref | term()}
  def build_create_custodian_tx(opts) when is_list(opts) do
    with {:ok, registry_ref} <- Sigil.Diplomacy.resolve_registry_ref(opts),
         {:ok, character_ref} <- require_character_ref(opts) do
      tx_bytes =
        registry_ref
        |> TxCustodian.build_create_custodian(character_ref, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:create_custodian, Keyword.fetch!(opts, :tribe_id)})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting multiple tribe standings."
  @spec build_batch_set_standings_tx(
          [{non_neg_integer(), Sigil.Diplomacy.standing_value()}],
          Sigil.Diplomacy.options()
        ) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_batch_set_standings_tx(updates, opts) when is_list(updates) and is_list(opts) do
    with {:ok, active_custodian} <- require_active_custodian(opts),
         {:ok, character_ref} <- require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_batch_set_standings(character_ref, updates, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:batch_set_standings, source_tribe_id(opts), updates})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting a pilot standing."
  @spec build_set_pilot_standing_tx(
          String.t(),
          Sigil.Diplomacy.standing_value(),
          Sigil.Diplomacy.options()
        ) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_pilot_standing_tx(pilot, standing, opts)
      when is_binary(pilot) and is_integer(standing) and is_list(opts) do
    with {:ok, active_custodian} <- require_active_custodian(opts),
         {:ok, character_ref} <- require_character_ref(opts) do
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

      store_pending_tx(
        opts,
        tx_bytes,
        {:set_pilot_standing, source_tribe_id(opts), pilot, standing}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting the default standing."
  @spec build_set_default_standing_tx(Sigil.Diplomacy.standing_value(), Sigil.Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_set_default_standing_tx(standing, opts) when is_integer(standing) and is_list(opts) do
    with {:ok, active_custodian} <- require_active_custodian(opts),
         {:ok, character_ref} <- require_character_ref(opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_set_default_standing(character_ref, standing, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(opts, tx_bytes, {:set_default_standing, source_tribe_id(opts), standing})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for setting multiple pilot standings."
  @spec build_batch_set_pilot_standings_tx(
          [{String.t(), Sigil.Diplomacy.standing_value()}],
          Sigil.Diplomacy.options()
        ) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def build_batch_set_pilot_standings_tx(updates, opts) when is_list(updates) and is_list(opts) do
    with {:ok, active_custodian} <- require_active_custodian(opts),
         {:ok, character_ref} <- require_character_ref(opts) do
      encoded_updates =
        Enum.map(updates, fn {pilot, standing} -> {ObjectCodec.hex_to_bytes(pilot), standing} end)

      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_batch_set_pilot_standings(character_ref, encoded_updates, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(
        opts,
        tx_bytes,
        {:batch_set_pilot_standings, source_tribe_id(opts), updates}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Submits a wallet-signed transaction and updates cache on success."
  @spec submit_signed_transaction(String.t(), String.t(), Sigil.Diplomacy.options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}} | {:error, term()}
  def submit_signed_transaction(tx_bytes, signature, opts)
      when is_binary(tx_bytes) and is_binary(signature) and is_list(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    case client.execute_transaction(tx_bytes, [signature], req_options) do
      {:ok, %{"status" => "SUCCESS", "digest" => digest} = effects} ->
        pending_key = Keyword.get(opts, :kind_bytes, tx_bytes)
        PendingOps.apply(standings_table(opts), opts, pending_key)
        {:ok, %{digest: digest, effects_bcs: effects["effectsBcs"]}}

      {:ok, effects} ->
        {:error, {:tx_failed, effects}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Signs and submits a transaction locally."
  @spec sign_and_submit_locally(String.t(), Sigil.Diplomacy.options()) ::
          {:ok, %{digest: String.t()}} | {:error, term()}
  def sign_and_submit_locally(kind_bytes_b64, opts)
      when is_binary(kind_bytes_b64) and is_list(opts) do
    case LocalSigner.sign_and_submit(kind_bytes_b64) do
      {:ok, digest} ->
        PendingOps.apply(standings_table(opts), opts, kind_bytes_b64)
        {:ok, %{digest: digest}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Builds transaction kind bytes for setting the custodian oracle address."
  @spec set_oracle_address(non_neg_integer(), String.t(), Sigil.Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :invalid_oracle_address | :no_active_custodian | :no_character_ref | term()}
  def set_oracle_address(tribe_id, oracle_address, opts)
      when is_integer(tribe_id) and is_binary(oracle_address) and is_list(opts) do
    normalized_opts = Keyword.put(opts, :tribe_id, tribe_id)

    with :ok <- ensure_leader(normalized_opts),
         {:ok, active_custodian} <- require_active_custodian(normalized_opts),
         {:ok, character_ref} <- require_character_ref(normalized_opts),
         {:ok, oracle_address_bytes} <- decode_address(oracle_address) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_set_oracle(character_ref, oracle_address_bytes, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(normalized_opts, tx_bytes, {:set_oracle, tribe_id, oracle_address})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Builds transaction kind bytes for removing the custodian oracle address."
  @spec remove_oracle_address(non_neg_integer(), Sigil.Diplomacy.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :no_active_custodian | :no_character_ref | term()}
  def remove_oracle_address(tribe_id, opts) when is_integer(tribe_id) and is_list(opts) do
    normalized_opts = Keyword.put(opts, :tribe_id, tribe_id)

    with :ok <- ensure_leader(normalized_opts),
         {:ok, active_custodian} <- require_active_custodian(normalized_opts),
         {:ok, character_ref} <- require_character_ref(normalized_opts) do
      tx_bytes =
        active_custodian
        |> ObjectCodec.to_custodian_ref()
        |> TxCustodian.build_remove_oracle(character_ref, [])
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      store_pending_tx(normalized_opts, tx_bytes, {:remove_oracle, tribe_id})

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @spec standings_table(Sigil.Diplomacy.options()) :: Cache.table_id()
  defp standings_table(opts), do: opts |> Keyword.fetch!(:tables) |> Map.fetch!(:standings)

  @spec source_tribe_id(Sigil.Diplomacy.options()) :: non_neg_integer()
  defp source_tribe_id(opts), do: Keyword.fetch!(opts, :tribe_id)

  @spec require_active_custodian(Sigil.Diplomacy.options()) ::
          {:ok, Sigil.Diplomacy.custodian_info()} | {:error, :no_active_custodian}
  defp require_active_custodian(opts) do
    case Sigil.Diplomacy.get_active_custodian(opts) do
      nil -> {:error, :no_active_custodian}
      active_custodian -> {:ok, active_custodian}
    end
  end

  @spec require_character_ref(Sigil.Diplomacy.options()) ::
          {:ok, Sigil.Diplomacy.character_ref()} | {:error, term()}
  defp require_character_ref(opts) do
    case {Keyword.get(opts, :character_ref), Keyword.get(opts, :character_id)} do
      {character_ref, _character_id} when not is_nil(character_ref) ->
        {:ok, character_ref}

      {nil, character_id} when is_binary(character_id) ->
        Sigil.Diplomacy.resolve_character_ref(character_id, opts)

      _other ->
        {:error, :no_character_ref}
    end
  end

  @spec store_pending_tx(Sigil.Diplomacy.options(), String.t(), term()) :: :ok
  defp store_pending_tx(opts, tx_bytes, operation) do
    Cache.put(standings_table(opts), {:pending_tx, tx_bytes}, operation)
  end

  @spec decode_address(String.t()) :: {:ok, <<_::256>>} | {:error, :invalid_oracle_address}
  defp decode_address("0x" <> hex) when byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::256>> = bytes} -> {:ok, bytes}
      _other -> {:error, :invalid_oracle_address}
    end
  end

  defp decode_address(_address), do: {:error, :invalid_oracle_address}

  @spec ensure_leader(Sigil.Diplomacy.options()) :: :ok | {:error, :not_leader}
  defp ensure_leader(opts) do
    if Sigil.Diplomacy.leader?(opts), do: :ok, else: {:error, :not_leader}
  end
end
