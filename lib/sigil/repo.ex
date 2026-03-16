defmodule Sigil.Repo do
  @moduledoc """
  Ecto repository for Sigil.

  Provides database access to PostgreSQL via Ecto.
  """

  use Ecto.Repo,
    otp_app: :sigil,
    adapter: Ecto.Adapters.Postgres
end
