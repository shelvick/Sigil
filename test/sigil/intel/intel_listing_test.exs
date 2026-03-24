defmodule Sigil.Intel.IntelListingTest do
  @moduledoc """
  Verifies intel listing schema validations and migration-backed persistence.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Intel.IntelListing}

  alias Sigil.Intel.IntelListing
  alias Sigil.Repo

  describe "changeset/2" do
    test "changeset accepts valid listing params" do
      changeset = IntelListing.changeset(new_listing_struct(), valid_listing_params())

      assert changeset.valid?
      assert get_change(changeset, :id) == "0xlisting-1"
      assert get_change(changeset, :client_nonce) == 42
      assert get_change(changeset, :status) == :active
    end

    test "changeset rejects missing required fields" do
      changeset = IntelListing.changeset(new_listing_struct(), %{})

      refute changeset.valid?

      assert errors_on(changeset) == %{
               client_nonce: ["can't be blank"],
               commitment_hash: ["can't be blank"],
               id: ["can't be blank"],
               price_mist: ["can't be blank"],
               report_type: ["can't be blank"],
               seller_address: ["can't be blank"],
               solar_system_id: ["can't be blank"],
               status: ["can't be blank"]
             }
    end

    test "changeset rejects zero or negative price" do
      zero_changeset =
        IntelListing.changeset(new_listing_struct(), valid_listing_params(%{price_mist: 0}))

      negative_changeset =
        IntelListing.changeset(new_listing_struct(), valid_listing_params(%{price_mist: -1}))

      refute zero_changeset.valid?
      refute negative_changeset.valid?
      assert errors_on(zero_changeset).price_mist == ["must be greater than 0"]
      assert errors_on(negative_changeset).price_mist == ["must be greater than 0"]
    end

    test "changeset rejects invalid report_type" do
      changeset =
        IntelListing.changeset(new_listing_struct(), valid_listing_params(%{report_type: 9}))

      refute changeset.valid?
      assert errors_on(changeset).report_type == ["is invalid"]
    end

    test "changeset rejects description over 500 characters" do
      changeset =
        IntelListing.changeset(
          new_listing_struct(),
          valid_listing_params(%{description: String.duplicate("d", 501)})
        )

      refute changeset.valid?
      assert errors_on(changeset).description == ["should be at most 500 character(s)"]
    end

    test "changeset accepts optional intel_report_id linkage" do
      intel_report_id = Ecto.UUID.generate()

      changeset =
        IntelListing.changeset(
          new_listing_struct(),
          valid_listing_params(%{intel_report_id: intel_report_id})
        )

      assert changeset.valid?
      assert get_change(changeset, :intel_report_id) == intel_report_id
    end

    test "changeset preserves existing intel_report_id when omitted" do
      intel_report_id = Ecto.UUID.generate()

      listing =
        new_listing_struct()
        |> Map.put(:intel_report_id, intel_report_id)

      changeset =
        IntelListing.changeset(
          listing,
          valid_listing_params()
          |> Map.delete(:intel_report_id)
        )

      assert changeset.valid?
      assert get_field(changeset, :intel_report_id) == intel_report_id
    end
  end

  describe "status_changeset/2" do
    test "status_changeset updates status and buyer_address" do
      listing =
        new_listing_struct()
        |> Map.merge(%{
          status: :active,
          buyer_address: nil,
          on_chain_digest: nil
        })

      changeset =
        IntelListing.status_changeset(listing, %{
          status: :sold,
          buyer_address: "0xbuyer-1",
          on_chain_digest: "digest-1"
        })

      assert changeset.valid?

      assert changeset.changes == %{
               buyer_address: "0xbuyer-1",
               on_chain_digest: "digest-1",
               status: :sold
             }
    end
  end

  describe "repo integration" do
    test "listing persists to database with all fields" do
      assert {:ok, listing} =
               new_listing_struct()
               |> IntelListing.changeset(
                 valid_listing_params(%{
                   buyer_address: "0xbuyer-1",
                   description: "Encrypted wormhole route",
                   intel_report_id: Ecto.UUID.generate(),
                   on_chain_digest: "digest-1",
                   restricted_to_tribe_id: 404,
                   status: :sold
                 })
               )
               |> Repo.insert()

      persisted = Repo.get(IntelListing, listing.id)

      assert persisted.seller_address == "0xseller-1"
      assert persisted.client_nonce == 42
      assert persisted.price_mist == 1_500_000_000
      assert persisted.status == :sold
      assert persisted.buyer_address == "0xbuyer-1"
      assert persisted.restricted_to_tribe_id == 404
      assert persisted.on_chain_digest == "digest-1"
    end

    test "listing persists descriptions up to 500 characters" do
      description = String.duplicate("d", 500)

      assert {:ok, listing} =
               new_listing_struct()
               |> IntelListing.changeset(
                 valid_listing_params(%{id: "0xlisting-500", description: description})
               )
               |> Repo.insert()

      persisted = Repo.get(IntelListing, listing.id)

      assert persisted.description == description
    end

    test "intel_listings table exists after migration" do
      columns =
        Repo.query!("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'intel_listings'
        ORDER BY ordinal_position
        """).rows
        |> List.flatten()

      indexes =
        Repo.query!("""
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = current_schema()
          AND tablename = 'intel_listings'
        ORDER BY indexname
        """).rows
        |> List.flatten()

      assert columns == [
               "id",
               "seller_address",
               "commitment_hash",
               "client_nonce",
               "price_mist",
               "report_type",
               "solar_system_id",
               "description",
               "status",
               "buyer_address",
               "restricted_to_tribe_id",
               "intel_report_id",
               "on_chain_digest",
               "inserted_at",
               "updated_at"
             ]

      assert "intel_listings_status_index" in indexes
      assert "intel_listings_seller_address_index" in indexes
      assert "intel_listings_solar_system_id_index" in indexes
      assert "intel_listings_restricted_to_tribe_id_index" in indexes
    end
  end

  defp new_listing_struct do
    apply(IntelListing, :__struct__, [])
  end

  defp valid_listing_params(overrides \\ %{}) do
    Map.merge(
      %{
        id: "0xlisting-1",
        seller_address: "0xseller-1",
        commitment_hash: "12345678901234567890",
        client_nonce: 42,
        price_mist: 1_500_000_000,
        report_type: 1,
        solar_system_id: 30_001_042,
        description: "Scout route intel",
        status: :active,
        buyer_address: nil,
        restricted_to_tribe_id: nil,
        on_chain_digest: nil
      },
      overrides
    )
  end
end
