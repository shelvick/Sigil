defmodule SigilWeb.AppLayoutTest do
  @moduledoc """
  Covers the app layout specification for the shared authenticated shell.
  """

  use Sigil.ConnCase, async: true

  import Hammox

  alias Sigil.Accounts.Account
  alias Sigil.Cache
  alias Sigil.Sui.Types.Character

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:accounts, :characters, :assemblies]})
    pubsub = unique_pubsub_name()
    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok, cache_tables: Cache.tables(cache_pid), pubsub: pubsub}
  end

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

    assert html =~ "Scout Vega"
    assert html =~ "Marshal Iona"
    refute html =~ "/session/character/#{first.id}"
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

  # R12: Character dropdown links only non-active characters to PUT /session/character/:id
  test "character switcher links non-active characters to PUT endpoint" do
    first = character_fixture("0xchar-one", "First Pilot", 314)
    second = character_fixture("0xchar-two", "Second Pilot", 271)
    third = character_fixture("0xchar-three", "Third Pilot", 159)
    account = account_with_characters([first, second, third])

    html =
      render_layout(
        current_account: account,
        active_character: first
      )

    assert html =~ "/session/character/#{second.id}"
    assert html =~ "/session/character/#{third.id}"
    refute html =~ "/session/character/#{first.id}"
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

    assert html =~ "0x1234...abcd"
    assert html =~ "Disconnect"
    refute html =~ "Commander"
    refute html =~ "Unaligned"
    refute html =~ "/session/character/"
  end

  # R14: Alerts nav link shown when authenticated
  test "app layout header shows Alerts link when authenticated" do
    html = render_layout(current_account: account_fixture())

    assert html =~ ~r/>\s*Alerts\s*</
    assert html =~ ~s(href="/alerts")
  end

  # R15: Alerts nav link hidden when unauthenticated
  test "app layout header hides Alerts link when unauthenticated" do
    html = render_layout(current_account: nil)

    refute html =~ ~r/>\s*Alerts\s*</
    refute html =~ ~s(href="/alerts")
  end

  # R16: Alerts pill keeps shared nav ordering and styling
  test "app layout places alerts pill after dashboard and tribe links" do
    character = character_fixture("0xchar-nav-order", "Nav Pilot", 314)
    account = account_with_characters([character])

    html =
      render_layout(
        current_account: account,
        active_character: character
      )

    assert html =~ "Dashboard"
    assert html =~ "Tribe"
    assert html =~ "Alerts"
    assert html =~ "rounded-full border border-quantum-400/40"

    {dashboard_pos, _} = :binary.match(html, "Dashboard")
    {tribe_pos, _} = :binary.match(html, "Tribe")
    {alerts_pos, _} = :binary.match(html, "Alerts")

    assert dashboard_pos < tribe_pos
    assert tribe_pos < alerts_pos
  end

  test "app layout header shows Map link when authenticated" do
    html = render_layout(current_account: account_fixture())

    assert html =~ ~r/>\s*Map\s*</
    assert html =~ ~s(href="/map")
  end

  test "app layout header hides Map link when unauthenticated" do
    authenticated_html = render_layout(current_account: account_fixture())
    unauthenticated_html = render_layout(current_account: nil)

    assert authenticated_html =~ ~r/>\s*Map\s*</
    assert authenticated_html =~ ~s(href="/map")
    refute unauthenticated_html =~ ~r/>\s*Map\s*</
    refute unauthenticated_html =~ ~s(href="/map")
  end

  @tag :acceptance
  test "authenticated page renders shared shell with alerts and character controls", %{
    conn: conn,
    cache_tables: cache_tables,
    pubsub: pubsub
  } do
    wallet_address = unique_wallet_address()

    first =
      character_fixture_for_wallet("0xchar-acceptance-one", "Scout Vega", 314, wallet_address)

    second =
      character_fixture_for_wallet(
        "0xchar-acceptance-two",
        "Marshal Iona",
        271_828,
        wallet_address
      )

    account = %Account{address: wallet_address, characters: [first, second], tribe_id: 314}

    Cache.put(cache_tables.accounts, wallet_address, account)
    stub_empty_dashboard_discovery(first.id)

    conn =
      init_test_session(conn, %{
        "wallet_address" => wallet_address,
        "active_character_id" => first.id,
        "cache_tables" => cache_tables,
        "pubsub" => pubsub
      })

    assert {:ok, _view, html} = live(conn, "/")

    assert html =~ "Sigil"
    assert html =~ "Dashboard"
    assert html =~ "Alerts"
    assert html =~ "Scout Vega"
    assert html =~ "Marshal Iona"
    assert html =~ "/session/character/#{second.id}"
    refute html =~ "/session/character/#{first.id}"
    refute html =~ "Connect Your Wallet"
    refute html =~ "Not Found"
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
    character_fixture_for_wallet(id, name, tribe_id, @wallet_address)
  end

  defp character_fixture_for_wallet(id, name, tribe_id, wallet_address) do
    %Character{
      id: id,
      key: %Sigil.Sui.Types.TenantItemId{item_id: "1", tenant: "0xtenant"},
      tribe_id: tribe_id,
      character_address: wallet_address,
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

  defp stub_empty_dashboard_discovery(character_id) do
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: _type, owner: ^character_id], [] ->
      {:ok, %{data: [], has_next_page: false, end_cursor: nil}}
    end)
  end

  defp unique_pubsub_name do
    :"app_layout_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_wallet_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(64, "0")

    "0x" <> suffix
  end
end
