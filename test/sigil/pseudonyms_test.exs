defmodule Sigil.PseudonymsTest do
  @moduledoc """
  Verifies pseudonym context behavior.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Pseudonym}
  @compile {:no_warn_undefined, Sigil.Pseudonyms}

  alias Sigil.Pseudonym
  alias Sigil.Repo

  describe "create_pseudonym/2" do
    test "create_pseudonym persists pseudonym record" do
      attrs = pseudonym_attrs(pseudonym_address: "0xpseudonym-created")

      assert {:ok, pseudonym} = Sigil.Pseudonyms.create_pseudonym("0xowner-1", attrs)
      assert pseudonym.account_address == "0xowner-1"
      assert pseudonym.pseudonym_address == "0xpseudonym-created"
      assert pseudonym.encrypted_private_key == <<1, 2, 3, 4>>

      persisted = Repo.get!(Pseudonym, pseudonym.id)
      assert persisted.account_address == "0xowner-1"
    end

    test "create_pseudonym rejects when limit reached" do
      account_address = "0xowner-limit"

      Enum.each(1..5, fn index ->
        insert_pseudonym!(
          account_address: account_address,
          pseudonym_address: "0xpseudonym-limit-#{index}"
        )
      end)

      assert Sigil.Pseudonyms.create_pseudonym(
               account_address,
               pseudonym_attrs(pseudonym_address: "0xpseudonym-limit-6")
             ) == {:error, :limit_reached}
    end

    test "create_pseudonym atomically enforces the five pseudonym cap", %{
      sandbox_owner: sandbox_owner
    } do
      account_address = "0xowner-concurrency"
      parent = self()

      Enum.each(1..4, fn index ->
        insert_pseudonym!(
          account_address: account_address,
          pseudonym_address: "0xpseudonym-concurrency-#{index}"
        )
      end)

      tasks =
        for suffix <- ["5", "6"] do
          attrs = pseudonym_attrs(pseudonym_address: "0xpseudonym-concurrency-#{suffix}")

          task =
            Task.async(fn ->
              send(parent, {:task_ready, self()})

              receive do
                :go ->
                  Sigil.Pseudonyms.create_pseudonym(account_address, attrs)
              end
            end)

          Ecto.Adapters.SQL.Sandbox.allow(Repo, sandbox_owner, task.pid)
          task_pid = task.pid
          assert_receive {:task_ready, ^task_pid}
          task
        end

      Enum.each(tasks, &send(&1.pid, :go))
      results = Enum.map(tasks, &Task.await(&1, 5_000))

      assert Enum.count(results, &match?({:ok, %{__struct__: Pseudonym}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :limit_reached})) == 1
      assert Repo.aggregate(Pseudonym, :count, :id) == 5
    end

    test "duplicate pseudonym_address is rejected" do
      insert_pseudonym!(
        account_address: "0xowner-existing",
        pseudonym_address: "0xpseudonym-duplicate"
      )

      assert {:error, changeset} =
               Sigil.Pseudonyms.create_pseudonym(
                 "0xowner-other",
                 pseudonym_attrs(pseudonym_address: "0xpseudonym-duplicate")
               )

      assert errors_on(changeset).pseudonym_address == ["has already been taken"]
    end
  end

  describe "list_pseudonyms/1" do
    test "list_pseudonyms returns account-scoped ordered list" do
      older =
        insert_pseudonym!(
          account_address: "0xowner-list",
          pseudonym_address: "0xpseudonym-older"
        )

      newer =
        insert_pseudonym!(
          account_address: "0xowner-list",
          pseudonym_address: "0xpseudonym-newer"
        )

      set_inserted_at!(older.id, ~U[2026-03-26 01:00:00.000000Z])
      set_inserted_at!(newer.id, ~U[2026-03-26 02:00:00.000000Z])

      pseudonyms = Sigil.Pseudonyms.list_pseudonyms("0xowner-list")

      assert Enum.map(pseudonyms, & &1.pseudonym_address) == [
               "0xpseudonym-older",
               "0xpseudonym-newer"
             ]
    end

    test "list_pseudonyms excludes other accounts" do
      mine =
        insert_pseudonym!(account_address: "0xowner-scope", pseudonym_address: "0xpseudonym-mine")

      _other =
        insert_pseudonym!(
          account_address: "0xowner-other",
          pseudonym_address: "0xpseudonym-other"
        )

      pseudonyms = Sigil.Pseudonyms.list_pseudonyms("0xowner-scope")

      assert Enum.map(pseudonyms, & &1.id) == [mine.id]
      refute Enum.any?(pseudonyms, &(&1.account_address == "0xowner-other"))
    end
  end

  describe "get_pseudonym/2" do
    test "get_pseudonym returns owned pseudonym" do
      pseudonym =
        insert_pseudonym!(
          account_address: "0xowner-get",
          pseudonym_address: "0xpseudonym-get"
        )

      assert {:ok, fetched} =
               Sigil.Pseudonyms.get_pseudonym("0xowner-get", "0xpseudonym-get")

      assert fetched.id == pseudonym.id
      assert fetched.account_address == "0xowner-get"
    end

    test "get_pseudonym rejects wrong owner" do
      insert_pseudonym!(account_address: "0xowner-a", pseudonym_address: "0xpseudonym-secret")

      assert Sigil.Pseudonyms.get_pseudonym("0xowner-b", "0xpseudonym-secret") ==
               {:error, :not_found}
    end
  end

  describe "delete_pseudonym/2" do
    test "delete_pseudonym removes record and returns it" do
      pseudonym =
        insert_pseudonym!(
          account_address: "0xowner-delete",
          pseudonym_address: "0xpseudonym-delete"
        )

      assert {:ok, deleted} =
               Sigil.Pseudonyms.delete_pseudonym("0xowner-delete", "0xpseudonym-delete")

      assert deleted.id == pseudonym.id
      assert Repo.get(Pseudonym, pseudonym.id) == nil
    end
  end

  describe "pseudonym_addresses/1" do
    test "pseudonym_addresses returns address list" do
      first =
        insert_pseudonym!(
          account_address: "0xowner-addresses",
          pseudonym_address: "0xpseudonym-address-1"
        )

      second =
        insert_pseudonym!(
          account_address: "0xowner-addresses",
          pseudonym_address: "0xpseudonym-address-2"
        )

      set_inserted_at!(first.id, ~U[2026-03-26 01:00:00.000000Z])
      set_inserted_at!(second.id, ~U[2026-03-26 02:00:00.000000Z])

      assert Sigil.Pseudonyms.pseudonym_addresses("0xowner-addresses") == [
               "0xpseudonym-address-1",
               "0xpseudonym-address-2"
             ]
    end
  end

  defp insert_pseudonym!(attrs) do
    attrs = attrs |> Map.new() |> Map.put_new(:encrypted_private_key, <<1, 2, 3, 4>>)

    new_pseudonym_struct()
    |> Pseudonym.changeset(attrs)
    |> Repo.insert!()
  end

  defp set_inserted_at!(id, inserted_at) do
    {1, nil} =
      Repo.update_all(
        from(pseudonym in Pseudonym, where: pseudonym.id == ^id),
        set: [inserted_at: inserted_at]
      )
  end

  defp pseudonym_attrs(overrides) do
    overrides = Map.new(overrides)

    Map.merge(
      %{
        pseudonym_address: "0xpseudonym-default",
        encrypted_private_key: <<1, 2, 3, 4>>
      },
      overrides
    )
  end

  defp new_pseudonym_struct do
    apply(Pseudonym, :__struct__, [])
  end
end
