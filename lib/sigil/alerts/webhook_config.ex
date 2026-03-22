defmodule Sigil.Alerts.WebhookConfig do
  @moduledoc """
  Per-tribe webhook delivery configuration.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @valid_service_types ~w(discord)

  @typedoc "Persisted webhook configuration."
  @type t() :: %__MODULE__{
          id: integer() | nil,
          tribe_id: integer() | nil,
          webhook_url: String.t() | nil,
          service_type: String.t() | nil,
          enabled: boolean() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "webhook_configs" do
    field :tribe_id, :integer
    field :webhook_url, :string
    field :service_type, :string
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Builds a changeset for a webhook configuration."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:tribe_id, :webhook_url, :service_type, :enabled])
    |> put_default_service_type()
    |> validate_required([:tribe_id, :webhook_url])
    |> validate_inclusion(:service_type, @valid_service_types)
  end

  @spec put_default_service_type(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp put_default_service_type(changeset) do
    if is_nil(get_field(changeset, :service_type)) do
      put_change(changeset, :service_type, "discord")
    else
      changeset
    end
  end
end
