defmodule Sigil.ConnCase do
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
      import Phoenix.LiveViewTest, except: [live: 2, live_isolated: 3]
      import Sigil.ConnCase
      require Phoenix.ConnTest

      @endpoint SigilWeb.Endpoint
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(
        Sigil.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    liveview_tracker = start_supervised!({Agent, fn -> [] end})

    on_exit(fn ->
      if Process.alive?(liveview_tracker) do
        liveview_tracker
        |> Agent.get(&Enum.uniq(&1))
        |> Enum.each(fn liveview_pid ->
          if Process.alive?(liveview_pid) do
            try do
              GenServer.stop(liveview_pid, :normal, :infinity)
            catch
              :exit, _reason -> :ok
            end
          end
        end)
      end
    end)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_private(:sigil_liveview_tracker, liveview_tracker)

    {:ok, conn: conn, sandbox_owner: pid}
  end

  @doc false
  def live(conn, path) when is_binary(path) do
    dispatched_conn = Phoenix.ConnTest.dispatch(conn, SigilWeb.Endpoint, :get, path, nil)
    result = Phoenix.LiveViewTest.__live__(dispatched_conn, path, [])

    track_liveview_result(conn, result)
  end

  @doc false
  def live_isolated(conn, live_view, opts \\ []) when is_list(opts) do
    result = Phoenix.LiveViewTest.__isolated__(conn, SigilWeb.Endpoint, live_view, opts)
    track_liveview_result(conn, result)
  end

  @doc false
  def track_liveview_result(conn, {:ok, view, html}) do
    case conn.private[:sigil_liveview_tracker] do
      nil -> :ok
      tracker -> Agent.update(tracker, &[view.pid | &1])
    end

    {:ok, view, html}
  end

  @doc false
  def track_liveview_result(_conn, result), do: result
end
