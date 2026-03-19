import Config

if config_env() != :test do
  if eve_world = System.get_env("EVE_WORLD") do
    config :sigil, :eve_world, eve_world
  end

  worlds = Application.get_env(:sigil, :eve_worlds, %{})
  localnet = Map.get(worlds, "localnet", %{})

  localnet =
    case System.get_env("SUI_LOCALNET_PACKAGE_ID") do
      nil -> localnet
      id -> %{localnet | package_id: id}
    end

  localnet =
    case System.get_env("SUI_LOCALNET_SIGIL_PACKAGE_ID") do
      nil -> localnet
      id -> %{localnet | sigil_package_id: id}
    end

  config :sigil, :eve_worlds, Map.put(worlds, "localnet", localnet)
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :sigil, Sigil.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      For example: sigil.gigalixirapp.com
      """

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :sigil, SigilWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
