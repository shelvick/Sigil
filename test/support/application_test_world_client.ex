defmodule Sigil.ApplicationTestWorldClient do
  @moduledoc """
  Returns static-data fixture payloads for spawned application snapshot probes.
  """

  @behaviour Sigil.StaticData.WorldClient

  alias Sigil.StaticDataTestFixtures, as: Fixtures

  @doc "Returns item type fixtures for application probe subprocesses."
  @impl true
  @spec fetch_types(keyword()) ::
          {:ok, [map()]} | {:error, Sigil.StaticData.WorldClient.error_reason()}
  def fetch_types(_opts), do: {:ok, Fixtures.item_type_records()}

  @doc "Returns solar system fixtures for application probe subprocesses."
  @impl true
  @spec fetch_solar_systems(keyword()) ::
          {:ok, [map()]} | {:error, Sigil.StaticData.WorldClient.error_reason()}
  def fetch_solar_systems(_opts), do: {:ok, Fixtures.solar_system_records()}

  @doc "Returns constellation fixtures for application probe subprocesses."
  @impl true
  @spec fetch_constellations(keyword()) ::
          {:ok, [map()]} | {:error, Sigil.StaticData.WorldClient.error_reason()}
  def fetch_constellations(_opts), do: {:ok, Fixtures.constellation_records()}
end
