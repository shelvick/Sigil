defmodule Sigil.Reputation.Engine.Scorer do
  @moduledoc """
  Context-aware score delta computation for reputation events.
  """

  alias Sigil.Cache

  @typedoc "Runtime ETS tables required by the scorer."
  @type tables() :: %{
          reputation: Cache.table_id(),
          standings: Cache.table_id()
        }

  @typedoc "Known score delta kind emitted by scorer helpers."
  @type delta_kind() :: :jump | :kill

  @typedoc "Score delta decision used by the engine event handlers."
  @type delta_result() ::
          {:ok,
           %{
             kind: delta_kind(),
             source_tribe_id: non_neg_integer(),
             target_tribe_id: non_neg_integer(),
             delta: integer()
           }}
          | :skip

  @typedoc "Dependencies required to evaluate score deltas."
  @type deps() :: %{
          required(:tables) => tables(),
          required(:scoring_module) => module(),
          required(:aggressor_flags) => %{non_neg_integer() => DateTime.t()},
          required(:now_fun) => (-> DateTime.t())
        }

  @typedoc "Subset of killmail event data required for scoring."
  @type kill_event() :: %{
          required(:killer_tribe_id) => non_neg_integer() | nil,
          required(:victim_tribe_id) => non_neg_integer() | nil,
          required(:victim_character_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Subset of jump event data required for scoring."
  @type jump_event() :: %{
          required(:source_gate_owner_tribe_id) => non_neg_integer() | nil,
          required(:character_tribe_id) => non_neg_integer() | nil,
          optional(atom()) => term()
        }

  @doc "Computes the jump delta and source/target tribe pair."
  @spec compute_jump_delta(jump_event(), deps()) :: delta_result()
  def compute_jump_delta(event, deps) do
    source_tribe_id = event.source_gate_owner_tribe_id
    target_tribe_id = event.character_tribe_id

    with true <- is_integer(source_tribe_id),
         true <- is_integer(target_tribe_id),
         true <- source_tribe_id != target_tribe_id do
      {:ok,
       %{
         kind: :jump,
         source_tribe_id: source_tribe_id,
         target_tribe_id: target_tribe_id,
         delta: deps.scoring_module.compute_jump_score()
       }}
    else
      _ -> :skip
    end
  end

  @doc "Computes the kill delta and source/target tribe pair with multipliers."
  @spec compute_kill_delta(kill_event(), deps()) :: delta_result()
  def compute_kill_delta(event, deps) do
    killer_tribe_id = event.killer_tribe_id
    victim_tribe_id = event.victim_tribe_id

    with true <- is_integer(killer_tribe_id),
         true <- is_integer(victim_tribe_id),
         true <- killer_tribe_id != victim_tribe_id do
      our_standing_of_killer =
        standing_value(victim_tribe_id, killer_tribe_id, deps.tables.standings)

      our_standing_of_victim = 4

      aggressor? = aggressor_active?(killer_tribe_id, deps.aggressor_flags, deps)

      on_our_grid? =
        victim_on_our_grid?(deps.tables.reputation, event.victim_character_id, victim_tribe_id)

      delta =
        deps.scoring_module.compute_kill_score(
          our_standing_of_killer,
          our_standing_of_victim,
          aggressor?,
          on_our_grid?
        )

      {:ok,
       %{
         kind: :kill,
         source_tribe_id: victim_tribe_id,
         target_tribe_id: killer_tribe_id,
         delta: delta
       }}
    else
      _ -> :skip
    end
  end

  @doc "Returns standing value for a tribe pair with neutral fallback."
  @spec standing_value(non_neg_integer(), non_neg_integer(), Cache.table_id()) :: 0..4
  def standing_value(source_tribe_id, target_tribe_id, _standings_table)
      when source_tribe_id == target_tribe_id,
      do: 4

  def standing_value(source_tribe_id, target_tribe_id, standings_table) do
    case Cache.get(standings_table, {:tribe_standing, source_tribe_id, target_tribe_id}) do
      standing when is_integer(standing) and standing >= 0 and standing <= 4 -> standing
      _other -> 2
    end
  end

  @doc "Returns true when an aggressor flag is present and still within the active window."
  @spec aggressor_active?(non_neg_integer(), %{non_neg_integer() => DateTime.t()}, deps()) ::
          boolean()
  def aggressor_active?(tribe_id, aggressor_flags, deps) do
    case Map.get(aggressor_flags, tribe_id) do
      %DateTime{} = flagged_at ->
        not deps.scoring_module.aggressor_expired?(flagged_at, deps.now_fun.())

      _other ->
        false
    end
  end

  @doc "Returns true when the victim's last observed gate belongs to the source tribe."
  @spec victim_on_our_grid?(Cache.table_id(), String.t(), non_neg_integer()) :: boolean()
  def victim_on_our_grid?(reputation_table, victim_character_id, victim_tribe_id) do
    Cache.get(reputation_table, {:last_gate, victim_character_id}) == victim_tribe_id
  end
end
