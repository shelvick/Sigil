defmodule FrontierOS.MixProject do
  use Mix.Project

  def project do
    [
      app: :frontier_os,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {FrontierOS.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core framework
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_pubsub, "~> 2.1"},

      # Database
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},

      # HTTP server
      {:bandit, "~> 1.0"},

      # HTTP client + data
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},

      # Crypto (for Sui integration)
      {:blake2, "~> 1.0"},

      # Observability
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},

      # Development and test
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:hammox, "~> 0.7", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
