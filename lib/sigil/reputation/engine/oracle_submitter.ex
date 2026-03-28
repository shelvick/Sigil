defmodule Sigil.Reputation.Engine.OracleSubmitter do
  @moduledoc """
  Handles tier-crossing oracle submission side effects for the reputation engine.
  """

  require Logger

  alias Sigil.Cache
  alias Sigil.Reputation.ReputationScore

  @typedoc "Standing atom used by oracle submission payloads."
  @type standing_atom() :: :hostile | :unfriendly | :neutral | :friendly | :allied

  @typedoc "Expected engine submit callback argument shape."
  @type submit_args() :: %{
          custodian_ref: map(),
          target_tribe_id: non_neg_integer(),
          standing: standing_atom(),
          signer_keypair: binary()
        }

  @typedoc "Subset of engine state used by oracle submission logic."
  @type state() :: %{
          required(:tables) => %{standings: Cache.table_id()},
          required(:submit_fn) => (submit_args() -> {:ok, term()} | {:error, term()}),
          required(:signer_keypair) => binary() | nil,
          optional(atom()) => term()
        }

  @doc "Submits oracle updates only when a score crosses tiers and auto-submit is allowed."
  @spec maybe_submit(state(), ReputationScore.t(), integer(), integer(), (integer() ->
                                                                            standing_atom())) ::
          :ok
  def maybe_submit(_state, _score_record, old_tier, new_tier, _standing_atom_fun)
      when old_tier == new_tier,
      do: :ok

  def maybe_submit(
        _state,
        %ReputationScore{pinned: true},
        _old_tier,
        _new_tier,
        _standing_atom_fun
      ),
      do: :ok

  def maybe_submit(
        %{signer_keypair: signer_keypair},
        _score_record,
        _old_tier,
        _new_tier,
        _standing_atom_fun
      )
      when not is_binary(signer_keypair) do
    Logger.warning("Skipping oracle submit: signer keypair missing")
    :ok
  end

  def maybe_submit(state, score_record, _old_tier, new_tier, standing_atom_fun) do
    case Cache.get(state.tables.standings, {:active_custodian, score_record.source_tribe_id}) do
      custodian_ref when is_map(custodian_ref) ->
        submit_oracle(state, score_record, new_tier, custodian_ref, standing_atom_fun)

      _other ->
        :ok
    end
  rescue
    exception ->
      Logger.error("Oracle submit exception: #{Exception.message(exception)}")
      :ok
  end

  @spec submit_oracle(
          state(),
          ReputationScore.t(),
          integer(),
          map(),
          (integer() -> standing_atom())
        ) :: :ok
  defp submit_oracle(state, score_record, new_tier, custodian_ref, standing_atom_fun) do
    case state.submit_fn.(%{
           custodian_ref: custodian_ref,
           target_tribe_id: score_record.target_tribe_id,
           standing: standing_atom_fun.(new_tier),
           signer_keypair: state.signer_keypair
         }) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("Oracle submit failed: #{inspect(reason)}")
        :ok
    end
  end
end
