defmodule Sigil.WalrusClientTest do
  @moduledoc """
  Captures the Walrus blob-store client contract for seal-delivery flows.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.WalrusClient}
  @compile {:no_warn_undefined, Sigil.WalrusClient.HTTP}

  import Plug.Conn

  alias Sigil.WalrusClient
  alias Sigil.WalrusClient.HTTP

  describe "behaviour contract" do
    test "defines store, read, and existence callbacks" do
      callbacks = WalrusClient.behaviour_info(:callbacks)

      assert {:store_blob, 3} in callbacks
      assert {:read_blob, 2} in callbacks
      assert {:blob_exists?, 2} in callbacks
    end
  end

  describe "store_blob/3" do
    test "store_blob returns blob_id on successful upload" do
      stub_name = stub_name(:store_success)

      Req.Test.expect(stub_name, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/v1/blobs"
        assert conn.query_string == "epochs=5"
        assert request_binary(conn) == "encrypted-payload"

        Req.Test.json(conn, %{
          "newlyCreated" => %{"blobObject" => %{"blobId" => "blob-123"}}
        })
      end)

      assert {:ok, %{blob_id: "blob-123"}} =
               HTTP.store_blob("encrypted-payload", 5,
                 publisher_url: "https://publisher.test",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "store_blob handles already-certified blob" do
      stub_name = stub_name(:store_already_certified)

      Req.Test.expect(stub_name, fn conn ->
        assert conn.method == "PUT"

        Req.Test.json(conn, %{
          "alreadyCertified" => %{"blobId" => "blob-existing-456"}
        })
      end)

      assert {:ok, %{blob_id: "blob-existing-456"}} =
               HTTP.store_blob("encrypted-payload", 7,
                 publisher_url: "https://publisher.test",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "store_blob returns error on publisher failure" do
      stub_name = stub_name(:store_transport_error)

      Req.Test.stub(stub_name, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :econnrefused} =
               HTTP.store_blob("encrypted-payload", 5,
                 publisher_url: "https://publisher.test",
                 req_options: [plug: {Req.Test, stub_name}]
               )
    end

    test "store_blob returns rate_limited on walrus 429" do
      stub_name = stub_name(:store_rate_limited)

      Req.Test.expect(stub_name, fn conn ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{"error" => "too many requests"}))
      end)

      assert {:error, :rate_limited} =
               HTTP.store_blob("encrypted-payload", 5,
                 publisher_url: "https://publisher.test",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end
  end

  describe "read_blob/2" do
    test "read_blob returns binary data for existing blob" do
      stub_name = stub_name(:read_success)

      Req.Test.expect(stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v1/blobs/blob-123"

        send_resp(conn, 200, "sealed-intel")
      end)

      assert {:ok, "sealed-intel"} =
               HTTP.read_blob("blob-123",
                 aggregator_url: "https://aggregator.test",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "read_blob returns not_found for missing blob" do
      stub_name = stub_name(:read_not_found)

      Req.Test.expect(stub_name, fn conn ->
        send_resp(conn, 404, "missing")
      end)

      assert {:error, :not_found} =
               HTTP.read_blob("missing-blob",
                 aggregator_url: "https://aggregator.test",
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end
  end

  describe "blob_exists?/2" do
    @tag :acceptance
    test "blob availability preflight reports whether the encrypted blob exists" do
      present_stub = stub_name(:exists_true)
      missing_stub = stub_name(:exists_false)
      error_stub = stub_name(:exists_error)

      Req.Test.expect(present_stub, fn conn ->
        assert conn.method == "HEAD"
        send_resp(conn, 200, "")
      end)

      Req.Test.expect(missing_stub, fn conn ->
        assert conn.method == "HEAD"
        send_resp(conn, 404, "")
      end)

      Req.Test.stub(error_stub, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert HTTP.blob_exists?("blob-present",
               aggregator_url: "https://aggregator.test",
               req_options: [plug: {Req.Test, present_stub}]
             )

      refute HTTP.blob_exists?("blob-missing",
               aggregator_url: "https://aggregator.test",
               req_options: [plug: {Req.Test, missing_stub}]
             )

      refute HTTP.blob_exists?("blob-error",
               aggregator_url: "https://aggregator.test",
               req_options: [plug: {Req.Test, error_stub}]
             )

      assert :ok = Req.Test.verify!(present_stub)
      assert :ok = Req.Test.verify!(missing_stub)
    end
  end

  defp request_binary(conn) do
    {:ok, body, _conn} = read_body(conn)
    body
  end

  defp stub_name(prefix), do: {prefix, System.unique_integer([:positive])}
end
