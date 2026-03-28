defmodule Sigil.Diplomacy.PendingOps do
  @moduledoc """
  Applies cached diplomacy operations after a signed transaction succeeds.
  """

  alias Sigil.Cache
  alias Sigil.{Diplomacy, Diplomacy.ObjectCodec}

  @diplomacy_topic "diplomacy"

  @doc "Applies the pending operation keyed by the transaction bytes, if present."
  @spec apply(Cache.table_id(), keyword(), String.t()) :: :ok
  def apply(table, opts, tx_bytes) when is_binary(tx_bytes) do
    case take_pending_op(table, tx_bytes) do
      {:set_standing, source_tribe_id, target_tribe_id, standing} ->
        Cache.put(table, {:tribe_standing, source_tribe_id, target_tribe_id}, standing)

        broadcast(
          opts,
          {:standing_updated,
           %{tribe_id: target_tribe_id, standing: ObjectCodec.standing_to_atom(standing)}}
        )

      {:set_pilot_standing, source_tribe_id, pilot, standing} ->
        Cache.put(table, {:pilot_standing, source_tribe_id, pilot}, standing)

        broadcast(
          opts,
          {:pilot_standing_updated,
           %{pilot: pilot, standing: ObjectCodec.standing_to_atom(standing)}}
        )

      {:set_default_standing, source_tribe_id, standing} ->
        Cache.put(table, {:default_standing, source_tribe_id}, standing)
        broadcast(opts, {:default_standing_updated, ObjectCodec.standing_to_atom(standing)})

      {:batch_set_standings, source_tribe_id, updates} ->
        Enum.each(updates, fn {target_tribe_id, standing} ->
          Cache.put(table, {:tribe_standing, source_tribe_id, target_tribe_id}, standing)

          broadcast(
            opts,
            {:standing_updated,
             %{tribe_id: target_tribe_id, standing: ObjectCodec.standing_to_atom(standing)}}
          )
        end)

      {:batch_set_pilot_standings, source_tribe_id, updates} ->
        Enum.each(updates, fn {pilot, standing} ->
          Cache.put(table, {:pilot_standing, source_tribe_id, pilot}, standing)

          broadcast(
            opts,
            {:pilot_standing_updated,
             %{pilot: pilot, standing: ObjectCodec.standing_to_atom(standing)}}
          )
        end)

      {:vote_leader, _candidate} ->
        refresh_governance_state(table, opts, tx_bytes)

      :claim_leadership ->
        refresh_governance_state(table, opts, tx_bytes)

      {:set_oracle, tribe_id, oracle_address} ->
        update_oracle_address(table, tribe_id, oracle_address)

      {:remove_oracle, tribe_id} ->
        update_oracle_address(table, tribe_id, nil)

      :create_custodian ->
        broadcast(opts, {:custodian_created, nil})

      nil ->
        :ok

      _unknown ->
        :ok
    end

    :ok
  end

  @spec refresh_governance_state(Cache.table_id(), keyword(), String.t()) :: :ok
  defp refresh_governance_state(table, opts, tx_bytes) do
    case governance_refresh_tribe_id(table, tx_bytes) do
      {:ok, tribe_id} ->
        case do_refresh_governance_state(table, opts, tribe_id) do
          :ok ->
            clear_governance_pending_op(table, tx_bytes)
            Cache.delete(table, {:governance_refresh, tx_bytes})
            broadcast_governance_updated(opts, tribe_id)
            :ok

          {:error, :no_active_custodian} ->
            clear_governance_pending_op(table, tx_bytes)
            clear_governance_cache(opts, tribe_id)
            Cache.delete(table, {:governance_refresh, tx_bytes})
            broadcast_governance_updated(opts, tribe_id)
            :ok

          {:error, _reason} ->
            restore_governance_pending_op(table, tx_bytes)
            :ok
        end

      :error ->
        clear_governance_pending_op(table, tx_bytes)

        case Keyword.fetch(opts, :tribe_id) do
          {:ok, tribe_id} ->
            broadcast_governance_updated(opts, tribe_id)
            :ok

          :error ->
            :ok
        end
    end
  end

  @spec do_refresh_governance_state(Cache.table_id(), keyword(), non_neg_integer()) ::
          :ok | {:error, term()}
  defp do_refresh_governance_state(table, opts, tribe_id) do
    with :ok <- refresh_active_custodian(table, opts, tribe_id),
         {:ok, _governance_data} <- refresh_governance_cache(opts, tribe_id) do
      :ok
    end
  end

  @spec refresh_active_custodian(Cache.table_id(), keyword(), non_neg_integer()) ::
          :ok | {:error, term()}
  defp refresh_active_custodian(table, opts, tribe_id) do
    case Diplomacy.discover_custodian(tribe_id, opts) do
      {:ok, nil} ->
        Cache.delete(table, {:active_custodian, tribe_id})
        {:error, :no_active_custodian}

      {:ok, _custodian} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec update_oracle_address(Cache.table_id(), non_neg_integer(), String.t() | nil) :: :ok
  defp update_oracle_address(table, tribe_id, oracle_address) do
    case Cache.get(table, {:active_custodian, tribe_id}) do
      %{object_id: _, object_id_bytes: _, initial_shared_version: _, current_leader: _} =
          custodian ->
        Cache.put(
          table,
          {:active_custodian, tribe_id},
          Map.put(custodian, :oracle_address, oracle_address)
        )

      _other ->
        :ok
    end
  end

  @spec take_pending_op(Cache.table_id(), String.t()) :: term() | nil
  defp take_pending_op(table, tx_bytes) do
    case Cache.take(table, {:pending_tx, tx_bytes}) do
      {:vote_leader, _candidate} = pending_op ->
        Cache.put(table, {:pending_tx_inflight, tx_bytes}, pending_op)
        pending_op

      :claim_leadership = pending_op ->
        Cache.put(table, {:pending_tx_inflight, tx_bytes}, pending_op)
        pending_op

      pending_op ->
        pending_op
    end
  end

  @spec restore_governance_pending_op(Cache.table_id(), String.t()) :: :ok
  defp restore_governance_pending_op(table, tx_bytes) do
    case Cache.take(table, {:pending_tx_inflight, tx_bytes}) do
      nil -> :ok
      pending_op -> Cache.put(table, {:pending_tx, tx_bytes}, pending_op)
    end
  end

  @spec clear_governance_pending_op(Cache.table_id(), String.t()) :: :ok
  defp clear_governance_pending_op(table, tx_bytes) do
    Cache.delete(table, {:pending_tx_inflight, tx_bytes})
  end

  @spec governance_refresh_tribe_id(Cache.table_id(), String.t()) ::
          {:ok, non_neg_integer()} | :error
  defp governance_refresh_tribe_id(table, tx_bytes) do
    case Cache.get(table, {:governance_refresh, tx_bytes}) do
      tribe_id when is_integer(tribe_id) and tribe_id >= 0 -> {:ok, tribe_id}
      _other -> :error
    end
  end

  @spec refresh_governance_cache(keyword(), non_neg_integer()) ::
          {:ok, Diplomacy.governance_data()} | {:error, term()}
  defp refresh_governance_cache(opts, tribe_id) do
    Diplomacy.load_governance_data(Keyword.put(opts, :tribe_id, tribe_id))
  end

  @spec clear_governance_cache(keyword(), non_neg_integer()) :: :ok
  defp clear_governance_cache(opts, tribe_id) do
    Cache.delete(table(opts), {:governance_data, tribe_id})
  end

  @spec table(keyword()) :: Cache.table_id()
  defp table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:standings)
  end

  @spec broadcast(keyword(), term()) :: :ok | {:error, term()}
  defp broadcast(opts, event) do
    pubsub = Keyword.get(opts, :pubsub, Sigil.PubSub)
    Phoenix.PubSub.broadcast(pubsub, @diplomacy_topic, event)
  end

  @spec broadcast_governance_updated(keyword(), non_neg_integer()) :: :ok | {:error, term()}
  defp broadcast_governance_updated(opts, tribe_id) do
    pubsub = Keyword.get(opts, :pubsub, Sigil.PubSub)
    event = {:governance_updated, %{tribe_id: tribe_id}}
    Phoenix.PubSub.broadcast(pubsub, Diplomacy.topic(tribe_id), event)
  end
end
