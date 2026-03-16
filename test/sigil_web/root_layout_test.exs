defmodule SigilWeb.RootLayoutTest do
  @moduledoc """
  Covers the root layout specification for the shared document shell.
  """

  use Sigil.ConnCase, async: true

  test "root layout includes Google Font links" do
    html = render_root_layout("Command Deck")

    assert html =~ "fonts.googleapis.com"
    assert html =~ "Sometype+Mono:wght@400;700"
    assert html =~ "Space+Grotesk:wght@400;500;600;700"
  end

  test "root layout applies EVE Frontier body classes" do
    html = render_root_layout("Command Deck")

    assert html =~ "bg-space-950 text-cream font-sans antialiased min-h-screen"
  end

  test "root layout includes CSRF meta tag" do
    html = render_root_layout("Command Deck")

    assert html =~ "name=\"csrf-token\""
  end

  test "root layout renders page title with Sigil suffix" do
    html = render_root_layout("Mission Control")

    assert html =~ ~r/Mission Control\s*· Sigil/
    refute html =~ ~r/Mission Control\s*-\s*Sigil/
  end

  test "root layout includes CSS and JS asset references" do
    html = render_root_layout("Command Deck")

    assert html =~ "/assets/app.css"
    assert html =~ "/assets/app.js"
  end

  defp render_root_layout(page_title) do
    render_component(&SigilWeb.Layouts.root/1,
      inner_content: Phoenix.HTML.raw("<div>Command deck</div>"),
      page_title: page_title
    )
  end
end
