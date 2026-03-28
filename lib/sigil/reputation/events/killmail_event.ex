defmodule Sigil.Reputation.Events.KillmailEvent do
  @moduledoc """
  Normalized killmail event used by the reputation pipeline.
  """

  @enforce_keys [
    :killer_character_id,
    :victim_character_id,
    :killer_tribe_id,
    :victim_tribe_id,
    :solar_system_id,
    :loss_type,
    :timestamp,
    :checkpoint_seq
  ]
  defstruct [
    :killer_character_id,
    :victim_character_id,
    :killer_tribe_id,
    :victim_tribe_id,
    :solar_system_id,
    :loss_type,
    :timestamp,
    :checkpoint_seq
  ]

  @type t() :: %__MODULE__{
          killer_character_id: String.t(),
          victim_character_id: String.t(),
          killer_tribe_id: non_neg_integer() | nil,
          victim_tribe_id: non_neg_integer() | nil,
          solar_system_id: String.t() | nil,
          loss_type: String.t(),
          timestamp: DateTime.t(),
          checkpoint_seq: non_neg_integer()
        }
end
