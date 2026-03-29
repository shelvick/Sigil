defmodule Sigil.Release do
  @moduledoc """
  Release tasks for running Ecto migrations in production.

  Usage from a deployed release:

      _build/prod/rel/sigil/bin/sigil eval "Sigil.Release.migrate()"

  Or via Gigalixir:

      gigalixir run "bin/sigil eval 'Sigil.Release.migrate()'"
  """

  @app :sigil

  @doc "Runs all pending Ecto migrations."
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
