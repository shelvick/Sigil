defmodule Sigil.Sui.Client.HTTP.Paging do
  @moduledoc """
  Object/event query variable and pagination decoding helpers.
  """

  alias Sigil.Sui.Client
  alias Sigil.Sui.Client.HTTP.Codec

  @doc "Builds object query GraphQL variables from filter options."
  @spec object_variables(Client.object_filter(), pos_integer()) :: map()
  def object_variables(filters, default_limit) do
    {filter, after_cursor, limit} =
      Enum.reduce(filters, {%{}, nil, default_limit}, fn
        {:type, type}, {filter, after_cursor, limit} ->
          {Map.put(filter, "type", type), after_cursor, limit}

        {:owner, owner}, {filter, after_cursor, limit} ->
          {Map.put(filter, "owner", owner), after_cursor, limit}

        {:cursor, cursor}, {filter, _after_cursor, limit} ->
          {filter, cursor, limit}

        {:limit, page_size}, {filter, after_cursor, _limit} ->
          {filter, after_cursor, page_size}
      end)

    %{"filter" => filter, "after" => after_cursor, "first" => limit}
  end

  @doc "Builds normalized object pagination results from GraphQL response data."
  @spec build_objects_page(map()) ::
          {:ok, Client.objects_page()} | {:error, Client.error_reason()}
  def build_objects_page(%{"objects" => %{"pageInfo" => page_info, "nodes" => nodes}})
      when is_map(page_info) and is_list(nodes) do
    with {:ok, has_next_page} when is_boolean(has_next_page) <-
           Map.fetch(page_info, "hasNextPage"),
         {:ok, end_cursor} <- fetch_end_cursor(page_info),
         {:ok, object_data} <- extract_object_data(nodes) do
      {:ok, %{data: object_data, has_next_page: has_next_page, end_cursor: end_cursor}}
    else
      :error -> {:error, :invalid_response}
      {:error, :invalid_response} -> {:error, :invalid_response}
    end
  end

  def build_objects_page(_other), do: {:error, :invalid_response}

  @doc "Extracts endCursor while tolerating null pagination cursors."
  @spec fetch_end_cursor(map()) :: {:ok, String.t() | nil} | :error
  def fetch_end_cursor(page_info) do
    case Map.fetch(page_info, "endCursor") do
      {:ok, end_cursor} when is_binary(end_cursor) or is_nil(end_cursor) -> {:ok, end_cursor}
      _other -> :error
    end
  end

  @doc "Extracts move object JSON maps from GraphQL object nodes."
  @spec extract_object_data([map()]) ::
          {:ok, [Client.object_map()]} | {:error, Client.error_reason()}
  def extract_object_data(nodes) do
    reduced_nodes =
      Enum.reduce_while(nodes, {:ok, []}, fn
        %{"asMoveObject" => %{"contents" => %{"json" => object_json}}} = node, {:ok, acc}
        when is_map(object_json) ->
          {:cont, {:ok, [Codec.merge_owner_metadata(object_json, node) | acc]}}

        %{"asMoveObject" => nil}, {:ok, acc} ->
          {:cont, {:ok, acc}}

        _node, _acc ->
          {:halt, {:error, :invalid_response}}
      end)

    case reduced_nodes do
      {:ok, object_data} -> {:ok, Enum.reverse(object_data)}
      {:error, :invalid_response} = error -> error
    end
  end
end
