import Config

config :frontier_os,
  ecto_repos: [FrontierOS.Repo]

config :frontier_os, FrontierOSWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FrontierOSWeb.ErrorHTML, json: FrontierOSWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FrontierOS.PubSub,
  live_view: [signing_salt: "8kFm3xQr"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  frontier_os: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  frontier_os: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
