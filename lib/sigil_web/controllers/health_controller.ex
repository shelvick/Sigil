defmodule SigilWeb.HealthController do
  @moduledoc """
  Health check controller for Sigil.

  Provides a simple health endpoint for load balancers and deployment health checks.
  """

  use SigilWeb, :controller

  @doc """
  Returns a 200 OK JSON response indicating the application is healthy.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
