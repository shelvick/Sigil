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
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:frontier_os, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:frontier_os, ~w(--watch)]}
  ]

config :frontier_os, FrontierOSWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/frontier_os_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for LiveDashboard
config :frontier_os, dev_routes: true

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :logger, :console, format: "[$level] $message\n"
