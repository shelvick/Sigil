defmodule Sigil.Reputation.Engine do
  @moduledoc """
  Reputation scoring engine that consumes chain events and maintains tribe-pair scores.
  """

  use GenServer

  require Logger

  alias Sigil.Cache
  alias Sigil.Worlds
  alias Sigil.Reputation.Engine.{OracleSubmitter, Persistence, ScoreState, Scorer, Tables}
  alias Sigil.Reputation.{EventParser, ReputationScore, Scoring}

  @chain_events_topic "chain_events"
  @reputation_topic "reputation"
  @default_pubsub Sigil.PubSub
  @default_decay_interval_ms 3_600_000
  @default_flush_interval_ms 60_000
  @default_decay_hours 24
  @required_tables [:reputation, :assemblies, :accounts, :characters, :gate_network, :standings]

  @typedoc "Runtime ETS tables required by the engine."
  @type tables() :: %{
          reputation: Cache.table_id(),
          assemblies: Cache.table_id(),
          accounts: Cache.table_id(),
          characters: Cache.table_id(),
          gate_network: Cache.table_id(),
          standings: Cache.table_id()
        }

  @typedoc "Oracle submit callback argument contract."
  @type oracle_submit_args() :: %{
          custodian_ref: map(),
          target_tribe_id: non_neg_integer(),
          standing: :hostile | :unfriendly | :neutral | :friendly | :allied,
          signer_keypair: binary()
        }

  @typedoc "Options accepted by `start_link/1`."
  @type option() ::
          {:pubsub, atom() | module()}
          | {:tables, tables()}
          | {:resolve_tables, (-> tables() | nil)}
          | {:scoring_module, module()}
          | {:now_fun, (-> DateTime.t())}
          | {:submit_fn, (oracle_submit_args() -> {:ok, term()} | {:error, term()})}
          | {:signer_keypair, binary() | nil}
          | {:decay_interval_ms, pos_integer()}
          | {:flush_interval_ms, pos_integer()}
          | {:repo_module, module()}
          | {:sandbox_owner, pid()}
          | {:enabled, boolean()}
          | {:world, Worlds.world_name()}

  @type options() :: [option()]

  @typedoc "Engine runtime state."
  @type state() :: %{
          pubsub: atom() | module(),
          world: Worlds.world_name(),
          tables: tables() | nil,
          resolve_tables: (-> tables() | nil),
          scoring_module: module(),
          now_fun: (-> DateTime.t()),
          submit_fn: (oracle_submit_args() -> {:ok, term()} | {:error, term()}),
          signer_keypair: binary() | nil,
          decay_interval_ms: pos_integer(),
          flush_interval_ms: pos_integer(),
          repo_module: module(),
          sandbox_owner: pid() | nil,
          aggressor_flags: %{non_neg_integer() => DateTime.t()},
          dirty_scores: MapSet.t({non_neg_integer(), non_neg_integer()})
        }

  @doc "Returns the singleton child spec used by the application supervisor."
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @doc "Starts the reputation engine."
  @spec start_link(options()) :: GenServer.on_start() | :ignore
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Returns current state for test inspection."
  @spec get_state(GenServer.server()) :: state()
  def get_state(server), do: GenServer.call(server, :get_state)

  @impl true
  @spec init(options()) :: {:ok, state(), {:continue, :post_init}} | :ignore
  def init(opts) do
    enabled =
      Keyword.get(opts, :enabled, Application.get_env(:sigil, :start_reputation_engine, false))

    world = Keyword.get(opts, :world, Worlds.default_world())

    if enabled do
      {:ok,
       %{
         pubsub: Keyword.get(opts, :pubsub, @default_pubsub),
         world: world,
         tables: Keyword.get(opts, :tables),
         resolve_tables:
           Keyword.get(opts, :resolve_tables, fn ->
             default_resolve_tables(world)
           end),
         scoring_module: Keyword.get(opts, :scoring_module, Scoring),
         now_fun: Keyword.get(opts, :now_fun, &DateTime.utc_now/0),
         submit_fn: Keyword.get(opts, :submit_fn, fn _args -> {:ok, :noop} end),
         signer_keypair: Keyword.get(opts, :signer_keypair),
         decay_interval_ms: Keyword.get(opts, :decay_interval_ms, @default_decay_interval_ms),
         flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
         repo_module: Keyword.get(opts, :repo_module, Sigil.Repo),
         sandbox_owner: Keyword.get(opts, :sandbox_owner),
         aggressor_flags: %{},
         dirty_scores: MapSet.new()
       }, {:continue, :post_init}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:post_init, state) do
    :ok = maybe_allow_sandbox_owner(state.repo_module, state.sandbox_owner)
    :ok = Phoenix.PubSub.subscribe(state.pubsub, Worlds.topic(state.world, @chain_events_topic))
    schedule_decay(state.decay_interval_ms)
    schedule_flush(state.flush_interval_ms)

    next_state =
      state
      |> maybe_resolve_tables()
      |> load_scores_from_repo()

    {:noreply, next_state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info({:chain_event, event_type, raw_event, checkpoint_seq}, state)
      when event_type in [:killmail_created, :jump, :priority_list_updated] do
    next_state =
      state
      |> maybe_resolve_tables()
      |> maybe_process_chain_event(event_type, raw_event, checkpoint_seq)

    {:noreply, next_state}
  end

  def handle_info(:decay_tick, state) do
    next_state =
      state
      |> maybe_resolve_tables()
      |> apply_decay_tick()

    schedule_decay(state.decay_interval_ms)
    {:noreply, next_state}
  end

  def handle_info(:flush_state, state) do
    next_state =
      state
      |> maybe_resolve_tables()
      |> flush_dirty_scores()

    schedule_flush(state.flush_interval_ms)
    {:noreply, next_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @spec maybe_process_chain_event(state(), atom(), map(), non_neg_integer()) :: state()
  defp maybe_process_chain_event(
         %{tables: nil} = state,
         _event_type,
         _raw_event,
         _checkpoint_seq
       ),
       do: state

  defp maybe_process_chain_event(state, event_type, raw_event, checkpoint_seq) do
    parse_opts = [
      tables: state.tables,
      now_fun: state.now_fun,
      checkpoint_seq: checkpoint_seq
    ]

    case EventParser.parse_event(event_type, raw_event, parse_opts) do
      {:ok, event} -> apply_parsed_event(state, event_type, event)
      {:error, _reason} -> state
    end
  end

  @spec apply_parsed_event(state(), atom(), struct()) :: state()
  defp apply_parsed_event(state, :priority_list_updated, event) do
    case event.aggressor_tribe_id do
      tribe_id when is_integer(tribe_id) ->
        now = state.now_fun.()
        %{state | aggressor_flags: Map.put(state.aggressor_flags, tribe_id, now)}

      _other ->
        state
    end
  end

  defp apply_parsed_event(state, :jump, event) do
    state = remember_last_gate_owner(state, event)

    case Scorer.compute_jump_delta(event, scorer_deps(state)) do
      {:ok, %{source_tribe_id: source_tribe_id, target_tribe_id: target_tribe_id, delta: delta}} ->
        apply_score_delta(state, source_tribe_id, target_tribe_id, delta, event.timestamp)

      :skip ->
        state
    end
  end

  defp apply_parsed_event(state, :killmail_created, event) do
    case Scorer.compute_kill_delta(event, scorer_deps(state)) do
      {:ok, %{source_tribe_id: source_tribe_id, target_tribe_id: target_tribe_id, delta: delta}} ->
        apply_score_delta(state, source_tribe_id, target_tribe_id, delta, event.timestamp)

      :skip ->
        state
    end
  end

  @spec remember_last_gate_owner(state(), struct()) :: state()
  defp remember_last_gate_owner(state, %{
         source_gate_owner_tribe_id: tribe_id,
         character_id: character_id
       })
       when is_integer(tribe_id) and is_binary(character_id) do
    Cache.put(state.tables.reputation, {:last_gate, character_id}, tribe_id)
    state
  end

  defp remember_last_gate_owner(state, _event), do: state

  @spec scorer_deps(state()) :: Scorer.deps()
  defp scorer_deps(state) do
    %{
      tables: %{reputation: state.tables.reputation, standings: state.tables.standings},
      scoring_module: state.scoring_module,
      aggressor_flags: state.aggressor_flags,
      now_fun: state.now_fun
    }
  end

  @spec apply_score_delta(
          state(),
          non_neg_integer(),
          non_neg_integer(),
          integer(),
          DateTime.t()
        ) :: state()
  defp apply_score_delta(state, _source_tribe_id, _target_tribe_id, 0, _timestamp), do: state

  defp apply_score_delta(state, source_tribe_id, target_tribe_id, delta, timestamp) do
    score_key = {:reputation_score, source_tribe_id, target_tribe_id}

    score_record =
      ScoreState.fetch_score_record(
        state.tables.reputation,
        score_key,
        source_tribe_id,
        target_tribe_id,
        state.scoring_module
      )

    old_score = score_record.score || 0
    new_score = ScoreState.clamp_score(old_score + delta)

    if new_score == old_score do
      state
    else
      thresholds =
        ScoreState.normalize_thresholds(score_record.tier_thresholds, state.scoring_module)

      old_tier = state.scoring_module.evaluate_tier(old_score, thresholds)
      new_tier = state.scoring_module.evaluate_tier(new_score, thresholds)

      updated_record = %ReputationScore{
        score_record
        | source_tribe_id: source_tribe_id,
          target_tribe_id: target_tribe_id,
          score: new_score,
          last_event_at: timestamp,
          last_decay_at: score_record.last_decay_at || timestamp,
          tier_thresholds: thresholds
      }

      Cache.put(state.tables.reputation, score_key, updated_record)

      next_state =
        state
        |> ScoreState.mark_dirty(source_tribe_id, target_tribe_id)
        |> maybe_submit_oracle(updated_record, old_tier, new_tier)

      broadcast_score_update(
        next_state,
        updated_record,
        old_score,
        ScoreState.standing_atom(old_tier),
        ScoreState.standing_atom(new_tier)
      )

      next_state
    end
  end

  @spec apply_decay_tick(state()) :: state()
  defp apply_decay_tick(%{tables: nil} = state), do: state

  defp apply_decay_tick(state) do
    now = state.now_fun.()

    state_after_scores =
      state.tables.reputation
      |> Cache.match({{:reputation_score, :_, :_}, :_})
      |> Enum.reduce(state, fn
        {{:reputation_score, source_tribe_id, target_tribe_id}, %ReputationScore{} = score_record},
        acc_state ->
          apply_decay_for_pair(acc_state, source_tribe_id, target_tribe_id, score_record, now)

        _other, acc_state ->
          acc_state
      end)

    trimmed_flags =
      Map.reject(state_after_scores.aggressor_flags, fn {_tribe_id, timestamp} ->
        state_after_scores.scoring_module.aggressor_expired?(timestamp, now)
      end)

    %{state_after_scores | aggressor_flags: trimmed_flags}
  end

  @spec apply_decay_for_pair(
          state(),
          non_neg_integer(),
          non_neg_integer(),
          ReputationScore.t(),
          DateTime.t()
        ) :: state()
  defp apply_decay_for_pair(state, source_tribe_id, target_tribe_id, score_record, now) do
    old_score = score_record.score || 0

    hours_elapsed = decay_hours_since(score_record.last_decay_at, now)

    decayed_score = state.scoring_module.apply_decay(old_score, hours_elapsed)

    transitive_adjustment =
      compute_transitive_adjustment(
        state.tables.standings,
        source_tribe_id,
        target_tribe_id,
        state
      )

    new_score = ScoreState.clamp_score(decayed_score + transitive_adjustment)

    if new_score == old_score do
      state
    else
      thresholds =
        ScoreState.normalize_thresholds(score_record.tier_thresholds, state.scoring_module)

      old_tier = state.scoring_module.evaluate_tier(old_score, thresholds)
      new_tier = state.scoring_module.evaluate_tier(new_score, thresholds)

      updated_record = %ReputationScore{
        score_record
        | score: new_score,
          last_decay_at: now,
          tier_thresholds: thresholds
      }

      Cache.put(
        state.tables.reputation,
        {:reputation_score, source_tribe_id, target_tribe_id},
        updated_record
      )

      next_state =
        state
        |> ScoreState.mark_dirty(source_tribe_id, target_tribe_id)
        |> maybe_submit_oracle(updated_record, old_tier, new_tier)

      broadcast_score_update(
        next_state,
        updated_record,
        old_score,
        ScoreState.standing_atom(old_tier),
        ScoreState.standing_atom(new_tier)
      )

      next_state
    end
  end

  @spec compute_transitive_adjustment(
          Cache.table_id(),
          non_neg_integer(),
          non_neg_integer(),
          state()
        ) ::
          integer()
  defp compute_transitive_adjustment(standings_table, source_tribe_id, target_tribe_id, state) do
    our_standings =
      standings_table
      |> Cache.match({{:tribe_standing, source_tribe_id, :_}, :_})
      |> Enum.reduce(%{}, fn
        {{:tribe_standing, ^source_tribe_id, intermediate_tribe_id}, standing}, acc
        when is_integer(standing) ->
          Map.put(acc, intermediate_tribe_id, standing)

        _other, acc ->
          acc
      end)

    their_standings_of_target =
      Enum.reduce(our_standings, %{}, fn {intermediate_tribe_id, _our_standing}, acc ->
        case Cache.get(standings_table, {:tribe_standing, intermediate_tribe_id, target_tribe_id}) do
          standing when is_integer(standing) -> Map.put(acc, intermediate_tribe_id, standing)
          _other -> acc
        end
      end)

    state.scoring_module.compute_transitive_score(our_standings, their_standings_of_target, 0.25)
  end

  @spec flush_dirty_scores(state()) :: state()
  defp flush_dirty_scores(state), do: Persistence.flush_dirty_scores(state)

  @spec load_scores_from_repo(state()) :: state()
  defp load_scores_from_repo(state), do: Persistence.load_scores_from_repo(state)

  @spec maybe_submit_oracle(map(), ReputationScore.t(), integer(), integer()) :: map()
  defp maybe_submit_oracle(state, score_record, old_tier, new_tier) do
    _result =
      OracleSubmitter.maybe_submit(
        state,
        score_record,
        old_tier,
        new_tier,
        &ScoreState.standing_atom/1
      )

    state
  end

  @spec broadcast_score_update(map(), ReputationScore.t(), integer(), atom(), atom()) ::
          :ok | {:error, term()}
  defp broadcast_score_update(state, score_record, old_score, old_tier, new_tier) do
    payload = %{
      tribe_id: score_record.source_tribe_id,
      target_tribe_id: score_record.target_tribe_id,
      account_address: account_address_for(score_record.source_tribe_id, state.tables),
      score: score_record.score,
      old_score: old_score,
      old_tier: old_tier,
      new_tier: new_tier,
      target_tribe_name: nil
    }

    Phoenix.PubSub.broadcast(
      state.pubsub,
      Worlds.topic(state.world, @reputation_topic),
      {:reputation_updated, payload}
    )
  end

  defp account_address_for(source_tribe_id, tables) do
    case Cache.get(tables.standings, {:active_custodian, source_tribe_id}) do
      %{current_leader: current_leader} when is_binary(current_leader) -> current_leader
      _other -> nil
    end
  end

  defp maybe_resolve_tables(state), do: Tables.maybe_resolve(state, @required_tables)
  defp default_resolve_tables(world), do: Tables.default_resolve_tables(world)

  defp maybe_allow_sandbox_owner(repo_module, owner),
    do: Tables.maybe_allow_sandbox_owner(repo_module, owner)

  defp decay_hours_since(nil, _now), do: @default_decay_hours

  defp decay_hours_since(%DateTime{} = last_decay_at, now) do
    now
    |> DateTime.diff(last_decay_at, :second)
    |> max(0)
    |> div(3600)
    |> max(1)
  end

  defp schedule_decay(interval_ms), do: Process.send_after(self(), :decay_tick, interval_ms)
  defp schedule_flush(interval_ms), do: Process.send_after(self(), :flush_state, interval_ms)
end
