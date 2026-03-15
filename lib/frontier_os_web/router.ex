defmodule FrontierOSWeb.Router do
  @moduledoc """
  Phoenix router for FrontierOS.

  Defines pipelines and route scopes for the application.
  The `:api` pipeline serves JSON endpoints and the `:browser`
  pipeline serves HTML/LiveView pages.
  """

  use FrontierOSWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FrontierOSWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FrontierOSWeb do
    pipe_through :browser

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete

    live_session :wallet_session, on_mount: FrontierOSWeb.WalletSession do
      live "/", DashboardLive
      live "/assembly/:id", AssemblyDetailLive
    end
  end

  scope "/api", FrontierOSWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  if Application.compile_env(:frontier_os, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FrontierOSWeb.Telemetry
    end
  end
end
