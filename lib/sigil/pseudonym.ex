defmodule Sigil.Pseudonym do
  @moduledoc """
  Ecto schema for persisted pseudonym identities.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  @typedoc "Persisted pseudonym record."
  @type t() :: %__MODULE__{
          id: integer() | nil,
          account_address: String.t() | nil,
          pseudonym_address: String.t() | nil,
          encrypted_private_key: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pseudonyms" do
    field :account_address, :string
    field :pseudonym_address, :string
    field :encrypted_private_key, :binary

    timestamps()
  end

  @doc "Builds a changeset for creating or updating a pseudonym record."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pseudonym, attrs) do
    pseudonym
    |> cast(attrs, [:account_address, :pseudonym_address, :encrypted_private_key])
    |> validate_required([:account_address, :pseudonym_address, :encrypted_private_key])
    |> validate_prefix(:account_address)
    |> validate_prefix(:pseudonym_address)
    |> validate_non_empty_binary(:encrypted_private_key)
    |> unique_constraint(:pseudonym_address)
  end

  @spec validate_prefix(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_prefix(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if String.starts_with?(value, "0x") do
        []
      else
        [{field, "must start with 0x"}]
      end
    end)
  end

  @spec validate_non_empty_binary(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_non_empty_binary(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and byte_size(value) > 0 do
        []
      else
        [{field, "can't be blank"}]
      end
    end)
  end
end
