import Config

config :sigil, Sigil.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sigil_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Default port 4000; override with PORT env var (e.g., PORT=4001 iex -S mix phx.server)
config :sigil, SigilWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "lJ67NjKyPMcrM07BmbSO9tbFa0dZoME4oZ7EifJb4E6tMWJfdO8lDHkKBamvsy8Z",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:sigil, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:sigil, ~w(--watch)]}
  ]

config :sigil, SigilWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/sigil_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for LiveDashboard
config :sigil, dev_routes: true

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :logger, :console, format: "[$level] $message\n"
