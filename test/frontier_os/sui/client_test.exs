defmodule FrontierOS.Sui.ClientTest do
  @moduledoc """
  Verifies the packet 2 Sui client behaviour and Hammox mock contract.
  """

  use ExUnit.Case, async: true

  import Hammox

  setup :verify_on_exit!

  test "Client module defines behaviour callbacks and types" do
    callbacks = FrontierOS.Sui.Client.behaviour_info(:callbacks)
    {:ok, types} = Code.Typespec.fetch_types(FrontierOS.Sui.Client)

    assert {:get_object, 2} in callbacks
    assert {:get_objects, 2} in callbacks
    assert {:execute_transaction, 3} in callbacks

    type_names =
      Enum.map(types, fn {:type, {name, _, _}} -> name end)

    assert :error_reason in type_names
    assert :object_map in type_names
    assert :tx_effects in type_names
    assert :object_filter_key in type_names
    assert :object_filter in type_names
    assert :request_opts in type_names
  end

  test "ClientMock implements Client behaviour" do
    behaviours = FrontierOS.Sui.ClientMock.module_info(:attributes)[:behaviour] || []

    assert FrontierOS.Sui.Client in behaviours
  end

  test "Hammox enforces return types on mock expectations" do
    expect(FrontierOS.Sui.ClientMock, :get_object, fn "0x123", [] ->
      {:ok, %{id: 123}}
    end)

    assert_raise Hammox.TypeMatchError, fn ->
      FrontierOS.Sui.ClientMock.get_object("0x123", [])
    end
  end

  test "test environment uses ClientMock" do
    assert Application.fetch_env!(:frontier_os, :sui_client) == FrontierOS.Sui.ClientMock
  end
end
