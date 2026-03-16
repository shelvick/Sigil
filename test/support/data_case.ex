defmodule Sigil.DataCase do
  @moduledoc """
  Test case template for tests requiring database access.

  Sets up Ecto sandbox with the `start_owner!` pattern for
  concurrent test isolation. All tests using this case template
  can safely run with `async: true`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Sigil.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Sigil.DataCase
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(
        Sigil.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, sandbox_owner: pid}
  end

  @doc """
  Helper for returning list of errors in a changeset.

  Returns a map of field names to lists of error messages.

  ## Examples

      assert errors_on(changeset) == %{name: ["can't be blank"]}

  """
  @spec errors_on(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
