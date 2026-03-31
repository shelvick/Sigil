defmodule SigilWeb.StaticDataController do
  @moduledoc """
  Serves static game data as cacheable JSON for client-side rendering.
  """

  use SigilWeb, :controller

  alias Sigil.StaticData
  alias SigilWeb.CacheResolver
  alias SigilWeb.GalaxyMapLive.Data

  @doc "Returns solar systems and constellations for the galaxy map."
  @spec galaxy(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def galaxy(conn, _params) do
    case CacheResolver.application_static_data() do
      nil ->
        conn |> put_status(503) |> json(%{error: "static data unavailable"})

      static_data ->
        systems = StaticData.list_solar_systems(static_data)
        constellations = StaticData.list_constellations(static_data)

        conn
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> json(%{
          systems: Data.map_system_payload(systems),
          constellations: Data.map_constellation_payload(constellations)
        })
    end
  end
end
