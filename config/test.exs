import Config

config :frontier_os, FrontierOS.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "frontier_os_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test.
config :frontier_os, FrontierOSWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_to_accept_it_ok",
  server: false

config :frontier_os, :sui_client, FrontierOS.Sui.ClientMock

config :logger, level: :warning
