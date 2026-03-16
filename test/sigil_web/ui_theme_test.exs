defmodule SigilWeb.UIThemeTest do
  @moduledoc """
  Covers the packet 1 UI theme specification by asserting the theme assets
  advertise the required palette, fonts, and base CSS hooks.
  """

  use Sigil.ConnCase, async: true

  @tailwind_config Path.expand("../../assets/tailwind.config.js", __DIR__)
  @app_css Path.expand("../../assets/css/app.css", __DIR__)

  test "tailwind config defines the EVE Frontier palette" do
    config = File.read!(@tailwind_config)

    # space-* background scale
    assert config =~ ~r/space:\s*\{[\s\S]*?950:\s*"#0A0A0A"/
    assert config =~ ~r/space:\s*\{[\s\S]*?900:\s*"#120B06"/
    assert config =~ ~r/space:\s*\{[\s\S]*?600:\s*"#373737"/
    assert config =~ ~r/space:\s*\{[\s\S]*?500:\s*"#737373"/

    # quantum-* accent scale (spec-defined token names)
    assert config =~ ~r/quantum:\s*\{[\s\S]*?300:\s*"#FFD580"/
    assert config =~ ~r/quantum:\s*\{[\s\S]*?400:\s*"#FFB829"/
    assert config =~ ~r/quantum:\s*\{[\s\S]*?500:\s*"#E8863A"/
    assert config =~ ~r/quantum:\s*\{[\s\S]*?600:\s*"#C74A06"/
    assert config =~ ~r/quantum:\s*\{[\s\S]*?700:\s*"#381B0C"/
    assert config =~ ~r/quantum:\s*\{[\s\S]*?800:\s*"#5C3421"/

    # Named tokens
    assert config =~ ~r/cream:\s*"#FFFFD6"/
    assert config =~ ~r/foreground:\s*"#FAFAFA"/
    assert config =~ ~r/success:\s*"#22C55E"/
    assert config =~ ~r/warning:\s*"#F59E0B"/

    refute config =~ ~r/"#00b4d8"/
  end

  test "tailwind config maps the EVE Frontier font families" do
    config = File.read!(@tailwind_config)

    assert config =~ ~r/fontFamily:\s*\{[\s\S]*sans:\s*\[[^\]]*"Space Grotesk"/
    assert config =~ ~r/fontFamily:\s*\{[\s\S]*mono:\s*\[[^\]]*"Sometype Mono"/
  end

  test "app.css defines theme variables and base styling hooks" do
    css = File.read!(@app_css)

    assert css =~ ":root"
    assert css =~ "--space-950"
    assert css =~ "--space-700"
    assert css =~ "--cream"
    assert css =~ "--quantum-400"
    assert css =~ "--quantum-500"
    assert css =~ "--quantum-600"
    assert css =~ "--foreground"
    assert css =~ "::-webkit-scrollbar-thumb"
    assert css =~ "scrollbar-color"
  end

  @tag :acceptance
  test "home page renders the EVE Frontier theme shell", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/<body[^>]*bg-space-950[^>]*text-cream/
    assert html =~ "font-mono"
    refute html =~ "bg-gray-950 text-gray-100"
  end
end
