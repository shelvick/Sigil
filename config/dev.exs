import Config

config :frontier_os, FrontierOS.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "frontier_os_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Port 4000 is RESERVED for a critical live service — NEVER use it.
# FrontierOS dev server runs on port 4001.
config :frontier_os, FrontierOSWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "lJ67NjKyPMcrM07BmbSO9tbFa0dZoME4oZ7EifJb4E6tMWJfdO8lDHkKBamvsy8Z",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
