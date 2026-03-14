import Config

config :frontier_os,
  ecto_repos: [FrontierOS.Repo]

config :frontier_os, :sui_client, FrontierOS.Sui.Client.HTTP
config :frontier_os, :world_client, FrontierOS.StaticData.WorldClient.HTTP
config :frontier_os, :world_package_id, "0xworld"
config :frontier_os, :start_static_data, true

config :frontier_os, FrontierOSWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FrontierOSWeb.ErrorHTML, json: FrontierOSWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FrontierOS.PubSub,
  live_view: [signing_salt: "8kFm3xQr"]

# Configure asset builders only when those dev-only deps are present.
if Code.ensure_loaded?(Esbuild) do
  config :esbuild,
    version: "0.17.11",
    frontier_os: [
      args:
        ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]
end

if Code.ensure_loaded?(Tailwind) do
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
end

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
