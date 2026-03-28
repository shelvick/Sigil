defmodule Sigil.Sui.GrpcStream.CursorStore do
  @moduledoc """
  Sandbox-safe Postgres cursor persistence helpers for gRPC checkpoint streams.
  """

  require Logger

  alias Ecto.Adapters.SQL.Sandbox

  @doc "Allows this process to use the sandbox connection owned by another process."
  @spec maybe_allow_sandbox_owner(module(), pid() | nil) :: :ok
  def maybe_allow_sandbox_owner(_repo_module, nil), do: :ok

  def maybe_allow_sandbox_owner(repo_module, owner) when is_pid(owner) do
    if Code.ensure_loaded?(Sandbox) and function_exported?(Sandbox, :allow, 3) do
      Sandbox.allow(repo_module, owner, self())
    end

    :ok
  rescue
    exception ->
      Logger.warning("GrpcStream sandbox allow failed: #{Exception.message(exception)}")
      :ok
  end

  @doc "Loads the persisted cursor for a stream id, returning nil when absent or invalid."
  @spec default_load_cursor(module(), String.t()) :: non_neg_integer() | nil
  def default_load_cursor(repo_module, stream_id) do
    case repo_module.query("SELECT cursor FROM checkpoint_cursors WHERE stream_id = $1", [
           stream_id
         ]) do
      {:ok, %{rows: [[cursor]]}} when is_integer(cursor) and cursor >= 0 ->
        cursor

      {:ok, %{rows: []}} ->
        nil

      {:ok, _result} ->
        nil

      {:error, reason} ->
        Logger.warning("Failed to load checkpoint cursor for #{stream_id}: #{inspect(reason)}")
        nil
    end
  rescue
    exception ->
      Logger.warning(
        "Exception loading checkpoint cursor for #{stream_id}: #{Exception.message(exception)}"
      )

      nil
  end

  @doc "Persists a stream cursor with upsert semantics for durable checkpoint resume."
  @spec default_save_cursor(module(), String.t(), non_neg_integer()) :: :ok | {:error, term()}
  def default_save_cursor(repo_module, stream_id, cursor)
      when is_integer(cursor) and cursor >= 0 do
    sql =
      """
      INSERT INTO checkpoint_cursors (stream_id, cursor, inserted_at, updated_at)
      VALUES ($1, $2, NOW(), NOW())
      ON CONFLICT (stream_id)
      DO UPDATE SET cursor = EXCLUDED.cursor, updated_at = NOW()
      """

    case repo_module.query(sql, [stream_id, cursor]) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception ->
      {:error, exception}
  end
end
