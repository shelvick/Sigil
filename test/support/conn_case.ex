defmodule FrontierOS.ConnCase do
  @moduledoc """
  Test case template for tests requiring a connection.

  Sets up Phoenix.ConnTest helpers and Ecto sandbox with the
  `start_owner!` pattern for concurrent test isolation.
  All tests using this case template can safely run with `async: true`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import FrontierOS.ConnCase

      @endpoint FrontierOSWeb.Endpoint
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(
        FrontierOS.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, conn: Phoenix.ConnTest.build_conn(), sandbox_owner: pid}
  end
end
