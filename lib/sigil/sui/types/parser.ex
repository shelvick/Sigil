defmodule Sigil.Sui.Types.Parser do
  @moduledoc """
  Shared scalar parsers for Sui JSON payloads.
  """

  @doc "Parses a non-negative integer from a JSON scalar."
  @spec integer!(String.t() | non_neg_integer()) :: non_neg_integer()
  def integer!(value) when is_integer(value) and value >= 0, do: value

  def integer!(value) when is_binary(value) do
    parsed = String.to_integer(value)
    if parsed < 0, do: raise(ArgumentError, "expected non-negative integer, got: #{parsed}")
    parsed
  end

  @doc "Parses an optional value when present."
  @spec optional(term(), (term() -> parsed)) :: parsed | nil when parsed: var
  def optional(nil, _parser), do: nil
  def optional(value, parser) when is_function(parser, 1), do: parser.(value)

  @doc "Parses a byte vector from a binary or JSON list of bytes."
  @spec bytes!(binary() | [byte()]) :: binary()
  def bytes!(value) when is_binary(value), do: value
  def bytes!(value) when is_list(value), do: :erlang.list_to_binary(value)

  @doc "Unwraps a GraphQL UID field into its string id."
  @spec uid!(map() | String.t()) :: String.t()
  def uid!(%{"id" => value}) when is_binary(value), do: value
  def uid!(value) when is_binary(value), do: value

  @doc "Parses an assembly status enum into its atom form."
  @spec status!(String.t() | map()) :: :null | :offline | :online
  def status!(%{"@variant" => variant}), do: status!(variant)
  def status!("NULL"), do: :null
  def status!("OFFLINE"), do: :offline
  def status!("ONLINE"), do: :online

  def status!(value) do
    raise ArgumentError, "unknown assembly status: #{inspect(value)}"
  end
end
