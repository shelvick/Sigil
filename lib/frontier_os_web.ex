defmodule FrontierOSWeb do
  @moduledoc """
  The entrypoint for defining your web interface.

  Provides helper macros for controllers, routers, LiveViews,
  LiveComponents, and HTML components used throughout the
  FrontierOS web layer.

  This can be used in your application as:

      use FrontierOSWeb, :controller
      use FrontierOSWeb, :live_view
      use FrontierOSWeb, :html
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
        layouts: [html: FrontierOSWeb.Layouts]

      import Plug.Conn

      unquote(html_helpers())
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
      import Phoenix.LiveView.Router

      unquote(verified_routes())
    end
  end

  @doc """
  Defines LiveView helpers for FrontierOSWeb LiveViews.
  """
  @spec live_view() :: Macro.t()
  def live_view do
    quote do
      use Phoenix.LiveView, layout: {FrontierOSWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  @doc """
  Defines LiveComponent helpers for FrontierOSWeb LiveComponents.
  """
  @spec live_component() :: Macro.t()
  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  @doc """
  Defines HTML component helpers for FrontierOSWeb components.
  """
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML

      use Gettext, backend: FrontierOSWeb.Gettext

      import FrontierOSWeb.CoreComponents

      alias Phoenix.LiveView.JS

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
        router: FrontierOSWeb.Router,
        statics: FrontierOSWeb.static_paths()
    end
  end

  @doc false
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
