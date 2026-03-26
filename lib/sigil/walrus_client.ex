defmodule Sigil.WalrusClient do
  @moduledoc """
  Behaviour for Walrus blob storage operations.
  """

  @type store_result() :: {:ok, %{blob_id: String.t()}} | {:error, term()}
  @type read_result() :: {:ok, binary()} | {:error, :not_found | term()}

  @doc "Stores a blob for the requested number of Walrus epochs."
  @callback store_blob(binary(), pos_integer(), keyword()) :: store_result()

  @doc "Reads a blob payload from Walrus by blob id."
  @callback read_blob(String.t(), keyword()) :: read_result()

  @doc "Returns whether a blob is currently available from Walrus."
  @callback blob_exists?(String.t(), keyword()) :: boolean()
end
