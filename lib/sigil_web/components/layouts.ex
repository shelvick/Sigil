defmodule SigilWeb.Layouts do
  @moduledoc """
  Layout components for Sigil.

  Embeds root and app layout templates used by the
  endpoint and LiveView rendering pipeline.
  """

  use SigilWeb, :html

  embed_templates "layouts/*"

  @spec character_display_name(Sigil.Sui.Types.Character.t()) :: String.t()
  defp character_display_name(%{metadata: %{name: name}}) when is_binary(name), do: name
  defp character_display_name(_character), do: "Commander"

  @spec character_tribe_label(Sigil.Sui.Types.Character.t()) :: String.t()
  defp character_tribe_label(%{tribe_id: 0}), do: "Unaligned"

  defp character_tribe_label(%{tribe_id: tribe_id}) when is_integer(tribe_id),
    do: "Tribe #{tribe_id}"

  defp character_tribe_label(_character), do: "Unaligned"
end
