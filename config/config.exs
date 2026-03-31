import Config

unpublished_package_id = "0x" <> String.duplicate("0", 64)

stillness_sigil_package_id =
  System.get_env("SUI_STILLNESS_SIGIL_PACKAGE_ID") || unpublished_package_id

utopia_sigil_package_id =
  System.get_env("SUI_UTOPIA_SIGIL_PACKAGE_ID") || unpublished_package_id

internal_sigil_package_id =
  System.get_env("SUI_INTERNAL_SIGIL_PACKAGE_ID") || unpublished_package_id

seal_key_server_object_ids =
  System.get_env("SEAL_KEY_SERVER_OBJECT_IDS", "")
  |> String.split(",", trim: true)

seal_threshold =
  System.get_env("SEAL_THRESHOLD") ||
    Integer.to_string(max(length(seal_key_server_object_ids), 1))

config :sigil,
  ecto_repos: [Sigil.Repo]

config :sigil, :sui_client, Sigil.Sui.Client.HTTP
config :sigil, :world_client, Sigil.StaticData.WorldClient.HTTP

config :sigil, :eve_worlds, %{
  "stillness" => %{
    package_id: "0x28b497559d65ab320d9da4613bf2498d5946b2c0ae3597ccfda3072ce127448c",
    sigil_package_id: stillness_sigil_package_id,
    graphql_url: "https://graphql.testnet.sui.io/graphql",
    rpc_url: "https://fullnode.testnet.sui.io:443",
    world_api_url: "https://world-api-stillness.live.tech.evefrontier.com"
  },
  "utopia" => %{
    package_id: "0xd12a70c74c1e759445d6f209b01d43d860e97fcf2ef72ccbbd00afd828043f75",
    sigil_package_id: utopia_sigil_package_id,
    graphql_url: "https://graphql.testnet.sui.io/graphql",
    rpc_url: "https://fullnode.testnet.sui.io:443",
    world_api_url: "https://world-api-utopia.uat.pub.evefrontier.com"
  },
  "internal" => %{
    package_id: "0x353988e063b4683580e3603dbe9e91fefd8f6a06263a646d43fd3a2f3ef6b8c1",
    sigil_package_id: internal_sigil_package_id,
    graphql_url: "https://graphql.testnet.sui.io/graphql",
    rpc_url: "https://fullnode.testnet.sui.io:443",
    world_api_url: "https://world-api-stillness.live.tech.evefrontier.com"
  },
  "localnet" => %{
    package_id: "must be set via SUI_LOCALNET_PACKAGE_ID env var",
    sigil_package_id: unpublished_package_id,
    graphql_url: "http://localhost:9125/graphql",
    rpc_url: "http://localhost:9000",
    world_api_url: "https://world-api-stillness.live.tech.evefrontier.com"
  }
}

config :sigil, :seal, %{
  key_server_object_ids: seal_key_server_object_ids,
  threshold: String.to_integer(seal_threshold),
  walrus_publisher_url:
    System.get_env("WALRUS_PUBLISHER_URL", "https://publisher.walrus-testnet.walrus.space"),
  walrus_aggregator_url:
    System.get_env("WALRUS_AGGREGATOR_URL", "https://aggregator.walrus-testnet.walrus.space"),
  walrus_epochs: String.to_integer(System.get_env("WALRUS_EPOCHS", "15")),
  sui_rpc_url: System.get_env("SUI_RPC_URL", "https://fullnode.testnet.sui.io:443")
}

config :sigil, :eve_world, "stillness"

config :sigil, :start_static_data, true
config :sigil, :start_monitor_supervisor, true
config :sigil, :start_assembly_event_router, false
config :sigil, :start_alert_engine, true
config :sigil, :monitor_registry, Sigil.GameState.MonitorRegistry
config :sigil, :webhook_notifier, Sigil.Alerts.WebhookNotifier.Discord

config :sigil, SigilWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SigilWeb.ErrorHTML, json: SigilWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sigil.PubSub,
  live_view: [signing_salt: "8kFm3xQr"]

# Configure esbuild and tailwind (dev-only deps, skip in test)
if config_env() != :test do
  config :esbuild,
    version: "0.17.11",
    sigil: [
      args:
        ~w(js/app.js --bundle --target=es2020 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]

  config :tailwind,
    version: "3.4.3",
    sigil: [
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
