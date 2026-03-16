defmodule Sigil.StaticData.DetsFile do
  @moduledoc """
  DETS file operations for static data: open, write, and path resolution.

  Uses a bounded pool of predeclared table names to avoid creating atoms
  from runtime paths.
  """

  @slot_count 128
  @slots List.to_tuple(for(index <- 0..(@slot_count - 1), do: :"sigil_static_data_slot_#{index}"))

  @dets_filenames %{
    solar_systems: "solar_systems.dets",
    item_types: "item_types.dets",
    constellations: "constellations.dets"
  }

  @doc "Opens a DETS file without creating atoms from runtime paths."
  @spec open_file(String.t()) :: {:ok, atom()} | {:error, term()}
  def open_file(path) do
    do_open_file(path, 0)
  end

  @doc "Returns the DETS file path for a given table name within a directory."
  @spec dets_path(String.t(), atom()) :: String.t()
  def dets_path(dir, table_name) do
    Path.join(dir, Map.fetch!(@dets_filenames, table_name))
  end

  @doc "Writes `{id, struct}` tuples to a DETS file, replacing any existing contents."
  @spec write_rows!(String.t(), [{integer(), struct()}]) :: :ok
  def write_rows!(path, rows) do
    {:ok, dets_ref} = open_file(path)

    :ok = :dets.delete_all_objects(dets_ref)
    :ok = :dets.insert(dets_ref, rows)
    :ok = :dets.sync(dets_ref)
    :ok = :dets.close(dets_ref)
  end

  @spec do_open_file(String.t(), non_neg_integer()) :: {:ok, atom()} | {:error, term()}
  defp do_open_file(_path, attempt) when attempt >= @slot_count do
    {:error, :no_available_dets_slot}
  end

  defp do_open_file(path, attempt) do
    slot = slot_for(path, attempt)

    case :dets.open_file(slot, file: String.to_charlist(path), type: :set) do
      {:error, :incompatible_arguments} -> do_open_file(path, attempt + 1)
      result -> result
    end
  end

  @spec slot_for(String.t(), non_neg_integer()) :: atom()
  defp slot_for(path, attempt) do
    index = rem(:erlang.phash2(path, @slot_count) + attempt, @slot_count)
    elem(@slots, index)
  end
end
