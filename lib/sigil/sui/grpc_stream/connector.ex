defmodule Sigil.Sui.GrpcStream.Connector do
  @moduledoc """
  gRPC connector and stream-forwarding helpers for Sui checkpoint subscriptions.
  """

  require Logger

  alias Sigil.Sui.GrpcStream.Codec

  alias Sigil.Sui.Proto.{
    SubscribeCheckpointsRequest,
    SubscriptionService
  }

  @default_connect_timeout_ms 1_000
  @default_read_mask_paths ["cursor", "checkpoint.transactions.events"]

  @doc "Returns the default connector callback configured for runtime.
  "
  @spec default_connect_fun() :: (String.t(), non_neg_integer() | nil ->
                                    {:ok, term()} | {:error, term()})
  def default_connect_fun do
    case Application.get_env(:sigil, :grpc_connector) do
      nil -> &default_connect/2
      module -> &module.connect/2
    end
  end

  @doc "Connects to Sui and starts forwarding stream responses to owner mailbox."
  @spec default_connect(String.t(), non_neg_integer() | nil) ::
          {:ok, %{stream_ref: pid(), monitor_ref: reference()}} | {:error, term()}
  def default_connect(endpoint, _cursor) do
    owner = self()

    with {:ok, channel} <-
           GRPC.Stub.connect(connection_target(endpoint), connection_options(endpoint)),
         {:ok, responses} <-
           SubscriptionService.Stub.subscribe_checkpoints(channel, subscribe_request()) do
      # Upstream SubscribeCheckpoints starts from current head.
      # Backfill behavior remains injectable via custom connector module.
      {reader_pid, monitor_ref} =
        spawn_monitor(fn -> forward_stream_responses(responses, owner, self()) end)

      {:ok, %{stream_ref: reader_pid, monitor_ref: monitor_ref}}
    end
  rescue
    error in RuntimeError -> {:error, error}
  end

  @doc "Streams responses and reports checkpoints/close events back to the stream owner."
  @spec forward_stream_responses(Enumerable.t(), pid(), pid()) :: :ok
  def forward_stream_responses(responses, owner, stream_ref) do
    reason =
      Enum.reduce_while(responses, :closed, fn
        {:ok, response}, _acc ->
          case Codec.normalize_stream_response(response) do
            {:ok, checkpoint} ->
              send(owner, {:checkpoint, stream_ref, checkpoint})
              {:cont, :closed}

            {:error, reason} ->
              {:halt, reason}
          end

        {:error, reason}, _acc ->
          {:halt, reason}

        other, _acc ->
          {:halt, {:unexpected_stream_item, other}}
      end)

    send(owner, {:stream_closed, stream_ref, reason})
    :ok
  end

  @doc "Builds the protobuf request used for checkpoint subscriptions."
  @spec subscribe_request() :: SubscribeCheckpointsRequest.t()
  def subscribe_request do
    %SubscribeCheckpointsRequest{
      read_mask: %Google.Protobuf.FieldMask{paths: @default_read_mask_paths}
    }
  end

  @doc "Normalizes optional URL schemes to plain GRPC host:port target."
  @spec connection_target(String.t()) :: String.t()
  def connection_target("https://" <> rest), do: rest
  def connection_target("http://" <> rest), do: rest
  def connection_target(endpoint), do: endpoint

  @doc "Builds secure transport options unless endpoint points to localhost."
  @spec connection_options(String.t()) :: keyword()
  def connection_options(endpoint) do
    adapter_opts = [transport_opts: [timeout: @default_connect_timeout_ms]]

    if local_endpoint?(endpoint) do
      [adapter: GRPC.Client.Adapters.Mint, adapter_opts: adapter_opts]
    else
      [
        adapter: GRPC.Client.Adapters.Mint,
        adapter_opts: adapter_opts,
        cred: GRPC.Credential.new(ssl: [])
      ]
    end
  end

  @doc "Checks whether the endpoint target resolves to loopback/local host."
  @spec local_endpoint?(String.t()) :: boolean()
  def local_endpoint?(endpoint) do
    target = connection_target(endpoint)

    String.starts_with?(target, "localhost:") or
      String.starts_with?(target, "127.0.0.1:") or
      String.starts_with?(target, "[::1]:")
  end
end
