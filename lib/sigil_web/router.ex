defmodule SigilWeb.Router do
  @moduledoc """
  Phoenix router for Sigil.

  Defines pipelines and route scopes for the application.
  The `:api` pipeline serves JSON endpoints and the `:browser`
  pipeline serves HTML/LiveView pages.
  """

  use SigilWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SigilWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SigilWeb do
    pipe_through :browser

    post "/session", SessionController, :create
    put "/session/character/:character_id", SessionController, :update_character
    delete "/session", SessionController, :delete

    live_session :wallet_session, on_mount: SigilWeb.WalletSession do
      live "/", DashboardLive
      live "/assembly/:id", AssemblyDetailLive
      live "/tribe/:tribe_id", TribeOverviewLive
      live "/tribe/:tribe_id/intel", IntelLive
      live "/tribe/:tribe_id/diplomacy", DiplomacyLive
    end
  end

  scope "/api", SigilWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  if Application.compile_env(:sigil, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SigilWeb.Telemetry
    end
  end
end
