defmodule Sigil.Sui.Client.HTTP.DynamicFields do
  @moduledoc """
  GraphQL query and response parsing helpers for Sui dynamic field operations.

  Extracted from `Sigil.Sui.Client.HTTP` to keep the main client module focused
  on core object and transaction operations.
  """

  alias Sigil.Sui.Client

  @get_dynamic_fields_query """
  query GetDynamicFields($id: SuiAddress!, $first: Int, $after: String) {
    object(address: $id) {
      dynamicFields(first: $first, after: $after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          name {
            type {
              repr
            }
            json
          }
          value {
            ... on MoveValue {
              type {
                repr
              }
              json
            }
            ... on MoveObject {
              contents {
                type {
                  repr
                }
                json
              }
            }
          }
        }
      }
    }
  }
  """

  @doc "Returns the GraphQL query string for fetching dynamic fields."
  @spec query() :: String.t()
  def query, do: @get_dynamic_fields_query

  @doc "Builds a dynamic fields page from the GraphQL response data."
  @spec build_page(map()) ::
          {:ok, Client.dynamic_fields_page()} | {:error, Client.error_reason()}
  def build_page(%{"object" => nil}), do: {:error, :not_found}

  def build_page(%{"object" => %{"dynamicFields" => dynamic_fields}})
      when is_map(dynamic_fields) do
    with %{"pageInfo" => page_info, "nodes" => nodes} when is_map(page_info) and is_list(nodes) <-
           dynamic_fields,
         {:ok, has_next_page} when is_boolean(has_next_page) <-
           Map.fetch(page_info, "hasNextPage"),
         {:ok, end_cursor} <- fetch_end_cursor(page_info),
         {:ok, entries} <- extract_entries(nodes) do
      {:ok, %{data: entries, has_next_page: has_next_page, end_cursor: end_cursor}}
    else
      :error -> {:error, :invalid_response}
      {:error, :invalid_response} -> {:error, :invalid_response}
      _other -> {:error, :invalid_response}
    end
  end

  def build_page(_other), do: {:error, :invalid_response}

  # -- Private helpers --

  @spec fetch_end_cursor(map()) :: {:ok, String.t() | nil} | :error
  defp fetch_end_cursor(page_info) do
    case Map.fetch(page_info, "endCursor") do
      {:ok, end_cursor} when is_binary(end_cursor) or is_nil(end_cursor) -> {:ok, end_cursor}
      _other -> :error
    end
  end

  @spec extract_entries([map()]) ::
          {:ok, [Client.dynamic_field_entry()]} | {:error, Client.error_reason()}
  defp extract_entries(nodes) do
    reduced_nodes =
      Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
        case normalize_entry(node) do
          {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
          {:error, :invalid_response} = error -> {:halt, error}
        end
      end)

    case reduced_nodes do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, :invalid_response} = error -> error
    end
  end

  @spec normalize_entry(map()) ::
          {:ok, Client.dynamic_field_entry()} | {:error, Client.error_reason()}
  defp normalize_entry(%{"name" => name, "value" => value})
       when is_map(name) and is_map(value) do
    with {:ok, normalized_name} <- normalize_name(name),
         {:ok, normalized_value} <- normalize_value(value) do
      {:ok, %{name: normalized_name, value: normalized_value}}
    end
  end

  defp normalize_entry(_node), do: {:error, :invalid_response}

  @spec normalize_name(map()) ::
          {:ok, Client.dynamic_field_name()} | {:error, Client.error_reason()}
  defp normalize_name(%{"type" => %{"repr" => type}, "json" => json})
       when is_binary(type) do
    {:ok, %{type: type, json: json}}
  end

  defp normalize_name(_name), do: {:error, :invalid_response}

  @spec normalize_value(map()) ::
          {:ok, Client.dynamic_field_value()} | {:error, Client.error_reason()}
  defp normalize_value(%{"type" => %{"repr" => type}, "json" => json})
       when is_binary(type) do
    {:ok, %{type: type, json: json}}
  end

  defp normalize_value(%{
         "contents" => %{"type" => %{"repr" => type}, "json" => json}
       })
       when is_binary(type) do
    {:ok, %{type: type, json: json}}
  end

  defp normalize_value(_value), do: {:error, :invalid_response}
end
