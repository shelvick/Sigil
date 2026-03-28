defmodule Sigil.Pseudonyms do
  @moduledoc """
  Repo-backed pseudonym identity management.
  """

  import Ecto.Query

  alias Sigil.Pseudonym
  alias Sigil.Repo

  @max_pseudonyms_per_account 5

  @doc "Creates a pseudonym for an account when it is still below the five-identity cap."
  @spec create_pseudonym(String.t(), map()) ::
          {:ok, Pseudonym.t()} | {:error, Ecto.Changeset.t() | :limit_reached}
  def create_pseudonym(account_address, attrs)
      when is_binary(account_address) and is_map(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("account_address", account_address)

    case Repo.transaction(fn ->
           lock_account(account_address)

           if pseudonym_count(account_address) >= @max_pseudonyms_per_account do
             Repo.rollback(:limit_reached)
           end

           case %Pseudonym{} |> Pseudonym.changeset(attrs) |> Repo.insert() do
             {:ok, pseudonym} -> pseudonym
             {:error, changeset} -> Repo.rollback(changeset)
           end
         end) do
      {:ok, pseudonym} -> {:ok, pseudonym}
      {:error, :limit_reached} -> {:error, :limit_reached}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @doc "Lists pseudonyms owned by an account in creation order."
  @spec list_pseudonyms(String.t()) :: [Pseudonym.t()]
  def list_pseudonyms(account_address) when is_binary(account_address) do
    Repo.all(
      from pseudonym in Pseudonym,
        where: pseudonym.account_address == ^account_address,
        order_by: [asc: pseudonym.inserted_at, asc: pseudonym.id]
    )
  end

  @doc "Fetches a pseudonym only when it belongs to the given account."
  @spec get_pseudonym(String.t(), String.t()) :: {:ok, Pseudonym.t()} | {:error, :not_found}
  def get_pseudonym(account_address, pseudonym_address)
      when is_binary(account_address) and is_binary(pseudonym_address) do
    case Repo.get_by(Pseudonym,
           account_address: account_address,
           pseudonym_address: pseudonym_address
         ) do
      %Pseudonym{} = pseudonym -> {:ok, pseudonym}
      nil -> {:error, :not_found}
    end
  end

  @doc "Deletes a pseudonym only when it belongs to the given account."
  @spec delete_pseudonym(String.t(), String.t()) :: {:ok, Pseudonym.t()} | {:error, :not_found}
  def delete_pseudonym(account_address, pseudonym_address)
      when is_binary(account_address) and is_binary(pseudonym_address) do
    case get_pseudonym(account_address, pseudonym_address) do
      {:ok, %Pseudonym{} = pseudonym} -> Repo.delete(pseudonym)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc "Returns the ordered pseudonym address list for an account."
  @spec pseudonym_addresses(String.t()) :: [String.t()]
  def pseudonym_addresses(account_address) when is_binary(account_address) do
    account_address
    |> list_pseudonyms()
    |> Enum.map(& &1.pseudonym_address)
  end

  @spec lock_account(String.t()) :: :ok
  defp lock_account(account_address) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1)::bigint)", [account_address])
    :ok
  end

  @spec pseudonym_count(String.t()) :: non_neg_integer()
  defp pseudonym_count(account_address) do
    Repo.one(
      from pseudonym in Pseudonym,
        where: pseudonym.account_address == ^account_address,
        select: count(pseudonym.id)
    )
  end

  @spec stringify_keys(map()) :: map()
  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
