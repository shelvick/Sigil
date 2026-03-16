defmodule SigilWeb.Endpoint do
  @moduledoc """
  Phoenix HTTP/WebSocket endpoint for Sigil.

  Handles incoming connections, serves static assets, parses request bodies,
  manages sessions, and routes requests to the router.
  """

  use Phoenix.Endpoint, otp_app: :sigil

  @session_options [
    store: :cookie,
    key: "_sigil_key",
    signing_salt: "Wd2r7kNp",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :sigil,
    gzip: false,
    only: SigilWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :sigil
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
  plug SigilWeb.Router
end
