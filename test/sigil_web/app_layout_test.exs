defmodule SigilWeb.AppLayoutTest do
  @moduledoc """
  Covers the app layout specification for the shared authenticated shell.
  """

  use Sigil.ConnCase, async: true

  alias Sigil.Accounts.Account
  alias Sigil.Sui.Types.Character

  @wallet_address "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd"

  # R1: Branding
  test "app layout shows Sigil branding" do
    html = render_layout(current_account: nil)

    assert html =~ ~r/>\s*Sigil\s*</
  end

  # R2: Dashboard link
  test "app layout includes dashboard link" do
    html = render_layout(current_account: nil)

    assert html =~ ~s(href="/")
    assert html =~ ~r/>\s*Dashboard\s*</
  end

  # R3: Wallet display
  test "app layout shows truncated wallet address when authenticated" do
    html = render_layout(current_account: account_fixture())

    assert html =~ "0x1234...abcd"
    refute html =~ @wallet_address
  end

  # R4: Disconnect
  test "app layout shows disconnect link when authenticated" do
    html = render_layout(current_account: account_fixture())

    assert html =~ ~r/>\s*Disconnect\s*</
    assert html =~ ~s(href="/session")
    assert html =~ "data-method=\"delete\""
  end

  # R5: Unauthenticated
  test "app layout hides wallet info when not authenticated" do
    html = render_layout(current_account: nil)

    refute html =~ "0x1234...abcd"
    refute html =~ ">Disconnect<"
    refute html =~ ">Wallet<"
  end

  # R6: Flash
  test "app layout renders flash group with dark theme styling" do
    html = render_layout(current_account: nil)

    assert html =~ ~s(id="flash-group")
    assert html =~ ~s(id="client-error")
    assert html =~ ~s(id="server-error")
    assert html =~ "bg-space-900/95"
    assert html =~ "border-warning/40"
    assert html =~ "backdrop-blur"
  end

  # R7: Content container
  test "app layout renders inner content in container" do
    html = render_layout(current_account: nil)

    assert html =~ "Inner Hull"
    assert html =~ "max-w-7xl px-4 sm:px-6 lg:px-8"
    assert html =~ ~s(<main class="pb-10 pt-6">)
  end

  # R8: Header shows active character name
  test "app layout header shows active character name" do
    character = character_fixture("0xchar-pilot", "Vega Solaris", 314)
    account = account_with_characters([character])

    html =
      render_layout(
        current_account: account,
        active_character: character
      )

    assert html =~ "Vega Solaris"
    refute html =~ "Commander"
  end

  # R8 edge case: character without metadata name falls back to "Commander"
  test "app layout header shows Commander fallback when character has no name" do
    character = character_fixture_no_name("0xchar-nameless", 42)
    account = account_with_characters([character])

    html =
      render_layout(
        current_account: account,
        active_character: character
      )

    assert html =~ "Commander"
    refute html =~ "Vega Solaris"
  end

  # R9: Header shows character's tribe badge
  test "app layout header shows active character tribe badge" do
    character = character_fixture("0xchar-tribal", "Anchor Holt", 271_828)
    account = account_with_characters([character])

    html =
      render_layout(
        current_account: account,
        active_character: character
      )

    assert html =~ "Tribe 271828"
    refute html =~ "Unaligned"
  end

  # R9 edge case: character with tribe_id 0 shows "Unaligned"
  test "app layout header shows Unaligned when character has tribe_id 0" do
    character = character_fixture("0xchar-loner", "Drift Kai", 0)
    account = account_with_characters([character])

    html =
      render_layout(
        current_account: account,
        active_character: character
      )

    assert html =~ "Unaligned"
    refute html =~ "Tribe 0"
  end

  # R10: Character dropdown shown when multiple characters
  test "app layout header shows character switcher for multi-character account" do
    first = character_fixture("0xchar-alpha", "Scout Vega", 314)
    second = character_fixture("0xchar-beta", "Marshal Iona", 271_828)
    account = account_with_characters([first, second])

    html =
      render_layout(
        current_account: account,
        active_character: first
      )

    # Both characters listed in the switcher
    assert html =~ "Scout Vega"
    assert html =~ "Marshal Iona"
    # Switcher links present for both characters
    assert html =~ "/session/character/#{first.id}"
    assert html =~ "/session/character/#{second.id}"
  end

  # R11: Character dropdown hidden when single character
  test "app layout header hides switcher for single-character account" do
    character = character_fixture("0xchar-solo", "Solo Rhea", 314)
    account = account_with_characters([character])

    html =
      render_layout(
        current_account: account,
        active_character: character
      )

    assert html =~ "Solo Rhea"
    # No switcher link should be present for a single character
    refute html =~ "/session/character/"
  end

  # R12: Character dropdown links to PUT /session/character/:id
  test "character switcher links to PUT /session/character endpoint" do
    first = character_fixture("0xchar-one", "First Pilot", 314)
    second = character_fixture("0xchar-two", "Second Pilot", 271)
    third = character_fixture("0xchar-three", "Third Pilot", 159)
    account = account_with_characters([first, second, third])

    html =
      render_layout(
        current_account: account,
        active_character: first
      )

    # Each non-active character has a PUT link
    assert html =~ "/session/character/#{second.id}"
    assert html =~ "/session/character/#{third.id}"
    # Links use PUT method
    assert html =~ ~s(method="put")
  end

  # R13: No character display when no characters
  test "app layout header hides character display when no characters" do
    account = account_fixture()

    html =
      render_layout(
        current_account: account,
        active_character: nil
      )

    # Still shows wallet and disconnect
    assert html =~ "0x1234...abcd"
    assert html =~ "Disconnect"
    # No character name or tribe displayed
    refute html =~ "Commander"
    refute html =~ "Unaligned"
    refute html =~ "/session/character/"
  end

  defp render_layout(assigns) do
    render_component(&SigilWeb.Layouts.app/1,
      inner_content: Phoenix.HTML.raw("<section>Inner Hull</section>"),
      flash: %{},
      current_account: assigns[:current_account],
      active_character: assigns[:active_character]
    )
  end

  defp account_fixture do
    %Account{address: @wallet_address, characters: [], tribe_id: nil}
  end

  defp account_with_characters(characters) do
    tribe_id =
      case characters do
        [%Character{tribe_id: tid} | _] -> tid
        [] -> nil
      end

    %Account{address: @wallet_address, characters: characters, tribe_id: tribe_id}
  end

  defp character_fixture(id, name, tribe_id) do
    %Character{
      id: id,
      key: %Sigil.Sui.Types.TenantItemId{item_id: "1", tenant: "0xtenant"},
      tribe_id: tribe_id,
      character_address: @wallet_address,
      metadata: %Sigil.Sui.Types.Metadata{
        assembly_id: "0xmeta-#{id}",
        name: name,
        description: "Test character",
        url: "https://example.test/characters/#{id}"
      },
      owner_cap_id: "0xowner-#{id}"
    }
  end

  defp character_fixture_no_name(id, tribe_id) do
    %Character{
      id: id,
      key: %Sigil.Sui.Types.TenantItemId{item_id: "1", tenant: "0xtenant"},
      tribe_id: tribe_id,
      character_address: @wallet_address,
      metadata: nil,
      owner_cap_id: "0xowner-#{id}"
    }
  end
end
