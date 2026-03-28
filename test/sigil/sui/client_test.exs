defmodule Sigil.Sui.ClientTest do
  @moduledoc """
  Verifies the packet 2 Sui client behaviour and Hammox mock contract.
  """

  use ExUnit.Case, async: true

  import Hammox

  setup :verify_on_exit!

  test "Client module defines behaviour callbacks and types" do
    callbacks = Sigil.Sui.Client.behaviour_info(:callbacks)
    {:ok, types} = Code.Typespec.fetch_types(Sigil.Sui.Client)

    assert {:get_object, 2} in callbacks
    assert {:get_object_with_ref, 2} in callbacks
    assert {:get_objects, 2} in callbacks
    assert {:get_dynamic_fields, 2} in callbacks
    assert {:execute_transaction, 3} in callbacks
    assert {:get_coins, 2} in callbacks

    type_names =
      Enum.map(types, fn {:type, {name, _, _}} -> name end)

    assert :error_reason in type_names
    assert :object_map in type_names
    assert :tx_effects in type_names
    assert :object_ref in type_names
    assert :object_with_ref in type_names
    assert :objects_page in type_names
    assert :object_filter_key in type_names
    assert :object_filter in type_names
    assert :request_opt in type_names
    assert :request_opts in type_names
    assert :dynamic_field_name in type_names
    assert :dynamic_field_value in type_names
    assert :dynamic_field_entry in type_names
    assert :dynamic_fields_page in type_names
    assert :coin_info in type_names
  end

  test "ClientMock implements Client behaviour" do
    behaviours = Sigil.Sui.ClientMock.module_info(:attributes)[:behaviour] || []

    assert Sigil.Sui.Client in behaviours
  end

  test "get_objects accepts request options and objects_page returns" do
    page = %{data: [%{"id" => "0x1"}], has_next_page: false, end_cursor: nil}
    opts = [url: "http://example.test/graphql", req_options: [plug: {Req.Test, :sui_stub}]]

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: "0x2::gate::Gate"], ^opts ->
      {:ok, page}
    end)

    assert Sigil.Sui.ClientMock.get_objects([type: "0x2::gate::Gate"], opts) == {:ok, page}
  end

  test "Hammox enforces return types on mock expectations" do
    expect(Sigil.Sui.ClientMock, :get_object, fn "0x123", [] ->
      {:ok, %{id: 123}}
    end)

    assert_raise Hammox.TypeMatchError, fn ->
      Sigil.Sui.ClientMock.get_object("0x123", [])
    end
  end

  test "Hammox enforces get_objects page return type" do
    opts = [url: "http://example.test/graphql", req_options: [plug: {Req.Test, :sui_stub}]]

    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: "0x2::gate::Gate"], ^opts ->
      {:ok, [%{"id" => "0x1"}]}
    end)

    assert_raise Hammox.TypeMatchError, fn ->
      Sigil.Sui.ClientMock.get_objects([type: "0x2::gate::Gate"], opts)
    end
  end

  test "Client module defines verify_zklogin_signature callback" do
    callbacks = Sigil.Sui.Client.behaviour_info(:callbacks)
    {:ok, types} = Code.Typespec.fetch_types(Sigil.Sui.Client)
    {:ok, callbacks_ast} = Code.Typespec.fetch_callbacks(Sigil.Sui.Client)

    assert {:verify_zklogin_signature, 5} in callbacks

    type_names =
      Enum.map(types, fn {:type, {name, _, _}} -> name end)

    assert :zklogin_intent_scope in type_names
    assert :zklogin_result in type_names

    verify_callback =
      Enum.find(callbacks_ast, fn
        {{:verify_zklogin_signature, 5}, _callback_ast} -> true
        _other -> false
      end)

    assert {{:verify_zklogin_signature, 5},
            [
              {:type, _, :fun,
               [
                 {:type, _, :product,
                  [
                    {:remote_type, _, [{:atom, _, String}, {:atom, _, :t}, []]},
                    {:remote_type, _, [{:atom, _, String}, {:atom, _, :t}, []]},
                    {:user_type, _, :zklogin_intent_scope, []},
                    {:remote_type, _, [{:atom, _, String}, {:atom, _, :t}, []]},
                    {:user_type, _, :request_opts, []}
                  ]},
                 {:type, _, :union,
                  [
                    {:type, _, :tuple, [{:atom, _, :ok}, {:user_type, _, :zklogin_result, []}]},
                    {:type, _, :tuple, [{:atom, _, :error}, {:user_type, _, :error_reason, []}]}
                  ]}
               ]}
            ]} = verify_callback
  end

  test "Hammox enforces return types on verify_zklogin_signature mock" do
    opts = [url: "http://example.test/graphql", req_options: [plug: {Req.Test, :sui_stub}]]

    expect(Sigil.Sui.ClientMock, :verify_zklogin_signature, fn "message-bytes",
                                                               "signature-bytes",
                                                               "PERSONAL_MESSAGE",
                                                               "0x123",
                                                               ^opts ->
      {:ok, true}
    end)

    assert_raise Hammox.TypeMatchError, fn ->
      Sigil.Sui.ClientMock.verify_zklogin_signature(
        "message-bytes",
        "signature-bytes",
        "PERSONAL_MESSAGE",
        "0x123",
        opts
      )
    end
  end

  test "Client module defines get_dynamic_fields callback" do
    callbacks = Sigil.Sui.Client.behaviour_info(:callbacks)
    {:ok, types} = Code.Typespec.fetch_types(Sigil.Sui.Client)
    {:ok, callbacks_ast} = Code.Typespec.fetch_callbacks(Sigil.Sui.Client)

    assert {:get_dynamic_fields, 2} in callbacks

    type_names =
      Enum.map(types, fn {:type, {name, _, _}} -> name end)

    assert :dynamic_field_name in type_names
    assert :dynamic_field_value in type_names
    assert :dynamic_field_entry in type_names
    assert :dynamic_fields_page in type_names

    dynamic_fields_callback =
      Enum.find(callbacks_ast, fn
        {{:get_dynamic_fields, 2}, _callback_ast} -> true
        _other -> false
      end)

    assert {{:get_dynamic_fields, 2},
            [
              {:type, _, :fun,
               [
                 {:type, _, :product,
                  [
                    {:remote_type, _, [{:atom, _, String}, {:atom, _, :t}, []]},
                    {:user_type, _, :request_opts, []}
                  ]},
                 {:type, _, :union,
                  [
                    {:type, _, :tuple,
                     [{:atom, _, :ok}, {:user_type, _, :dynamic_fields_page, []}]},
                    {:type, _, :tuple, [{:atom, _, :error}, {:user_type, _, :error_reason, []}]}
                  ]}
               ]}
            ]} = dynamic_fields_callback
  end

  test "Hammox enforces return types on get_dynamic_fields mock" do
    opts = [url: "http://example.test/graphql", req_options: [plug: {Req.Test, :sui_stub}]]

    expect(Sigil.Sui.ClientMock, :get_dynamic_fields, fn "0xparent", ^opts ->
      {:ok, [%{name: %{type: "u64", json: 1}, value: %{type: "u64", json: 2}}]}
    end)

    assert_raise Hammox.TypeMatchError, fn ->
      Sigil.Sui.ClientMock.get_dynamic_fields("0xparent", opts)
    end
  end

  test "Client module defines get_coins callback" do
    callbacks = Sigil.Sui.Client.behaviour_info(:callbacks)
    {:ok, types} = Code.Typespec.fetch_types(Sigil.Sui.Client)
    {:ok, callbacks_ast} = Code.Typespec.fetch_callbacks(Sigil.Sui.Client)

    assert {:get_coins, 2} in callbacks

    type_names =
      Enum.map(types, fn {:type, {name, _, _}} -> name end)

    assert :coin_info in type_names

    get_coins_callback =
      Enum.find(callbacks_ast, fn
        {{:get_coins, 2}, _callback_ast} -> true
        _other -> false
      end)

    assert {{:get_coins, 2},
            [
              {:type, _, :fun,
               [
                 {:type, _, :product,
                  [
                    {:remote_type, _, [{:atom, _, String}, {:atom, _, :t}, []]},
                    {:user_type, _, :request_opts, []}
                  ]},
                 {:type, _, :union,
                  [
                    {:type, _, :tuple,
                     [
                       {:atom, _, :ok},
                       {:type, _, :list, [{:user_type, _, :coin_info, []}]}
                     ]},
                    {:type, _, :tuple, [{:atom, _, :error}, {:user_type, _, :error_reason, []}]}
                  ]}
               ]}
            ]} = get_coins_callback
  end

  test "Hammox enforces return types on get_coins mock" do
    opts = [url: "http://example.test/graphql", req_options: [plug: {Req.Test, :sui_stub}]]

    expect(Sigil.Sui.ClientMock, :get_coins, fn "0x123", ^opts ->
      {:ok, [%{object_id: <<1>>, version: 7, digest: <<2::256>>, balance: 10_000_000}]}
    end)

    assert_raise Hammox.TypeMatchError, fn ->
      Sigil.Sui.ClientMock.get_coins("0x123", opts)
    end
  end

  test "test environment uses ClientMock" do
    assert Application.fetch_env!(:sigil, :sui_client) == Sigil.Sui.ClientMock
  end
end
