import Config

config :sigil, Sigil.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sigil_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test.
config :sigil, SigilWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_to_accept_it_ok",
  server: false

config :sigil, :sui_client, Sigil.Sui.ClientMock
config :sigil, :world_client, Sigil.StaticData.WorldClientMock
config :sigil, :eve_world, "test"

config :sigil, :eve_worlds, %{
  "test" => %{package_id: "0xtest_world", graphql_url: "http://test.invalid/graphql"}
}

config :sigil, :start_static_data, false
config :sigil, :world_client_retry_delay, 0
config :sigil, :sui_client_retry_delay, 0

config :logger, level: :error
