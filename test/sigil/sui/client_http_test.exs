defmodule Sigil.Sui.ClientHTTPTest do
  @moduledoc """
  Captures the packet 1 Sui GraphQL HTTP client contract.
  """

  use ExUnit.Case, async: true

  import Plug.Conn

  alias Sigil.Sui.Client
  alias Sigil.Sui.Client.HTTP, as: ClientHTTP

  describe "get_object/2" do
    test "get_object returns parsed object JSON for valid address" do
      stub_name = stub_name(:get_object_success)
      object_json = %{"id" => "0xabc", "name" => "Gate Alpha"}

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)

        assert payload["query"] =~ "query GetObject"
        assert payload["variables"] == %{"id" => "0xabc"}

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0xabc",
              "asMoveObject" => %{"contents" => %{"json" => object_json}}
            }
          }
        })
      end)

      assert {:ok, ^object_json} =
               ClientHTTP.get_object("0xabc", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_object returns not_found for null object" do
      stub_name = stub_name(:get_object_not_found)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{"id" => "0xmissing"}
        Req.Test.json(conn, %{"data" => %{"object" => nil}})
      end)

      assert {:error, :not_found} =
               ClientHTTP.get_object("0xmissing", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_object returns graphql_errors when endpoint returns errors" do
      stub_name = stub_name(:get_object_graphql_errors)
      errors = [%{"message" => "bad query"}]

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{"id" => "0xabc"}
        Req.Test.json(conn, %{"errors" => errors})
      end)

      assert {:error, {:graphql_errors, ^errors}} =
               ClientHTTP.get_object("0xabc", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_object returns timeout on transport timeout" do
      stub_name = stub_name(:get_object_timeout)

      Req.Test.stub(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               ClientHTTP.get_object("0xabc", req_options: [plug: {Req.Test, stub_name}])
    end

    test "get_object returns rate_limited on HTTP 429" do
      stub_name = stub_name(:get_object_rate_limited)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{"id" => "0xabc"}
        json_response(conn, 429, %{"errors" => [%{"message" => "slow down"}]})
      end)

      assert {:error, :rate_limited} =
               ClientHTTP.get_object("0xabc", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_object returns invalid_response for malformed body" do
      stub_name = stub_name(:get_object_invalid_response)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{"id" => "0xabc"}
        Req.Test.json(conn, %{"data" => %{"object" => %{"address" => "0xabc"}}})
      end)

      assert {:error, :invalid_response} =
               ClientHTTP.get_object("0xabc", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end
  end

  describe "get_object_with_ref/2" do
    test "returns json and object ref tuple for valid object" do
      stub_name = stub_name(:get_object_with_ref_success)
      object_json = %{"id" => "0xabc123", "name" => "Gate Alpha"}
      # "3Acbb" is a short Base58 string; decoded = <<222, 173, 0>>
      # For a real 32-byte digest we use a known value
      digest_b58 = "11111111111111111111111111111111"
      # 32 '1' chars in Base58 = 32 zero bytes (each '1' = one leading zero byte)

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)
        assert payload["variables"] == %{"id" => "0xabc123"}

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0x" <> String.duplicate("ab", 32),
              "version" => 42,
              "digest" => digest_b58,
              "asMoveObject" => %{"contents" => %{"json" => object_json}}
            }
          }
        })
      end)

      assert {:ok, %{json: ^object_json, ref: {id_bytes, 42, digest_bytes}}} =
               ClientHTTP.get_object_with_ref("0xabc123",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert byte_size(id_bytes) == 32
      assert id_bytes == Base.decode16!(String.duplicate("ab", 32), case: :lower)
      assert byte_size(digest_bytes) == 32
      assert digest_bytes == <<0::256>>

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "merges initialSharedVersion from owner field for shared objects" do
      stub_name = stub_name(:get_object_with_ref_shared)
      object_json = %{"id" => "0xshared", "name" => "Shared Gate"}
      digest_b58 = "11111111111111111111111111111111"

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0x" <> String.duplicate("cc", 32),
              "version" => 10,
              "digest" => digest_b58,
              "owner" => %{"initialSharedVersion" => 5},
              "asMoveObject" => %{"contents" => %{"json" => object_json}}
            }
          }
        })
      end)

      assert {:ok, %{json: json}} =
               ClientHTTP.get_object_with_ref("0xshared",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert json["shared"] == %{"initialSharedVersion" => "5"}
      assert json["id"] == "0xshared"
    end

    test "does not merge owner metadata for non-shared objects" do
      stub_name = stub_name(:get_object_with_ref_owned)
      object_json = %{"id" => "0xowned", "name" => "Owned Cap"}
      digest_b58 = "11111111111111111111111111111111"

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0x" <> String.duplicate("dd", 32),
              "version" => 7,
              "digest" => digest_b58,
              "owner" => %{},
              "asMoveObject" => %{"contents" => %{"json" => object_json}}
            }
          }
        })
      end)

      assert {:ok, %{json: json}} =
               ClientHTTP.get_object_with_ref("0xowned",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      refute Map.has_key?(json, "shared")
    end

    test "returns not_found when object is null" do
      stub_name = stub_name(:get_object_with_ref_not_found)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{"id" => "0xmissing"}
        Req.Test.json(conn, %{"data" => %{"object" => nil}})
      end)

      assert {:error, :not_found} =
               ClientHTTP.get_object_with_ref("0xmissing",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "returns invalid_response for malformed version" do
      stub_name = stub_name(:get_object_with_ref_bad_version)

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0x" <> String.duplicate("ab", 32),
              "version" => "not-a-number",
              "digest" => "11111111111111111111111111111111",
              "asMoveObject" => %{"contents" => %{"json" => %{"id" => "0x1"}}}
            }
          }
        })
      end)

      assert {:error, :invalid_response} =
               ClientHTTP.get_object_with_ref("0x1",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "returns invalid_response for digest that is not 32 bytes" do
      stub_name = stub_name(:get_object_with_ref_bad_digest)
      # "2" in Base58 = single byte <<1>>, not 32 bytes
      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0x" <> String.duplicate("ab", 32),
              "version" => 42,
              "digest" => "2",
              "asMoveObject" => %{"contents" => %{"json" => %{"id" => "0x1"}}}
            }
          }
        })
      end)

      assert {:error, :invalid_response} =
               ClientHTTP.get_object_with_ref("0x1",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end
  end

  describe "get_objects/2" do
    test "get_objects returns page with data and page info" do
      stub_name = stub_name(:get_objects_success)

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)

        assert payload["query"] =~ "query GetObjects"

        assert payload["variables"] == %{
                 "after" => nil,
                 "filter" => %{"type" => "0x2::gate::Gate"},
                 "first" => 50
               }

        Req.Test.json(conn, %{
          "data" => %{
            "objects" => %{
              "pageInfo" => %{"hasNextPage" => true, "endCursor" => "cursor-1"},
              "nodes" => [
                %{
                  "address" => "0x1",
                  "asMoveObject" => %{
                    "contents" => %{"json" => %{"id" => "0x1", "name" => "Gate Alpha"}}
                  }
                },
                %{"address" => "0xpackage", "asMoveObject" => nil}
              ]
            }
          }
        })
      end)

      assert {:ok,
              %{
                data: [%{"id" => "0x1", "name" => "Gate Alpha"}],
                has_next_page: true,
                end_cursor: "cursor-1"
              }} =
               ClientHTTP.get_objects([type: "0x2::gate::Gate"],
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_objects passes cursor as after variable" do
      stub_name = stub_name(:get_objects_cursor)

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)

        assert payload["variables"] == %{"after" => "cursor-abc", "filter" => %{}, "first" => 50}

        Req.Test.json(conn, %{
          "data" => %{
            "objects" => %{
              "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
              "nodes" => []
            }
          }
        })
      end)

      assert {:ok, %{data: [], has_next_page: false, end_cursor: nil}} =
               ClientHTTP.get_objects([cursor: "cursor-abc"],
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_objects returns empty page for no matches" do
      stub_name = stub_name(:get_objects_empty)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "filter" => %{"owner" => "0xowner"},
                 "first" => 50
               }

        Req.Test.json(conn, %{
          "data" => %{
            "objects" => %{
              "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
              "nodes" => []
            }
          }
        })
      end)

      assert {:ok, %{data: [], has_next_page: false, end_cursor: nil}} =
               ClientHTTP.get_objects([owner: "0xowner"],
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_objects passes limit as first variable" do
      stub_name = stub_name(:get_objects_limit)

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)

        assert payload["variables"] == %{
                 "after" => nil,
                 "filter" => %{"owner" => "0xowner"},
                 "first" => 10
               }

        Req.Test.json(conn, %{
          "data" => %{
            "objects" => %{
              "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
              "nodes" => []
            }
          }
        })
      end)

      assert {:ok, %{data: [], has_next_page: false, end_cursor: nil}} =
               ClientHTTP.get_objects([owner: "0xowner", limit: 10],
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end
  end

  describe "execute_transaction/3" do
    test "execute_transaction returns normalized effects for successful submission" do
      stub_name = stub_name(:execute_transaction_success)

      Req.Test.expect(stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["method"] == "sui_executeTransactionBlock"

        assert payload["params"] == [
                 "tx-bytes",
                 ["sig-1"],
                 %{"showEffects" => true}
               ]

        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => %{
            "digest" => "tx-digest",
            "effects" => %{"status" => %{"status" => "success"}},
            "rawEffects" => "effects-bcs-b64"
          }
        })
      end)

      assert {:ok,
              %{
                "status" => "SUCCESS",
                "digest" => "tx-digest",
                "effectsBcs" => nil
              }} =
               ClientHTTP.execute_transaction("tx-bytes", ["sig-1"],
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "execute_transaction returns tx_failed on chain execution failure" do
      stub_name = stub_name(:execute_transaction_tx_failed)

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => %{
            "digest" => "failed-digest",
            "effects" => %{
              "status" => %{"status" => "failure", "error" => "InsufficientGas"}
            }
          }
        })
      end)

      assert {:error, {:tx_failed, "InsufficientGas"}} =
               ClientHTTP.execute_transaction("tx-bytes", ["sig-1"],
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "execute_transaction returns rpc_error on RPC-level failure" do
      stub_name = stub_name(:execute_transaction_rpc_error)

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"message" => "signature rejected"}
        })
      end)

      assert {:error, {:rpc_error, "signature rejected"}} =
               ClientHTTP.execute_transaction("tx-bytes", ["sig-1"],
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "execute_transaction returns timeout on transport timeout" do
      stub_name = stub_name(:execute_transaction_timeout)

      Req.Test.stub(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               ClientHTTP.execute_transaction("tx-bytes", ["sig-1"],
                 req_options: [plug: {Req.Test, stub_name}]
               )
    end
  end

  describe "verify_zklogin_signature/5" do
    test "verify_zklogin_signature returns success true for valid signature" do
      stub_name = stub_name(:verify_zklogin_signature_success)

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)

        assert payload["query"] =~ "query VerifyZkLoginSignature"

        assert payload["variables"] == %{
                 "author" => "0xabc",
                 "bytes" => "message-bytes",
                 "intentScope" => "PERSONAL_MESSAGE",
                 "signature" => "signature-bytes"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "verifyZkLoginSignature" => %{"success" => true}
          }
        })
      end)

      assert {:ok, %{"verifyZkLoginSignature" => %{"success" => true}}} =
               ClientHTTP.verify_zklogin_signature(
                 "message-bytes",
                 "signature-bytes",
                 "PERSONAL_MESSAGE",
                 "0xabc",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "verify_zklogin_signature returns success false for invalid signature" do
      stub_name = stub_name(:verify_zklogin_signature_failure)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "author" => "0xabc",
                 "bytes" => "message-bytes",
                 "intentScope" => "PERSONAL_MESSAGE",
                 "signature" => "signature-bytes"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "verifyZkLoginSignature" => %{"success" => false}
          }
        })
      end)

      assert {:ok, %{"verifyZkLoginSignature" => %{"success" => false}}} =
               ClientHTTP.verify_zklogin_signature(
                 "message-bytes",
                 "signature-bytes",
                 "PERSONAL_MESSAGE",
                 "0xabc",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "verify_zklogin_signature returns graphql_errors on endpoint error" do
      stub_name = stub_name(:verify_zklogin_signature_graphql_errors)
      errors = [%{"message" => "verification unavailable"}]

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "author" => "0xabc",
                 "bytes" => "message-bytes",
                 "intentScope" => "PERSONAL_MESSAGE",
                 "signature" => "signature-bytes"
               }

        Req.Test.json(conn, %{"errors" => errors})
      end)

      assert {:error, {:graphql_errors, ^errors}} =
               ClientHTTP.verify_zklogin_signature(
                 "message-bytes",
                 "signature-bytes",
                 "PERSONAL_MESSAGE",
                 "0xabc",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "verify_zklogin_signature returns timeout on transport timeout" do
      stub_name = stub_name(:verify_zklogin_signature_timeout)

      Req.Test.stub(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               ClientHTTP.verify_zklogin_signature(
                 "message-bytes",
                 "signature-bytes",
                 "PERSONAL_MESSAGE",
                 "0xabc",
                 req_options: [plug: {Req.Test, stub_name}]
               )
    end
  end

  describe "get_dynamic_fields/2" do
    test "get_dynamic_fields returns entries with name and value for valid parent" do
      stub_name = stub_name(:get_dynamic_fields_success)

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)

        assert payload["query"] =~ "query GetDynamicFields"

        assert payload["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => true, "endCursor" => "cursor-1"},
                "nodes" => [
                  %{
                    "name" => %{
                      "type" => %{"repr" => "address"},
                      "json" => "0xmember"
                    },
                    "value" => %{
                      "type" => %{"repr" => "u64"},
                      "json" => 3
                    }
                  }
                ]
              }
            }
          }
        })
      end)

      assert {:ok,
              %{
                data: [
                  %{
                    name: %{type: "address", json: "0xmember"},
                    value: %{type: "u64", json: 3}
                  }
                ],
                has_next_page: true,
                end_cursor: "cursor-1"
              }} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields normalizes MoveValue entries" do
      stub_name = stub_name(:get_dynamic_fields_move_value)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => [
                  %{
                    "name" => %{"type" => %{"repr" => "u64"}, "json" => 9},
                    "value" => %{
                      "type" => %{"repr" => "vector<address>"},
                      "json" => ["0x1", "0x2"]
                    }
                  }
                ]
              }
            }
          }
        })
      end)

      assert {:ok,
              %{
                data: [%{value: %{type: "vector<address>", json: ["0x1", "0x2"]}}],
                has_next_page: false,
                end_cursor: nil
              }} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields normalizes MoveObject entries" do
      stub_name = stub_name(:get_dynamic_fields_move_object)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => [
                  %{
                    "name" => %{"type" => %{"repr" => "address"}, "json" => "0xchild"},
                    "value" => %{
                      "contents" => %{
                        "type" => %{"repr" => "0x2::table::Entry"},
                        "json" => %{"value" => %{"candidate" => "0xleader"}}
                      }
                    }
                  }
                ]
              }
            }
          }
        })
      end)

      assert {:ok,
              %{
                data: [
                  %{
                    value: %{
                      type: "0x2::table::Entry",
                      json: %{"value" => %{"candidate" => "0xleader"}}
                    }
                  }
                ],
                has_next_page: false,
                end_cursor: nil
              }} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields returns not_found for null parent object" do
      stub_name = stub_name(:get_dynamic_fields_not_found)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xmissing"
               }

        Req.Test.json(conn, %{"data" => %{"object" => nil}})
      end)

      assert {:error, :not_found} =
               ClientHTTP.get_dynamic_fields("0xmissing",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields returns empty page for object with no dynamic fields" do
      stub_name = stub_name(:get_dynamic_fields_empty)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => []
              }
            }
          }
        })
      end)

      assert {:ok, %{data: [], has_next_page: false, end_cursor: nil}} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields passes cursor as after variable" do
      stub_name = stub_name(:get_dynamic_fields_cursor)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => "cursor-abc",
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => []
              }
            }
          }
        })
      end)

      assert {:ok, %{data: [], has_next_page: false, end_cursor: nil}} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 cursor: "cursor-abc",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields returns graphql_errors on endpoint error" do
      stub_name = stub_name(:get_dynamic_fields_graphql_errors)
      errors = [%{"message" => "query rejected"}]

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{"errors" => errors})
      end)

      assert {:error, {:graphql_errors, ^errors}} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields returns timeout on transport timeout" do
      stub_name = stub_name(:get_dynamic_fields_timeout)

      Req.Test.stub(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :timeout} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )
    end

    test "get_dynamic_fields returns rate_limited on HTTP 429" do
      stub_name = stub_name(:get_dynamic_fields_rate_limited)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        json_response(conn, 429, %{"errors" => [%{"message" => "slow down"}]})
      end)

      assert {:error, :rate_limited} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields returns invalid_response for malformed body" do
      stub_name = stub_name(:get_dynamic_fields_invalid_response)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => [
                  %{
                    "name" => %{"type" => %{"repr" => "address"}, "json" => "0xchild"},
                    "value" => %{}
                  }
                ]
              }
            }
          }
        })
      end)

      assert {:error, :invalid_response} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_dynamic_fields passes limit as first variable" do
      stub_name = stub_name(:get_dynamic_fields_limit)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 100,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => []
              }
            }
          }
        })
      end)

      assert {:ok, %{data: [], has_next_page: false, end_cursor: nil}} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 limit: 100,
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "errors key takes precedence over partial data" do
      stub_name = stub_name(:get_dynamic_fields_partial_errors)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => [
                  %{
                    "name" => %{"type" => %{"repr" => "address"}, "json" => "0xmember"},
                    "value" => %{"type" => %{"repr" => "u64"}, "json" => 1}
                  }
                ]
              }
            }
          },
          "errors" => [%{"message" => "partial failure"}]
        })
      end)

      assert {:error, {:graphql_errors, [%{"message" => "partial failure"}]}} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "http 429 returns rate_limited" do
      stub_name = stub_name(:get_dynamic_fields_429_short_circuit)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "after" => nil,
                 "first" => 50,
                 "id" => "0xparent"
               }

        json_response(conn, 429, %{
          "data" => %{
            "object" => %{
              "dynamicFields" => %{
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil},
                "nodes" => []
              }
            }
          }
        })
      end)

      assert {:error, :rate_limited} =
               ClientHTTP.get_dynamic_fields("0xparent",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end
  end

  describe "get_coins/2" do
    test "get_coins returns coin list with refs and balances" do
      stub_name = stub_name(:get_coins_success)
      digest_b58 = "11111111111111111111111111111111"

      Req.Test.expect(stub_name, fn conn ->
        payload = graphql_payload(conn)

        assert payload["query"] =~ "query GetCoins"

        assert payload["variables"] == %{
                 "owner" => "0xowner",
                 "type" => "0x2::coin::Coin<0x2::sui::SUI>"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "address" => %{
              "coins" => %{
                "nodes" => [
                  %{
                    "address" => "0x" <> String.duplicate("ab", 32),
                    "version" => "7",
                    "digest" => digest_b58,
                    "contents" => %{"json" => %{"balance" => "12000000"}}
                  }
                ]
              }
            }
          }
        })
      end)

      assert {:ok, [%{object_id: object_id, version: 7, digest: digest, balance: 12_000_000}]} =
               ClientHTTP.get_coins("0xowner", req_options: [plug: {Req.Test, stub_name}])

      assert object_id == Base.decode16!(String.duplicate("ab", 32), case: :lower)
      assert digest == <<0::256>>
      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_coins returns empty list for unfunded address" do
      stub_name = stub_name(:get_coins_empty)

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "owner" => "0xunfunded",
                 "type" => "0x2::coin::Coin<0x2::sui::SUI>"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "address" => %{
              "coins" => %{
                "nodes" => []
              }
            }
          }
        })
      end)

      assert {:ok, []} =
               ClientHTTP.get_coins("0xunfunded", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "get_coins returns graphql_errors on endpoint error" do
      stub_name = stub_name(:get_coins_graphql_errors)
      errors = [%{"message" => "coins unavailable"}]

      Req.Test.expect(stub_name, fn conn ->
        assert graphql_payload(conn)["variables"] == %{
                 "owner" => "0xowner",
                 "type" => "0x2::coin::Coin<0x2::sui::SUI>"
               }

        Req.Test.json(conn, %{"errors" => errors})
      end)

      assert {:error, {:graphql_errors, ^errors}} =
               ClientHTTP.get_coins("0xowner", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end
  end

  describe "configuration and behaviour" do
    test "URL override via opts is used for requests" do
      stub_name = stub_name(:url_override)

      Req.Test.expect(stub_name, fn conn ->
        assert conn.scheme == :http
        assert conn.host == "custom"
        assert conn.port == 8_000
        assert conn.request_path == "/graphql"

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0xabc",
              "asMoveObject" => %{"contents" => %{"json" => %{"id" => "0xabc"}}}
            }
          }
        })
      end)

      assert {:ok, %{"id" => "0xabc"}} =
               ClientHTTP.get_object("0xabc",
                 url: "http://custom:8000/graphql",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "default URL comes from active world config" do
      stub_name = stub_name(:default_url)

      Req.Test.expect(stub_name, fn conn ->
        assert conn.scheme == :http
        assert conn.host == "test.invalid"
        assert conn.request_path == "/graphql"

        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0xabc",
              "asMoveObject" => %{"contents" => %{"json" => %{"id" => "0xabc"}}}
            }
          }
        })
      end)

      assert {:ok, %{"id" => "0xabc"}} =
               ClientHTTP.get_object("0xabc", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "retries transient failures before succeeding" do
      stub_name = stub_name(:retry_success)

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      Req.Test.expect(stub_name, fn conn ->
        json_response(conn, 500, %{"errors" => [%{"message" => "temporary upstream failure"}]})
      end)

      Req.Test.expect(stub_name, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "object" => %{
              "address" => "0xabc",
              "asMoveObject" => %{"contents" => %{"json" => %{"id" => "0xabc"}}}
            }
          }
        })
      end)

      assert {:ok, %{"id" => "0xabc"}} =
               ClientHTTP.get_object("0xabc", req_options: [plug: {Req.Test, stub_name}])

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "Client.HTTP implements Sui.Client behaviour" do
      behaviours = ClientHTTP.module_info(:attributes)[:behaviour] || []

      assert Client in behaviours
    end
  end

  defp graphql_payload(conn) do
    {:ok, body, _conn} = read_body(conn)
    Jason.decode!(body)
  end

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp stub_name(prefix), do: {prefix, System.unique_integer([:positive])}
end
