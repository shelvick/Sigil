defmodule Sigil.StaticData.WorldApiTypesTest.WorldApiPlug do
  @moduledoc false

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(routes), do: routes

  @impl Plug
  def call(conn, routes) do
    conn = fetch_query_params(conn)

    case Map.fetch(routes, conn.request_path) do
      {:ok, {:paginated, records}} ->
        limit = conn.params["limit"] |> parse_integer(1_000)
        offset = conn.params["offset"] |> parse_integer(0)
        page_records = records |> Enum.drop(offset) |> Enum.take(limit)

        json(conn, 200, %{
          "data" => page_records,
          "metadata" => %{
            "total" => length(records),
            "limit" => limit,
            "offset" => offset
          }
        })

      {:ok, {:status, status, body}} ->
        json(conn, status, body)

      :error ->
        json(conn, 404, %{"error" => "not found"})
    end
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer(value, _default), do: String.to_integer(value)

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

defmodule Sigil.StaticData.WorldApiTypesTest do
  @moduledoc """
  Captures the packet 2 World API structs and client contract.
  """

  use ExUnit.Case, async: true

  import Hammox
  import Plug.Conn

  alias Sigil.StaticData.Constellation
  alias Sigil.StaticData.ItemType
  alias Sigil.StaticData.SolarSystem
  alias Sigil.StaticData.WorldClient
  alias Sigil.StaticData.WorldClient.HTTP, as: WorldClientHTTP
  alias Sigil.StaticData.WorldClientMock

  setup :verify_on_exit!

  describe "SolarSystem.from_json/1" do
    test "SolarSystem.from_json/1 parses valid API response" do
      solar_system = SolarSystem.from_json(solar_system_json())

      assert is_struct(solar_system, Sigil.StaticData.SolarSystem)
      assert solar_system.id == 30_000_001
      assert solar_system.name == "A 2560"
      assert solar_system.constellation_id == 20_000_001
      assert solar_system.region_id == 10_000_001
      assert solar_system.x == 1_234_567_890_123_456_789
      assert solar_system.y == -2_234_567_890_123_456_789
      assert solar_system.z == 3_234_567_890_123_456_789
    end

    test "SolarSystem.from_json/1 extracts nested location coordinates" do
      solar_system =
        SolarSystem.from_json(
          solar_system_json(%{
            "location" => %{"x" => 11, "y" => 22, "z" => 33}
          })
        )

      assert solar_system.x == 11
      assert solar_system.y == 22
      assert solar_system.z == 33
    end

    test "SolarSystem.from_json/1 raises on missing required field" do
      assert_raise KeyError, fn ->
        solar_system_json()
        |> Map.delete("constellationId")
        |> SolarSystem.from_json()
      end
    end
  end

  describe "ItemType.from_json/1" do
    test "ItemType.from_json/1 parses valid API response" do
      item_type = ItemType.from_json(item_type_json())

      assert is_struct(item_type, Sigil.StaticData.ItemType)
      assert item_type.id == 72_244
      assert item_type.name == "Feral Data"
      assert item_type.description == "Recovered datacore from frontier ruins"
      assert item_type.mass == 0.1
      assert item_type.radius == 1.0
      assert item_type.volume == 12.5
      assert item_type.portion_size == 1
      assert item_type.group_name == "Hull Repair Unit"
      assert item_type.group_id == 0
      assert item_type.category_name == "Module"
      assert item_type.category_id == 7
      assert item_type.icon_url == "https://images.example.test/72244.png"
    end

    test "ItemType.from_json/1 preserves empty string fields" do
      item_type =
        ItemType.from_json(
          item_type_json(%{
            "description" => "",
            "iconUrl" => ""
          })
        )

      assert item_type.description == ""
      assert item_type.icon_url == ""
    end

    test "ItemType.from_json/1 stores float mass and volume" do
      item_type =
        ItemType.from_json(
          item_type_json(%{
            "mass" => 0.1000000014901161,
            "volume" => 0.1000000014901161
          })
        )

      assert is_float(item_type.mass)
      assert is_float(item_type.volume)
      assert item_type.mass == 0.1000000014901161
      assert item_type.volume == 0.1000000014901161
    end
  end

  describe "Constellation.from_json/1" do
    test "Constellation.from_json/1 parses metadata and discards embedded solarSystems" do
      constellation = Constellation.from_json(constellation_json())

      assert is_struct(constellation, Sigil.StaticData.Constellation)
      assert constellation.id == 20_000_001
      assert constellation.name == "20000001"
      assert constellation.region_id == 10_000_001
      assert constellation.x == 4_234_567_890_123_456_789
      assert constellation.y == -5_234_567_890_123_456_789
      assert constellation.z == 6_234_567_890_123_456_789
      refute Map.has_key?(Map.from_struct(constellation), :solar_systems)
    end

    test "Constellation.from_json/1 extracts nested location coordinates" do
      constellation =
        Constellation.from_json(
          constellation_json(%{
            "location" => %{"x" => 44, "y" => 55, "z" => 66}
          })
        )

      assert constellation.x == 44
      assert constellation.y == 55
      assert constellation.z == 66
    end
  end

  describe "WorldClient behaviour and mock contract" do
    test "WorldClient module defines behaviour callbacks and error type" do
      callbacks = WorldClient.behaviour_info(:callbacks)
      {:ok, types} = Code.Typespec.fetch_types(WorldClient)

      assert {:fetch_types, 1} in callbacks
      assert {:fetch_solar_systems, 1} in callbacks
      assert {:fetch_constellations, 1} in callbacks

      type_names = Enum.map(types, fn {:type, {name, _, _}} -> name end)

      assert :error_reason in type_names
    end

    test "WorldClientMock implements WorldClient behaviour" do
      behaviours =
        WorldClientMock.module_info(:attributes)[:behaviour] || []

      assert WorldClient in behaviours
    end

    test "WorldClientMock satisfies WorldClient behaviour" do
      expect(WorldClientMock, :fetch_types, fn [] ->
        {:ok, %{id: 72_244}}
      end)

      assert_raise Hammox.TypeMatchError, fn ->
        WorldClientMock.fetch_types([])
      end
    end

    test "test environment uses WorldClientMock" do
      assert Application.fetch_env!(:sigil, :world_client) ==
               WorldClientMock
    end
  end

  describe "WorldClient.HTTP pagination and errors" do
    test "WorldClient.HTTP.fetch_types/1 returns all paginated records" do
      %{base_url: base_url} =
        start_world_api_server!(%{
          "/v2/types" => paginated_route(item_type_records(1_001))
        })

      assert {:ok, records} =
               WorldClientHTTP.fetch_types(base_url: base_url)

      assert length(records) == 1_001
      assert hd(records)["id"] == 70_001
      assert List.last(records)["id"] == 71_001
    end

    test "WorldClient.HTTP.fetch_solar_systems/1 returns all paginated records" do
      %{base_url: base_url} =
        start_world_api_server!(%{
          "/v2/solarsystems" => paginated_route(solar_system_records(1_001))
        })

      assert {:ok, records} =
               WorldClientHTTP.fetch_solar_systems(base_url: base_url)

      assert length(records) == 1_001
      assert hd(records)["id"] == 30_000_001
      assert List.last(records)["id"] == 30_001_001
    end

    test "WorldClient.HTTP.fetch_constellations/1 returns all paginated records" do
      %{base_url: base_url} =
        start_world_api_server!(%{
          "/v2/constellations" => paginated_route(constellation_records(1_001))
        })

      assert {:ok, records} =
               WorldClientHTTP.fetch_constellations(base_url: base_url)

      assert length(records) == 1_001
      assert hd(records)["id"] == 20_000_001
      assert List.last(records)["id"] == 20_001_001
    end

    test "WorldClient.HTTP returns error tuple on non-200 response" do
      %{base_url: base_url} =
        start_world_api_server!(%{
          "/v2/types" => status_route(503, %{"error" => "service unavailable"})
        })

      assert {:error, {:http_error, 503}} =
               WorldClientHTTP.fetch_types(base_url: base_url)
    end

    test "WorldClient.HTTP retries transient page failures before succeeding" do
      stub_name = {:world_api_retry, System.unique_integer([:positive])}

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      Req.Test.expect(stub_name, fn conn ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{"error" => "temporary upstream failure"}))
      end)

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => [item_type_json()],
          "metadata" => %{"total" => 1, "limit" => 1_000, "offset" => 0}
        })
      end)

      assert {:ok, [record]} =
               WorldClientHTTP.fetch_types(req_options: [plug: {Req.Test, stub_name}])

      assert record["id"] == 72_244
      assert :ok = Req.Test.verify!(stub_name)
    end

    test "WorldClient.HTTP returns error on timeout" do
      stub_name = {:world_api_timeout, System.unique_integer([:positive])}

      Req.Test.stub(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               WorldClientHTTP.fetch_types(req_options: [plug: {Req.Test, stub_name}])
    end
  end

  defp start_world_api_server!(routes) do
    pid =
      start_supervised!(
        {Bandit, plug: {__MODULE__.WorldApiPlug, routes}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(pid)

    %{base_url: "http://127.0.0.1:#{port}", pid: pid}
  end

  defp paginated_route(records), do: {:paginated, records}
  defp status_route(status, body), do: {:status, status, body}

  defp solar_system_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 30_000_001,
        "name" => "A 2560",
        "constellationId" => 20_000_001,
        "regionId" => 10_000_001,
        "location" => %{
          "x" => 1_234_567_890_123_456_789,
          "y" => -2_234_567_890_123_456_789,
          "z" => 3_234_567_890_123_456_789
        }
      },
      overrides
    )
  end

  defp item_type_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 72_244,
        "name" => "Feral Data",
        "description" => "Recovered datacore from frontier ruins",
        "mass" => 0.1,
        "radius" => 1.0,
        "volume" => 12.5,
        "portionSize" => 1,
        "groupName" => "Hull Repair Unit",
        "groupId" => 0,
        "categoryName" => "Module",
        "categoryId" => 7,
        "iconUrl" => "https://images.example.test/72244.png"
      },
      overrides
    )
  end

  defp constellation_json(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 20_000_001,
        "name" => "20000001",
        "regionId" => 10_000_001,
        "location" => %{
          "x" => 4_234_567_890_123_456_789,
          "y" => -5_234_567_890_123_456_789,
          "z" => 6_234_567_890_123_456_789
        },
        "solarSystems" => [%{"id" => 30_000_001, "name" => "A 2560"}]
      },
      overrides
    )
  end

  defp item_type_records(count) do
    for index <- 0..(count - 1) do
      item_type_json(%{
        "id" => 70_001 + index,
        "name" => "Item #{index}",
        "description" => "Description #{index}",
        "iconUrl" => "https://images.example.test/#{70_001 + index}.png"
      })
    end
  end

  defp solar_system_records(count) do
    for index <- 0..(count - 1) do
      solar_system_json(%{
        "id" => 30_000_001 + index,
        "name" => "System #{index}",
        "constellationId" => 20_000_001 + rem(index, 3),
        "regionId" => 10_000_001 + rem(index, 2),
        "location" => %{
          "x" => 1_000 + index,
          "y" => 2_000 + index,
          "z" => 3_000 + index
        }
      })
    end
  end

  defp constellation_records(count) do
    for index <- 0..(count - 1) do
      constellation_json(%{
        "id" => 20_000_001 + index,
        "name" => Integer.to_string(20_000_001 + index),
        "regionId" => 10_000_001 + rem(index, 4),
        "location" => %{
          "x" => 4_000 + index,
          "y" => 5_000 + index,
          "z" => 6_000 + index
        },
        "solarSystems" => []
      })
    end
  end
end
