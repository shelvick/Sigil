defmodule FrontierOSWeb.Endpoint do
  @moduledoc """
  Phoenix HTTP/WebSocket endpoint for FrontierOS.

  Handles incoming connections, serves static assets, parses request bodies,
  manages sessions, and routes requests to the router.
  """

  use Phoenix.Endpoint, otp_app: :frontier_os

  @session_options [
    store: :cookie,
    key: "_frontier_os_key",
    signing_salt: "Wd2r7kNp",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :frontier_os,
    gzip: false,
    only: FrontierOSWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :frontier_os
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FrontierOSWeb.Router
end
