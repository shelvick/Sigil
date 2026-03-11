defmodule FrontierOS.Repo do
  @moduledoc """
  Ecto repository for FrontierOS.

  Provides database access to PostgreSQL via Ecto.
  """

  use Ecto.Repo,
    otp_app: :frontier_os,
    adapter: Ecto.Adapters.Postgres
end
