defmodule SigilWeb.Layouts do
  @moduledoc """
  Layout components for Sigil.

  Embeds root and app layout templates used by the
  endpoint and LiveView rendering pipeline.
  """

  use SigilWeb, :html

  embed_templates "layouts/*"

  @spec truncate_wallet(String.t()) :: String.t()
  defp truncate_wallet("0x" <> _rest = wallet_address) when byte_size(wallet_address) > 10 do
    prefix = String.slice(wallet_address, 0, 6)
    suffix = String.slice(wallet_address, -4, 4)

    prefix <> "..." <> suffix
  end

  defp truncate_wallet(wallet_address) when is_binary(wallet_address), do: wallet_address
end
