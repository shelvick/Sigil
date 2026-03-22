defmodule Sigil.Diplomacy.PendingOps do
  @moduledoc """
  Applies cached diplomacy operations after a signed transaction succeeds.
  """

  alias Sigil.Cache
  alias Sigil.Diplomacy.ObjectCodec

  @diplomacy_topic "diplomacy"

  @doc "Applies the pending operation keyed by the transaction bytes, if present."
  @spec apply(Cache.table_id(), keyword(), String.t()) :: :ok
  def apply(table, opts, tx_bytes) when is_binary(tx_bytes) do
    case Cache.take(table, {:pending_tx, tx_bytes}) do
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

      :create_custodian ->
        broadcast(opts, {:custodian_created, nil})

      nil ->
        :ok
    end

    :ok
  end

  @spec broadcast(keyword(), term()) :: :ok | {:error, term()}
  defp broadcast(opts, event) do
    pubsub = Keyword.get(opts, :pubsub, Sigil.PubSub)
    Phoenix.PubSub.broadcast(pubsub, @diplomacy_topic, event)
  end
end
