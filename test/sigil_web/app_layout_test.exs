defmodule SigilWeb.AppLayoutTest do
  @moduledoc """
  Covers the app layout specification for the shared authenticated shell.
  """

  use Sigil.ConnCase, async: true

  alias Sigil.Accounts.Account

  @wallet_address "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd"

  test "app layout shows Sigil branding" do
    html = render_layout(current_account: nil)

    assert html =~ ~r/>\s*Sigil\s*</
  end

  test "app layout includes dashboard link" do
    html = render_layout(current_account: nil)

    assert html =~ ~s(href="/")
    assert html =~ ~r/>\s*Dashboard\s*</
  end

  test "app layout shows truncated wallet address when authenticated" do
    html = render_layout(current_account: account_fixture())

    assert html =~ "0x1234...abcd"
    assert html =~ "Wallet"
    refute html =~ @wallet_address
  end

  test "app layout shows disconnect link when authenticated" do
    html = render_layout(current_account: account_fixture())

    assert html =~ ~r/>\s*Disconnect\s*</
    assert html =~ ~s(href="/session")
    assert html =~ "data-method=\"delete\""
  end

  test "app layout hides wallet info when not authenticated" do
    html = render_layout(current_account: nil)

    refute html =~ "0x1234...abcd"
    refute html =~ ">Disconnect<"
    refute html =~ ">Wallet<"
  end

  test "app layout renders flash group with dark theme styling" do
    html = render_layout(current_account: nil)

    assert html =~ ~s(id="flash-group")
    assert html =~ ~s(id="client-error")
    assert html =~ ~s(id="server-error")
    assert html =~ "bg-space-900/95"
    assert html =~ "border-warning/40"
    assert html =~ "backdrop-blur"
  end

  test "app layout renders inner content in container" do
    html = render_layout(current_account: nil)

    assert html =~ "Inner Hull"
    assert html =~ "max-w-7xl px-4 sm:px-6 lg:px-8"
    assert html =~ ~s(<main class="pb-10 pt-6">)
  end

  defp render_layout(assigns) do
    render_component(&SigilWeb.Layouts.app/1,
      inner_content: Phoenix.HTML.raw("<section>Inner Hull</section>"),
      flash: %{},
      current_account: assigns[:current_account]
    )
  end

  defp account_fixture do
    %Account{address: @wallet_address, characters: [], tribe_id: nil}
  end
end
