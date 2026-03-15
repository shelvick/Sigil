import Config

config :frontier_os,
  ecto_repos: [FrontierOS.Repo]

config :frontier_os, :sui_client, FrontierOS.Sui.Client.HTTP
config :frontier_os, :world_client, FrontierOS.StaticData.WorldClient.HTTP

config :frontier_os, :eve_worlds, %{
  "stillness" => "0x28b497559d65ab320d9da4613bf2498d5946b2c0ae3597ccfda3072ce127448c",
  "utopia" => "0xd12a70c74c1e759445d6f209b01d43d860e97fcf2ef72ccbbd00afd828043f75",
  "internal" => "0x353988e063b4683580e3603dbe9e91fefd8f6a06263a646d43fd3a2f3ef6b8c1"
}

config :frontier_os, :eve_world, "stillness"

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

# Configure esbuild and tailwind (dev-only deps, skip in test)
if config_env() != :test do
  config :esbuild,
    version: "0.17.11",
    frontier_os: [
      args:
        ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]

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
