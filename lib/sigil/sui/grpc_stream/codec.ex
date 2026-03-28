defmodule Sigil.Sui.GrpcStream.Codec do
  @moduledoc """
  Event filtering, normalization, and gRPC protobuf conversion for checkpoint streaming.
  """

  require Logger

  alias Sigil.Sui.Proto.{
    Checkpoint,
    Event,
    ExecutedTransaction,
    SubscribeCheckpointsResponse,
    TransactionEvents
  }

  @doc "Broadcasts all filtered transaction events from a checkpoint to PubSub."
  @spec broadcast_checkpoint_events(
          atom() | module(),
          String.t(),
          (map() -> boolean()),
          [map()],
          non_neg_integer()
        ) :: :ok
  def broadcast_checkpoint_events(pubsub, topic, event_filter_fun, transactions, sequence_number) do
    Enum.each(transactions, fn transaction ->
      case Map.fetch(transaction, "events") do
        {:ok, events} when is_list(events) ->
          Enum.each(events, fn event ->
            if event_filter_fun.(event) do
              broadcast_event(pubsub, topic, event, sequence_number)
            end
          end)

        _other ->
          :ok
      end
    end)

    :ok
  end

  @doc "Returns true only for reputation-relevant event types."
  @spec default_event_filter(map()) :: boolean()
  def default_event_filter(%{"type" => %{"repr" => type}}) when is_binary(type) do
    String.ends_with?(type, "KillmailCreatedEvent") or
      String.ends_with?(type, "JumpEvent") or
      String.ends_with?(type, "PriorityListUpdatedEvent")
  end

  def default_event_filter(_event), do: false

  @doc "Converts gRPC stream response items into normalized checkpoint payload maps."
  @spec normalize_stream_response(SubscribeCheckpointsResponse.t()) ::
          {:ok, map()} | {:error, term()}
  def normalize_stream_response(%SubscribeCheckpointsResponse{
        cursor: cursor,
        checkpoint: checkpoint
      })
      when is_integer(cursor) and not is_nil(checkpoint) do
    normalize_checkpoint(checkpoint, cursor)
  end

  def normalize_stream_response(%SubscribeCheckpointsResponse{
        checkpoint: %Checkpoint{sequence_number: cursor} = checkpoint
      })
      when is_integer(cursor) do
    normalize_checkpoint(checkpoint, cursor)
  end

  def normalize_stream_response(response) do
    Logger.warning("Malformed checkpoint stream response: #{inspect(response)}")
    {:error, :invalid_response}
  end

  @doc "Converts protobuf value messages into plain Elixir terms."
  @spec protobuf_value_to_term(Google.Protobuf.Value.t() | nil) :: term()
  def protobuf_value_to_term(nil), do: nil
  def protobuf_value_to_term(%Google.Protobuf.Value{kind: nil}), do: nil
  def protobuf_value_to_term(%Google.Protobuf.Value{kind: {:null_value, _value}}), do: nil
  def protobuf_value_to_term(%Google.Protobuf.Value{kind: {:number_value, value}}), do: value
  def protobuf_value_to_term(%Google.Protobuf.Value{kind: {:string_value, value}}), do: value
  def protobuf_value_to_term(%Google.Protobuf.Value{kind: {:bool_value, value}}), do: value

  def protobuf_value_to_term(%Google.Protobuf.Value{
        kind: {:struct_value, %Google.Protobuf.Struct{fields: fields}}
      })
      when is_map(fields) do
    Map.new(fields, fn {key, value} -> {key, protobuf_value_to_term(value)} end)
  end

  def protobuf_value_to_term(%Google.Protobuf.Value{
        kind: {:list_value, %Google.Protobuf.ListValue{values: values}}
      })
      when is_list(values) do
    Enum.map(values, &protobuf_value_to_term/1)
  end

  def protobuf_value_to_term(_value), do: nil

  @doc "Normalizes one protobuf event message into the internal event envelope shape."
  @spec normalize_event(Event.t()) :: map()
  def normalize_event(%Event{event_type: type, json: json}) do
    %{
      "type" => %{"repr" => type},
      "json" => protobuf_value_to_term(json)
    }
  end

  @doc "Normalizes one executed transaction into internal event envelope list shape."
  @spec normalize_transaction(ExecutedTransaction.t()) :: map()
  def normalize_transaction(%ExecutedTransaction{events: %TransactionEvents{events: events}})
      when is_list(events) do
    %{"events" => Enum.map(events, &normalize_event/1)}
  end

  def normalize_transaction(%ExecutedTransaction{}), do: %{"events" => []}

  @doc "Normalizes one checkpoint protobuf into the internal sequence+transactions payload."
  @spec normalize_checkpoint(Checkpoint.t(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def normalize_checkpoint(%Checkpoint{transactions: transactions}, cursor)
      when is_list(transactions) do
    {:ok,
     %{
       "sequenceNumber" => cursor,
       "transactions" => Enum.map(transactions, &normalize_transaction/1)
     }}
  end

  def normalize_checkpoint(checkpoint, _cursor) do
    Logger.warning("Malformed checkpoint payload from stream: #{inspect(checkpoint)}")
    {:error, :invalid_response}
  end

  @doc "Maps full Sui event type strings to local atom names."
  @spec event_name(String.t()) :: atom()
  def event_name(type) do
    cond do
      String.ends_with?(type, "KillmailCreatedEvent") -> :killmail_created
      String.ends_with?(type, "JumpEvent") -> :jump
      String.ends_with?(type, "PriorityListUpdatedEvent") -> :priority_list_updated
      true -> :unknown
    end
  end

  @doc "Normalizes known event payload variants into canonical parser keys."
  @spec normalize_event_payload(String.t(), map()) :: map()
  def normalize_event_payload(type, json) do
    cond do
      String.ends_with?(type, "KillmailCreatedEvent") -> normalize_killmail_payload(json)
      String.ends_with?(type, "JumpEvent") -> normalize_jump_payload(json)
      String.ends_with?(type, "PriorityListUpdatedEvent") -> normalize_priority_list_payload(json)
      true -> json
    end
  end

  @doc "Broadcasts a single filtered chain event to PubSub in parser-friendly format."
  @spec broadcast_event(atom() | module(), String.t(), map(), non_neg_integer()) :: :ok
  def broadcast_event(
        pubsub,
        topic,
        %{"type" => %{"repr" => type}, "json" => json},
        sequence_number
      )
      when is_binary(type) and is_map(json) do
    Phoenix.PubSub.broadcast(
      pubsub,
      topic,
      {:chain_event, event_name(type), normalize_event_payload(type, json), sequence_number}
    )
  end

  def broadcast_event(_pubsub, _topic, _event, _sequence_number), do: :ok

  @spec normalize_killmail_payload(map()) :: map()
  defp normalize_killmail_payload(json) do
    killer_id = first_present(json, ["killer_character_id", "killer"])
    victim_id = first_present(json, ["victim_character_id", "victim"])
    solar_system_id = first_present(json, ["solar_system_id", "solar_system"])

    json
    |> put_if_present("killer_character_id", killer_id)
    |> put_if_present("victim_character_id", victim_id)
    |> put_if_present("solar_system_id", solar_system_id)
    |> put_if_present("killer", killer_id)
    |> put_if_present("victim", victim_id)
    |> put_if_present("solar_system", solar_system_id)
  end

  @spec normalize_jump_payload(map()) :: map()
  defp normalize_jump_payload(json) do
    character_id = first_present(json, ["character_id", "character"])
    source_gate_id = first_present(json, ["source_gate_id", "source_gate"])
    destination_gate_id = first_present(json, ["destination_gate_id", "destination_gate"])

    json
    |> put_if_present("character_id", character_id)
    |> put_if_present("source_gate_id", source_gate_id)
    |> put_if_present("destination_gate_id", destination_gate_id)
    |> put_if_present("character", character_id)
    |> put_if_present("source_gate", source_gate_id)
    |> put_if_present("destination_gate", destination_gate_id)
  end

  @spec normalize_priority_list_payload(map()) :: map()
  defp normalize_priority_list_payload(json) do
    turret_id = first_present(json, ["turret_id", "turret"])

    aggressor_character_id =
      first_present(json, ["aggressor_character_id", "aggressor"]) ||
        aggressor_from_priority_list(Map.get(json, "priority_list"))

    json
    |> put_if_present("turret_id", turret_id)
    |> put_if_present("aggressor_character_id", aggressor_character_id)
    |> put_if_present("turret", turret_id)
    |> put_if_present("aggressor", aggressor_character_id)
  end

  @spec aggressor_from_priority_list(term()) :: String.t() | nil
  defp aggressor_from_priority_list(priority_list) when is_list(priority_list) do
    Enum.find_value(priority_list, fn
      %{"character_id" => character_id, "is_aggressor" => true} when is_binary(character_id) ->
        character_id

      %{"character" => character_id, "is_aggressor" => true} when is_binary(character_id) ->
        character_id

      _other ->
        nil
    end)
  end

  defp aggressor_from_priority_list(_priority_list), do: nil

  @spec first_present(map(), [String.t()]) :: term() | nil
  defp first_present(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} when not is_nil(value) -> value
        _other -> nil
      end
    end)
  end

  @spec put_if_present(map(), String.t(), term()) :: map()
  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
