defmodule Sigil.Sui.Proto.SubscribeCheckpointsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "sui.rpc.v2.SubscribeCheckpointsRequest",
    protoc_gen_elixir_version: "0.15.0",
    syntax: :proto3

  field :read_mask, 1,
    optional: true,
    type: Google.Protobuf.FieldMask,
    json_name: "readMask"
end

defmodule Sigil.Sui.Proto.SubscribeCheckpointsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "sui.rpc.v2.SubscribeCheckpointsResponse",
    protoc_gen_elixir_version: "0.15.0",
    syntax: :proto3

  field :cursor, 1, optional: true, type: :uint64
  field :checkpoint, 2, optional: true, type: Sigil.Sui.Proto.Checkpoint
end

defmodule Sigil.Sui.Proto.Checkpoint do
  @moduledoc false

  use Protobuf,
    full_name: "sui.rpc.v2.Checkpoint",
    protoc_gen_elixir_version: "0.15.0",
    syntax: :proto3

  field :sequence_number, 1, optional: true, type: :uint64, json_name: "sequenceNumber"
  field :transactions, 6, repeated: true, type: Sigil.Sui.Proto.ExecutedTransaction
end

defmodule Sigil.Sui.Proto.ExecutedTransaction do
  @moduledoc false

  use Protobuf,
    full_name: "sui.rpc.v2.ExecutedTransaction",
    protoc_gen_elixir_version: "0.15.0",
    syntax: :proto3

  field :events, 5, optional: true, type: Sigil.Sui.Proto.TransactionEvents
end

defmodule Sigil.Sui.Proto.TransactionEvents do
  @moduledoc false

  use Protobuf,
    full_name: "sui.rpc.v2.TransactionEvents",
    protoc_gen_elixir_version: "0.15.0",
    syntax: :proto3

  field :events, 3, repeated: true, type: Sigil.Sui.Proto.Event
end

defmodule Sigil.Sui.Proto.Event do
  @moduledoc false

  use Protobuf,
    full_name: "sui.rpc.v2.Event",
    protoc_gen_elixir_version: "0.15.0",
    syntax: :proto3

  field :event_type, 4, optional: true, type: :string, json_name: "eventType"
  field :json, 6, optional: true, type: Google.Protobuf.Value
end

defmodule Sigil.Sui.Proto.SubscriptionService.Service do
  @moduledoc false

  use GRPC.Service, name: "sui.rpc.v2.SubscriptionService"

  rpc(
    :SubscribeCheckpoints,
    Sigil.Sui.Proto.SubscribeCheckpointsRequest,
    stream(Sigil.Sui.Proto.SubscribeCheckpointsResponse)
  )
end

defmodule Sigil.Sui.Proto.SubscriptionService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sigil.Sui.Proto.SubscriptionService.Service
end
