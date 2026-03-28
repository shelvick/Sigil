defmodule Sigil.PseudonymTest do
  @moduledoc """
  Verifies pseudonym schema validations and migration-backed persistence.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Pseudonym}

  alias Sigil.Repo

  describe "changeset/2" do
    test "changeset accepts valid pseudonym attributes" do
      changeset = Sigil.Pseudonym.changeset(new_pseudonym_struct(), valid_pseudonym_attrs())

      assert changeset.valid?
      assert get_change(changeset, :account_address) == "0xowner-1"
      assert get_change(changeset, :pseudonym_address) == "0xpseudonym-1"
      assert get_change(changeset, :encrypted_private_key) == <<1, 2, 3, 4>>
    end

    test "changeset validates required fields" do
      changeset = Sigil.Pseudonym.changeset(new_pseudonym_struct(), %{})

      assert errors_on(changeset) == %{
               account_address: ["can't be blank"],
               encrypted_private_key: ["can't be blank"],
               pseudonym_address: ["can't be blank"]
             }
    end

    test "changeset requires 0x-prefixed account and pseudonym addresses" do
      changeset =
        Sigil.Pseudonym.changeset(
          new_pseudonym_struct(),
          valid_pseudonym_attrs(%{
            account_address: "owner-1",
            pseudonym_address: "pseudonym-1"
          })
        )

      refute changeset.valid?
      assert errors_on(changeset).account_address == ["must start with 0x"]
      assert errors_on(changeset).pseudonym_address == ["must start with 0x"]
    end

    test "changeset rejects empty encrypted_private_key" do
      changeset =
        Sigil.Pseudonym.changeset(
          new_pseudonym_struct(),
          valid_pseudonym_attrs(%{encrypted_private_key: <<>>})
        )

      refute changeset.valid?
      assert errors_on(changeset).encrypted_private_key == ["can't be blank"]
    end
  end

  describe "repo integration" do
    test "duplicate pseudonym_address is rejected" do
      assert {:ok, inserted} =
               new_pseudonym_struct()
               |> Sigil.Pseudonym.changeset(valid_pseudonym_attrs())
               |> Repo.insert()

      assert {:error, changeset} =
               new_pseudonym_struct()
               |> Sigil.Pseudonym.changeset(
                 valid_pseudonym_attrs(%{account_address: "0xowner-2"})
               )
               |> Repo.insert()

      assert inserted.pseudonym_address == "0xpseudonym-1"
      assert errors_on(changeset).pseudonym_address == ["has already been taken"]
    end

    test "pseudonyms table exists after migration" do
      columns =
        Repo.query!("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'pseudonyms'
        ORDER BY ordinal_position
        """).rows
        |> List.flatten()

      indexes =
        Repo.query!("""
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = current_schema()
          AND tablename = 'pseudonyms'
        ORDER BY indexname
        """).rows
        |> List.flatten()

      assert columns == [
               "id",
               "account_address",
               "pseudonym_address",
               "encrypted_private_key",
               "inserted_at",
               "updated_at"
             ]

      assert "pseudonyms_account_address_index" in indexes
      assert "pseudonyms_pseudonym_address_index" in indexes
    end
  end

  defp new_pseudonym_struct do
    apply(Sigil.Pseudonym, :__struct__, [])
  end

  defp valid_pseudonym_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        account_address: "0xowner-1",
        pseudonym_address: "0xpseudonym-1",
        encrypted_private_key: <<1, 2, 3, 4>>
      },
      overrides
    )
  end
end
