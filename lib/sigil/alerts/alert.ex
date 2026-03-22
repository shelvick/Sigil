defmodule Sigil.Alerts.Alert do
  @moduledoc """
  Alert persistence schema and lifecycle changesets.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @valid_types ~w(fuel_low fuel_critical assembly_offline extension_changed hostile_activity)
  @valid_severities ~w(info warning critical)
  @valid_statuses ~w(new acknowledged dismissed)

  @typedoc "Persisted alert record."
  @type t() :: %__MODULE__{
          id: integer() | nil,
          type: String.t() | nil,
          severity: String.t() | nil,
          status: String.t() | nil,
          assembly_id: String.t() | nil,
          assembly_name: String.t() | nil,
          account_address: String.t() | nil,
          tribe_id: integer() | nil,
          message: String.t() | nil,
          metadata: map() | nil,
          dismissed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "alerts" do
    field :type, :string
    field :severity, :string
    field :status, :string
    field :assembly_id, :string
    field :assembly_name, :string
    field :account_address, :string
    field :tribe_id, :integer
    field :message, :string
    field :metadata, :map, default: %{}
    field :dismissed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Builds a changeset for creating or updating an alert record."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [
      :type,
      :severity,
      :status,
      :assembly_id,
      :assembly_name,
      :account_address,
      :tribe_id,
      :message,
      :metadata,
      :dismissed_at
    ])
    |> put_default_metadata()
    |> validate_required([
      :type,
      :severity,
      :status,
      :assembly_id,
      :assembly_name,
      :account_address,
      :message
    ])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:severity, @valid_severities)
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Builds a restricted changeset for alert lifecycle transitions."
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(alert, attrs) do
    alert
    |> cast(attrs, [:status, :dismissed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @spec put_default_metadata(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp put_default_metadata(changeset) do
    case fetch_change(changeset, :metadata) do
      {:ok, nil} ->
        put_change(changeset, :metadata, %{})

      :error ->
        if is_nil(get_field(changeset, :metadata)) do
          put_change(changeset, :metadata, %{})
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
