defmodule Sigil.Reputation.Events.JumpEvent do
  @moduledoc """
  Normalized gate jump event used by the reputation pipeline.
  """

  @enforce_keys [
    :character_id,
    :character_tribe_id,
    :source_gate_id,
    :source_gate_owner_tribe_id,
    :destination_gate_id,
    :timestamp,
    :checkpoint_seq
  ]
  defstruct [
    :character_id,
    :character_tribe_id,
    :source_gate_id,
    :source_gate_owner_tribe_id,
    :destination_gate_id,
    :timestamp,
    :checkpoint_seq
  ]

  @type t() :: %__MODULE__{
          character_id: String.t(),
          character_tribe_id: non_neg_integer() | nil,
          source_gate_id: String.t(),
          source_gate_owner_tribe_id: non_neg_integer() | nil,
          destination_gate_id: String.t(),
          timestamp: DateTime.t(),
          checkpoint_seq: non_neg_integer()
        }
end
