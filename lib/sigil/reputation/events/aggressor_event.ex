defmodule Sigil.Reputation.Events.AggressorEvent do
  @moduledoc """
  Normalized turret aggressor event used by the reputation pipeline.
  """

  @enforce_keys [
    :turret_id,
    :turret_owner_tribe_id,
    :aggressor_character_id,
    :aggressor_tribe_id,
    :timestamp,
    :checkpoint_seq
  ]
  defstruct [
    :turret_id,
    :turret_owner_tribe_id,
    :aggressor_character_id,
    :aggressor_tribe_id,
    :timestamp,
    :checkpoint_seq
  ]

  @type t() :: %__MODULE__{
          turret_id: String.t(),
          turret_owner_tribe_id: non_neg_integer() | nil,
          aggressor_character_id: String.t(),
          aggressor_tribe_id: non_neg_integer() | nil,
          timestamp: DateTime.t(),
          checkpoint_seq: non_neg_integer()
        }
end
