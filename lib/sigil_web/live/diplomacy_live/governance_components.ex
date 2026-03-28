defmodule SigilWeb.DiplomacyLive.GovernanceComponents do
  @moduledoc """
  LiveView function components for the tribe governance section: leader display,
  voting controls, and member vote tallies.

  Extracted from `SigilWeb.DiplomacyLive.Components` to keep component modules
  under 500 lines.
  """

  use SigilWeb, :html

  @doc """
  Renders the tribe governance summary and voting controls.
  """
  @spec governance_section(map()) :: Phoenix.LiveView.Rendered.t()
  def governance_section(assigns) do
    assigns =
      assigns
      |> assign(
        :leader_label,
        governance_label(assigns.active_custodian.current_leader, assigns.tribe_members)
      )
      |> assign(:member_rows, governance_member_rows(assigns))
      |> assign(:claim_available, claim_available?(assigns))

    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Tribe Governance</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Current Leader</h2>
          <p class="mt-2 text-sm text-space-500"><%= @leader_label %></p>
        </div>
        <div class="flex items-center gap-3">
          <span class="rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
            <%= @active_custodian.current_leader_votes %> votes
          </span>
          <button
            type="button"
            phx-click="toggle_governance"
            class="rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
          >
            <%= if @governance_expanded, do: "Hide Voting", else: "Show Voting" %>
          </button>
        </div>
      </div>

      <%= if @governance_error do %>
        <div class="mt-4 rounded-2xl border border-warning/40 bg-warning/5 p-4 text-sm text-warning">
          <%= @governance_error %>
        </div>
      <% end %>

      <%= if @governance_expanded and @governance_data do %>
        <div class="mt-6 space-y-4">
          <p :if={!@is_member} class="text-sm text-space-500">
            Your voting will register you as a governance participant.
          </p>

          <div class="space-y-3">
            <%= for row <- @member_rows do %>
              <div class="flex flex-col gap-3 rounded-2xl border border-space-600/60 bg-space-800/60 p-4 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <p class="font-semibold text-cream"><%= row.label %></p>
                  <p class="mt-1 text-sm text-space-500">Voted for <%= row.voted_for %></p>
                </div>
                <div class="flex items-center gap-3">
                  <span class="rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
                    <%= row.tally %> votes
                  </span>
                  <button
                    type="button"
                    phx-click="vote_leader"
                    phx-value-candidate={row.address}
                    class="rounded-full bg-quantum-400 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-space-950 transition hover:bg-quantum-300"
                  >
                    Vote
                  </button>
                </div>
              </div>
            <% end %>
          </div>

          <button
            :if={@claim_available}
            type="button"
            phx-click="claim_leadership"
            class="rounded-full border border-success/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-success transition hover:border-success hover:text-cream"
          >
            Claim Leadership
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # -- Private helpers --

  @spec governance_member_rows(map()) :: [map()]
  defp governance_member_rows(assigns) do
    assigns.active_custodian.members
    |> Enum.map(fn address ->
      voted_for = Map.get(assigns.governance_data.votes, address)

      %{
        address: address,
        label: governance_label(address, assigns.tribe_members),
        voted_for: governance_label(voted_for, assigns.tribe_members),
        tally: governance_tally(assigns, address)
      }
    end)
  end

  @spec governance_label(String.t() | nil, [map()]) :: String.t()
  defp governance_label(nil, _tribe_members), do: "No vote recorded"

  defp governance_label(address, tribe_members) do
    case Enum.find(
           tribe_members,
           &(&1.character_address == address or &1.wallet_address == address)
         ) do
      %{character_name: name} when is_binary(name) and byte_size(name) > 0 -> name
      _member -> String.slice(address, 0, 6)
    end
  end

  @spec governance_tally(map(), String.t()) :: non_neg_integer()
  defp governance_tally(%{governance_data: nil}, _address), do: 0

  defp governance_tally(assigns, address) do
    Map.get(assigns.governance_data.tallies, address, 0)
  end

  @spec claim_available?(map()) :: boolean()
  defp claim_available?(assigns) do
    viewer = Map.fetch!(assigns, :viewer_address)
    viewer_tally = governance_tally(assigns, viewer)
    leader_tally = governance_tally(assigns, assigns.active_custodian.current_leader)

    assigns.is_member and viewer_tally > leader_tally
  end
end
