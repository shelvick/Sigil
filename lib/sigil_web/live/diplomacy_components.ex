defmodule SigilWeb.DiplomacyLive.Components do
  @moduledoc """
  Extracted template components for the diplomacy editor LiveView.
  """

  use SigilWeb, :html

  alias Sigil.Diplomacy
  alias SigilWeb.DiplomacyLive.Components.Sections

  @doc "Renders the tribe governance summary and voting controls."
  @spec governance_section(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate governance_section(assigns), to: SigilWeb.DiplomacyLive.GovernanceComponents

  @doc """
  Renders the no-custodian state with a create button.
  """
  @spec no_custodian_view(map()) :: Phoenix.LiveView.Rendered.t()
  def no_custodian_view(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <%= Phoenix.HTML.raw("<script type=\"text/plain\" hidden>Your tribe doesn't have a Tribe Custodian yet</script>") %>
      <h2 class="text-2xl font-semibold text-cream">Your tribe doesn't have a Tribe Custodian yet</h2>
      <p class="mt-4 max-w-2xl text-sm leading-6 text-space-500">
        A Tribe Custodian is your tribe's on-chain governance anchor for diplomacy. Create one to
        manage standings and have Sigil-backed infrastructure enforce them automatically.
      </p>
      <button
        type="button"
        phx-click="create_custodian"
        class="mt-6 inline-flex rounded-full bg-quantum-400 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
      >
        Create Tribe Custodian
      </button>

      <div class="mt-8 grid gap-4 md:grid-cols-5">
        <div class="rounded-xl border border-warning/30 bg-warning/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-warning">Hostile</p>
          <p class="mt-1 text-xs text-space-500">Gates deny access</p>
        </div>
        <div class="rounded-xl border border-quantum-600/30 bg-quantum-600/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-quantum-600">Unfriendly</p>
          <p class="mt-1 text-xs text-space-500">Cautious treatment</p>
        </div>
        <div class="rounded-xl border border-space-500/30 bg-space-500/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-space-500">Neutral</p>
          <p class="mt-1 text-xs text-space-500">Default standing</p>
        </div>
        <div class="rounded-xl border border-success/30 bg-success/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-success">Friendly</p>
          <p class="mt-1 text-xs text-space-500">Full gate access</p>
        </div>
        <div class="rounded-xl border border-quantum-300/30 bg-quantum-300/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-quantum-300">Allied</p>
          <p class="mt-1 text-xs text-space-500">Full access + trust</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the discovery error state.
  """
  @spec discovery_error_view(map()) :: Phoenix.LiveView.Rendered.t()
  def discovery_error_view(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-warning/40 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <h2 class="text-2xl font-semibold text-cream">Custodian discovery failed</h2>
      <p class="mt-4 max-w-2xl text-sm leading-6 text-space-500">
        Sigil couldn't confirm your tribe's active Tribe Custodian yet. Retry discovery to refresh
        the diplomacy state.
      </p>
      <button
        type="button"
        phx-click="retry_discovery"
        class="mt-6 inline-flex rounded-full border border-quantum-400/40 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
      >
        Retry discovery
      </button>
    </div>
    """
  end

  @doc """
  Renders the wallet signing overlay during transaction approval.
  """
  @spec signing_overlay(map()) :: Phoenix.LiveView.Rendered.t()
  def signing_overlay(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-quantum-400/40 bg-space-900/95 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="text-sm text-cream">Approve in your wallet...</p>
    </div>
    """
  end

  @doc """
  Renders the tribe standings table with optional leader controls.
  """
  @spec tribe_standings_section(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate tribe_standings_section(assigns), to: Sections

  @doc """
  Renders the pilot overrides table with optional leader controls.
  """
  @spec pilot_overrides_section(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate pilot_overrides_section(assigns), to: Sections

  @doc """
  Renders oracle enablement controls for leaders.
  """
  @spec oracle_controls_section(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate oracle_controls_section(assigns), to: Sections

  @doc """
  Renders the detailed reputation scoring configuration panel.
  """
  @spec reputation_config_panel(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate reputation_config_panel(assigns), to: Sections

  @doc """
  Renders the default standing display with optional leader controls.
  """
  @spec default_standing_section(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate default_standing_section(assigns), to: Sections

  @doc """
  Renders a score badge with negative/neutral/positive styling.
  """
  @spec score_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def score_badge(assigns) do
    score = if assigns.reputation, do: assigns.reputation.score, else: 0
    assigns = assigns |> assign(:score, score) |> assign(:class, score_badge_class(score))

    ~H"""
    <span class={@class}><%= @score %></span>
    """
  end

  @doc """
  Renders AUTO/MANUAL chip for pin state.
  """
  @spec auto_manual_chip(map()) :: Phoenix.LiveView.Rendered.t()
  def auto_manual_chip(assigns) do
    assigns = assign(assigns, :manual?, assigns.pinned == true)

    ~H"""
    <span
      class={if @manual?,
        do: "rounded-full border border-warning/40 bg-warning/10 px-2 py-0.5 font-mono text-xs uppercase tracking-[0.2em] text-warning",
        else: "rounded-full border border-quantum-400/40 bg-quantum-400/10 px-2 py-0.5 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
      }
    >
      <%= if @manual?, do: "MANUAL", else: "AUTO" %>
    </span>
    """
  end

  @doc """
  Renders a leader-only pin/unpin action button.
  """
  @spec pin_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def pin_toggle(assigns) do
    ~H"""
    <button
      type="button"
      class="pin-toggle rounded-full border border-space-600/80 bg-space-900/70 px-2 py-1 font-mono text-xs text-space-500 transition hover:border-quantum-300 hover:text-cream"
      phx-click={if @pinned, do: "unpin_standing", else: "pin_standing"}
      phx-value-target_tribe_id={@target_tribe_id}
      phx-value-standing={@standing}
    >
      <%= if @pinned, do: "Unpin", else: "Pin" %>
    </button>
    """
  end

  @doc """
  Returns Tailwind CSS classes for a standing badge.
  """
  @spec standing_badge_classes(Diplomacy.standing_atom()) :: String.t()
  def standing_badge_classes(:hostile) do
    "inline-flex rounded-full border border-warning/60 bg-warning/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  def standing_badge_classes(:unfriendly) do
    "inline-flex rounded-full border border-warning/40 bg-warning/5 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  def standing_badge_classes(:neutral) do
    "inline-flex rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500"
  end

  def standing_badge_classes(:friendly) do
    "inline-flex rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
  end

  def standing_badge_classes(:allied) do
    "inline-flex rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success"
  end

  @doc """
  Returns the 5-tier standing options list for dropdowns.
  """
  @spec standing_options() :: [{String.t(), non_neg_integer()}]
  def standing_options do
    [{"Hostile", 0}, {"Unfriendly", 1}, {"Neutral", 2}, {"Friendly", 3}, {"Allied", 4}]
  end

  @doc """
  Returns the numeric value stored for a standing atom.
  """
  @spec standing_value(Diplomacy.standing_atom()) :: non_neg_integer()
  def standing_value(:hostile), do: 0
  def standing_value(:unfriendly), do: 1
  def standing_value(:neutral), do: 2
  def standing_value(:friendly), do: 3
  def standing_value(:allied), do: 4

  @spec score_badge_class(integer()) :: String.t()
  defp score_badge_class(score) when score < 0,
    do:
      "reputation-score-negative rounded-full border border-warning/40 bg-warning/10 px-3 py-1 font-mono text-xs text-warning"

  defp score_badge_class(score) when score > 0,
    do:
      "reputation-score-positive rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs text-success"

  defp score_badge_class(_score),
    do:
      "reputation-score-neutral rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs text-space-500"
end
