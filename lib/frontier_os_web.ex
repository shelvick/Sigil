defmodule FrontierOSWeb do
  @moduledoc """
  The entrypoint for defining your web interface.

  Provides helper macros for controllers, routers, and components
  used throughout the FrontierOS web layer.
  """

  @doc """
  Returns the list of static file paths served by the endpoint.
  """
  @spec static_paths() :: [String.t()]
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  @doc """
  Defines controller helpers for FrontierOSWeb controllers.
  """
  @spec controller() :: Macro.t()
  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: false]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @doc """
  Defines router helpers for FrontierOSWeb router.
  """
  @spec router() :: Macro.t()
  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller

      unquote(verified_routes())
    end
  end

  @doc """
  Defines verified routes for compile-time route checking.
  """
  @spec verified_routes() :: Macro.t()
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: FrontierOSWeb.Endpoint,
        router: FrontierOSWeb.Router
    end
  end

  @doc false
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
