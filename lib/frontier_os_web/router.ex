defmodule FrontierOSWeb.Router do
  @moduledoc """
  Phoenix router for FrontierOS.

  Defines pipelines and route scopes for the application.
  """

  use FrontierOSWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FrontierOSWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end
end
