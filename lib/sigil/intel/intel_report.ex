defmodule Sigil.Intel.IntelReport do
  @moduledoc """
  Ecto schema for tribe-scoped intel reports.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: {Ecto.UUID, :generate, []}}
  @timestamps_opts [type: :utc_datetime_usec]

  @type report_type() :: :location | :scouting

  @typedoc """
  Intel report persisted for a tribe.
  """
  @type t() :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          tribe_id: integer() | nil,
          assembly_id: String.t() | nil,
          solar_system_id: integer() | nil,
          label: String.t() | nil,
          report_type: report_type() | nil,
          notes: String.t() | nil,
          reported_by: String.t() | nil,
          reported_by_name: String.t() | nil,
          reported_by_character_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @location_required_fields [
    :tribe_id,
    :assembly_id,
    :reported_by,
    :reported_by_character_id
  ]
  @scouting_required_fields [
    :tribe_id,
    :reported_by,
    :reported_by_character_id,
    :notes
  ]
  @optional_fields [:solar_system_id, :label, :notes, :reported_by_name]
  @all_fields @location_required_fields ++ @optional_fields

  schema "intel_reports" do
    field :tribe_id, :integer
    field :assembly_id, :string
    field :solar_system_id, :integer
    field :label, :string
    field :report_type, Ecto.Enum, values: [:location, :scouting]
    field :notes, :string
    field :reported_by, :string
    field :reported_by_name, :string
    field :reported_by_character_id, :string

    timestamps()
  end

  @doc """
  Builds a changeset for assembly location reports.
  """
  @spec location_changeset(t(), map()) :: Ecto.Changeset.t()
  def location_changeset(report, attrs) do
    report
    |> cast(attrs, @all_fields)
    |> put_change(:report_type, :location)
    |> validate_required(@location_required_fields)
    |> validate_shared_fields()
    |> unique_constraint(:assembly_id, name: :intel_reports_tribe_assembly_location_idx)
  end

  @doc """
  Builds a changeset for scouting reports.
  """
  @spec scouting_changeset(t(), map()) :: Ecto.Changeset.t()
  def scouting_changeset(report, attrs) do
    report
    |> cast(attrs, @all_fields)
    |> put_change(:report_type, :scouting)
    |> validate_required(@scouting_required_fields)
    |> validate_shared_fields()
  end

  @spec validate_shared_fields(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_shared_fields(changeset) do
    changeset
    |> validate_number(:solar_system_id, greater_than_or_equal_to: 0)
    |> validate_length(:label, max: 120)
    |> validate_length(:notes, max: 1000)
  end
end
