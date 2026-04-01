defmodule Sigil.IntelMarket.Reputation do
  @moduledoc """
  Reputation lookup and buyer feedback transaction helpers for intel marketplace listings.
  """

  alias Sigil.IntelMarket
  alias Sigil.Intel.IntelListing
  alias Sigil.Sui.TxIntelReputation
  alias Sigil.Worlds

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @doc "Returns seller reputation counters for listing-card display."
  @spec get_reputation(String.t(), IntelMarket.options()) ::
          {:ok, %{positive: non_neg_integer(), negative: non_neg_integer()}}
          | {:error, :reputation_unavailable}
  def get_reputation(seller_address, opts)
      when is_binary(seller_address) and is_list(opts) do
    with {:ok, registry_id} <- reputation_registry_id(opts),
         {:ok, registry_json} <- fetch_reputation_registry(registry_id, opts) do
      {:ok, reputation_for_seller(registry_json, seller_address)}
    else
      {:error, _reason} -> {:error, :reputation_unavailable}
    end
  end

  @doc "Returns whether feedback for a listing is already recorded for the seller."
  @spec feedback_recorded?(String.t(), String.t(), IntelMarket.options()) :: boolean()
  def feedback_recorded?(seller_address, listing_id, opts)
      when is_binary(seller_address) and is_binary(listing_id) and is_list(opts) do
    with {:ok, registry_id} <- reputation_registry_id(opts),
         {:ok, registry_json} <- fetch_reputation_registry(registry_id, opts),
         {:ok, score} <- score_for_seller(registry_json, seller_address) do
      reviewed_listing?(score, listing_id)
    else
      _other -> false
    end
  end

  @doc "Builds buyer feedback transaction bytes for a positive quality confirmation."
  @spec build_confirm_quality_tx(String.t(), IntelMarket.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error,
             :listing_not_found
             | :listing_not_sold
             | :already_reviewed
             | :reputation_unavailable
             | term()}
  def build_confirm_quality_tx(listing_id, opts) when is_binary(listing_id) and is_list(opts) do
    build_feedback_tx(listing_id, :confirm_quality, opts)
  end

  @doc "Builds buyer feedback transaction bytes for a negative quality report."
  @spec build_report_bad_quality_tx(String.t(), IntelMarket.options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error,
             :listing_not_found
             | :listing_not_sold
             | :already_reviewed
             | :reputation_unavailable
             | term()}
  def build_report_bad_quality_tx(listing_id, opts)
      when is_binary(listing_id) and is_list(opts) do
    build_feedback_tx(listing_id, :report_bad_quality, opts)
  end

  @spec build_feedback_tx(
          String.t(),
          :confirm_quality | :report_bad_quality,
          IntelMarket.options()
        ) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error,
             :listing_not_found
             | :listing_not_sold
             | :already_reviewed
             | :reputation_unavailable
             | term()}
  defp build_feedback_tx(listing_id, action, opts) do
    case IntelMarket.get_listing(listing_id, opts) do
      %IntelListing{} = listing ->
        with :ok <- ensure_sold_listing(listing),
             false <- feedback_recorded?(listing.seller_address, listing.id, opts),
             {:ok, registry_ref} <- resolve_reputation_registry_ref(opts),
             {:ok, listing_ref} <- IntelMarket.resolve_listing_ref(listing.id, opts),
             {:ok, tx_bytes} <-
               build_feedback_bytes(action, registry_ref, listing_ref, opts) do
          {:ok, %{tx_bytes: tx_bytes}}
        else
          true -> {:error, :already_reviewed}
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, :listing_not_found}
    end
  end

  @spec ensure_sold_listing(IntelListing.t()) :: :ok | {:error, :listing_not_sold}
  defp ensure_sold_listing(%IntelListing{status: :sold}), do: :ok
  defp ensure_sold_listing(%IntelListing{}), do: {:error, :listing_not_sold}

  @spec resolve_reputation_registry_ref(IntelMarket.options()) ::
          {:ok, TxIntelReputation.registry_ref()} | {:error, :reputation_unavailable}
  defp resolve_reputation_registry_ref(opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, registry_id} <- reputation_registry_id(opts),
         {:ok, %{ref: {object_id, version, _digest}}} <-
           client.get_object_with_ref(registry_id, req_options),
         true <- is_binary(object_id) and byte_size(object_id) == 32 and is_integer(version) do
      {:ok, %{object_id: object_id, initial_shared_version: version}}
    else
      _other -> {:error, :reputation_unavailable}
    end
  end

  @spec build_feedback_bytes(
          :confirm_quality | :report_bad_quality,
          TxIntelReputation.registry_ref(),
          IntelMarket.listing_ref(),
          IntelMarket.options()
        ) :: {:ok, String.t()}
  defp build_feedback_bytes(:confirm_quality, registry_ref, listing_ref, opts) do
    tx_bytes =
      registry_ref
      |> TxIntelReputation.build_confirm_quality(listing_ref, tx_opts(opts))
      |> Sigil.Sui.TransactionBuilder.build_kind!()
      |> Base.encode64()

    {:ok, tx_bytes}
  end

  defp build_feedback_bytes(:report_bad_quality, registry_ref, listing_ref, opts) do
    tx_bytes =
      registry_ref
      |> TxIntelReputation.build_report_bad_quality(listing_ref, tx_opts(opts))
      |> Sigil.Sui.TransactionBuilder.build_kind!()
      |> Base.encode64()

    {:ok, tx_bytes}
  end

  @spec fetch_reputation_registry(String.t(), IntelMarket.options()) ::
          {:ok, map()} | {:error, term()}
  defp fetch_reputation_registry(registry_id, opts) do
    client = Keyword.get(opts, :client, @sui_client)
    req_options = Keyword.get(opts, :req_options, [])

    case client.get_object(registry_id, req_options) do
      {:ok, registry_json} when is_map(registry_json) -> {:ok, registry_json}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_response}
    end
  end

  @spec reputation_for_seller(map(), String.t()) :: %{
          positive: non_neg_integer(),
          negative: non_neg_integer()
        }
  defp reputation_for_seller(registry_json, seller_address) do
    case score_for_seller(registry_json, seller_address) do
      {:ok, score} ->
        %{
          positive: parse_non_neg_integer(score_value(score, "positive")),
          negative: parse_non_neg_integer(score_value(score, "negative"))
        }

      :error ->
        %{positive: 0, negative: 0}
    end
  end

  @spec score_for_seller(map(), String.t()) :: {:ok, map()} | :error
  defp score_for_seller(registry_json, seller_address) do
    seller_key = normalize_address(seller_address)

    registry_json
    |> score_entries()
    |> Enum.find_value(:error, fn entry ->
      case parse_score_entry(entry) do
        {entry_address, score} ->
          if normalize_address(entry_address) == seller_key, do: {:ok, score}, else: nil

        _other ->
          nil
      end
    end)
  end

  @spec score_entries(map()) :: [term()]
  defp score_entries(registry_json) do
    registry_json
    |> field_value("scores")
    |> unwrap_collection()
  end

  @spec parse_score_entry(term()) :: {String.t(), map()} | :error
  defp parse_score_entry(%{"key" => key, "value" => value}) when is_binary(key) and is_map(value),
    do: {key, unwrap_struct(value)}

  defp parse_score_entry(%{key: key, value: value}) when is_binary(key) and is_map(value),
    do: {key, unwrap_struct(value)}

  defp parse_score_entry(%{"fields" => %{"key" => key, "value" => value}})
       when is_binary(key) and is_map(value),
       do: {key, unwrap_struct(value)}

  defp parse_score_entry({key, value}) when is_binary(key) and is_map(value),
    do: {key, unwrap_struct(value)}

  defp parse_score_entry(_entry), do: :error

  @spec reviewed_listing?(map(), String.t()) :: boolean()
  defp reviewed_listing?(score, listing_id) do
    target = normalize_object_id(listing_id)

    score
    |> field_value("reviewed_listings")
    |> unwrap_collection()
    |> Enum.any?(fn value -> normalize_object_id(extract_listing_id(value)) == target end)
  end

  @spec extract_listing_id(term()) :: String.t()
  defp extract_listing_id(value) when is_binary(value), do: value

  defp extract_listing_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_listing_id(%{id: id}) when is_binary(id), do: id

  defp extract_listing_id(%{"bytes" => bytes}) when is_binary(bytes), do: bytes
  defp extract_listing_id(%{bytes: bytes}) when is_binary(bytes), do: bytes

  defp extract_listing_id(%{"value" => value}), do: extract_listing_id(value)
  defp extract_listing_id(%{value: value}), do: extract_listing_id(value)

  defp extract_listing_id(other), do: to_string(other)

  @spec reputation_registry_id(IntelMarket.options()) ::
          {:ok, String.t()} | {:error, :reputation_unavailable}
  defp reputation_registry_id(opts) do
    case Keyword.get_lazy(opts, :reputation_registry_id, fn ->
           configured_reputation_registry_id(opts)
         end) do
      registry_id when is_binary(registry_id) and registry_id != "" -> {:ok, registry_id}
      _other -> {:error, :reputation_unavailable}
    end
  end

  @spec configured_reputation_registry_id(IntelMarket.options()) :: String.t() | nil
  defp configured_reputation_registry_id(opts) when is_list(opts) do
    opts
    |> world()
    |> Worlds.reputation_registry_id()
  end

  @spec world(IntelMarket.options()) :: Worlds.world_name()
  defp world(opts) when is_list(opts) do
    Keyword.get(opts, :world, Worlds.default_world())
  end

  @spec unwrap_struct(map()) :: map()
  defp unwrap_struct(%{"fields" => fields}) when is_map(fields), do: fields
  defp unwrap_struct(%{fields: fields}) when is_map(fields), do: fields
  defp unwrap_struct(map) when is_map(map), do: map

  @spec unwrap_collection(term()) :: [term()]
  defp unwrap_collection(nil), do: []
  defp unwrap_collection(list) when is_list(list), do: list

  defp unwrap_collection(map) when is_map(map) do
    cond do
      is_list(Map.get(map, "contents")) -> Map.get(map, "contents")
      is_list(Map.get(map, :contents)) -> Map.get(map, :contents)
      is_list(Map.get(map, "entries")) -> Map.get(map, "entries")
      is_list(Map.get(map, :entries)) -> Map.get(map, :entries)
      is_map(Map.get(map, "fields")) -> unwrap_collection(Map.get(map, "fields"))
      is_map(Map.get(map, :fields)) -> unwrap_collection(Map.get(map, :fields))
      true -> Map.to_list(map)
    end
  end

  defp unwrap_collection(_other), do: []

  @spec field_value(map(), String.t()) :: term()
  defp field_value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(map, String.to_existing_atom(key)) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  rescue
    ArgumentError ->
      nil
  end

  @spec score_value(map(), String.t()) :: term()
  defp score_value(score, key), do: field_value(score, key)

  @spec tx_opts(IntelMarket.options()) :: TxIntelReputation.tx_opts()
  defp tx_opts(opts) when is_list(opts) do
    [world: world(opts)]
  end

  @spec parse_non_neg_integer(term()) :: non_neg_integer()
  defp parse_non_neg_integer(value) when is_integer(value) and value >= 0, do: value

  defp parse_non_neg_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> 0
    end
  end

  defp parse_non_neg_integer(_value), do: 0

  @spec normalize_address(String.t()) :: String.t()
  defp normalize_address(address) when is_binary(address) do
    address
    |> String.trim()
    |> String.downcase()
  end

  @spec normalize_object_id(String.t()) :: String.t()
  defp normalize_object_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end
end
