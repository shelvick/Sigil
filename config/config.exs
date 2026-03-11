import Config

config :frontier_os,
  ecto_repos: [FrontierOS.Repo]

config :frontier_os, FrontierOSWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FrontierOSWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FrontierOS.PubSub,
  live_view: [signing_salt: "8kFm3xQr"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
