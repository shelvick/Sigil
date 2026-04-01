defmodule Sigil.WorldsTest do
  @moduledoc """
  Verifies world configuration lookups and world-scoped topic naming.
  """

  use ExUnit.Case, async: true

  alias Sigil.Worlds

  test "default_world/0 returns configured world" do
    assert Worlds.default_world() == "test"
  end

  test "active_worlds/0 returns configured worlds" do
    assert Worlds.active_worlds() == ["test"]
  end

  test "get!/1 returns world config" do
    assert %{package_id: package_id, sigil_package_id: sigil_package_id} = Worlds.get!("test")

    assert package_id ==
             "0x1111111111111111111111111111111111111111111111111111111111111111"

    assert sigil_package_id ==
             "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1"
  end

  test "package_id/1, sigil_package_id/1, graphql_url/1, and rpc_url/1 resolve values" do
    assert Worlds.package_id("test") ==
             "0x1111111111111111111111111111111111111111111111111111111111111111"

    assert Worlds.sigil_package_id("test") ==
             "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1"

    assert Worlds.graphql_url("test") == "http://test.invalid/graphql"
    assert Worlds.rpc_url("test") == "http://test.invalid/rpc"
  end

  test "optional world fields default to nil when missing" do
    assert Worlds.world_api_url("test") == nil
    assert Worlds.reputation_registry_id("test") == nil
  end

  test "topic/2 prefixes the base topic with world" do
    assert Worlds.topic("utopia", "diplomacy") == "utopia:diplomacy"
  end
end
