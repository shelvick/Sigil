defmodule Sigil.Intel.IntelListing do
  @moduledoc """
  Ecto schema for persisted intel marketplace listings.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  @type listing_status() :: :active | :sold | :cancelled

  @typedoc """
  Local persistence model for an on-chain intel marketplace listing.
  """
  @type t() :: %__MODULE__{
          id: String.t() | nil,
          seller_address: String.t() | nil,
          seal_id: String.t() | nil,
          encrypted_blob_id: String.t() | nil,
          client_nonce: integer() | nil,
          price_mist: integer() | nil,
          report_type: integer() | nil,
          solar_system_id: integer() | nil,
          description: String.t() | nil,
          status: listing_status() | nil,
          buyer_address: String.t() | nil,
          restricted_to_tribe_id: integer() | nil,
          intel_report_id: Ecto.UUID.t() | nil,
          on_chain_digest: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @create_required [
    :id,
    :seller_address,
    :client_nonce,
    :price_mist,
    :report_type,
    :solar_system_id,
    :status
  ]
  @create_optional [
    :description,
    :buyer_address,
    :restricted_to_tribe_id,
    :intel_report_id,
    :on_chain_digest,
    :seal_id,
    :encrypted_blob_id
  ]
  @status_fields [:status, :buyer_address, :on_chain_digest]
  @valid_statuses [:active, :sold, :cancelled]
  @valid_report_types [1, 2]

  schema "intel_listings" do
    field :seller_address, :string
    field :seal_id, :string
    field :encrypted_blob_id, :string
    field :client_nonce, :integer
    field :price_mist, :integer
    field :report_type, :integer
    field :solar_system_id, :integer
    field :description, :string
    field :status, Ecto.Enum, values: @valid_statuses
    field :buyer_address, :string
    field :restricted_to_tribe_id, :integer
    field :intel_report_id, :string
    field :on_chain_digest, :string

    timestamps()
  end

  @doc """
  Builds a changeset for creating or refreshing an intel listing.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(listing, attrs) do
    listing
    |> cast(attrs, @create_required ++ @create_optional)
    |> validate_required(@create_required)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:report_type, @valid_report_types)
    |> validate_number(:price_mist, greater_than: 0)
    |> validate_number(:solar_system_id, greater_than_or_equal_to: 0)
    |> validate_length(:description, max: 500)
    |> unique_constraint(:id, name: :intel_listings_pkey)
  end

  @doc """
  Builds a restricted changeset for purchase and cancellation updates.
  """
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(listing, attrs) do
    listing
    |> cast(attrs, @status_fields)
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
