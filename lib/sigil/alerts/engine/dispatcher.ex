defmodule Sigil.Alerts.Engine.Dispatcher do
  @moduledoc """
  Internal helpers for alert-engine webhook dispatch and test ownership wiring.
  """

  require Logger

  alias Sigil.Alerts.{Alert, WebhookConfig}

  @doc "Starts asynchronous webhook delivery with the required test allowances."
  @spec default_dispatch(Alert.t(), WebhookConfig.t(), module(), keyword(), pid(), pid() | nil) ::
          :ok
  def default_dispatch(alert, config, notifier, notifier_opts, owner_pid, mock_owner) do
    stub_name = req_test_stub_name(notifier_opts)

    {:ok, _pid} =
      Task.start(fn ->
        allow_dispatch_dependencies(owner_pid, mock_owner || owner_pid, notifier, stub_name)
        deliver_safely(alert, config, notifier, notifier_opts)
      end)

    :ok
  end

  @doc "Allows the current process to use a Mox-owned notifier when needed."
  @spec maybe_allow_mock_owner(pid() | nil, module()) :: :ok
  def maybe_allow_mock_owner(owner, _notifier) when owner in [nil, self()], do: :ok

  def maybe_allow_mock_owner(owner, notifier) do
    mox = Module.concat([Mox])

    case {Code.ensure_loaded?(mox), function_exported?(mox, :allow, 3), notifier} do
      {true, true, notifier} ->
        if String.ends_with?(Atom.to_string(notifier), "Mock") do
          mox.allow(notifier, owner, self())
        end

        :ok

      _other ->
        :ok
    end
  end

  @doc "Allows the current process to use a Req.Test stub owned by another process."
  @spec maybe_allow_req_test_owner(pid(), keyword()) :: :ok
  def maybe_allow_req_test_owner(owner, notifier_opts) when is_pid(owner) do
    req_test = Module.concat([Req, Test])

    case {Code.ensure_loaded?(req_test), function_exported?(req_test, :allow, 3),
          req_test_stub_name(notifier_opts)} do
      {true, true, stub_name} when not is_nil(stub_name) ->
        req_test.allow(stub_name, owner, self())
        :ok

      _other ->
        :ok
    end
  end

  @spec allow_dispatch_dependencies(pid(), pid(), module(), term() | nil) :: :ok
  defp allow_dispatch_dependencies(owner_pid, mock_owner, notifier, stub_name) do
    :ok = maybe_allow_mock_owner(mock_owner, notifier)

    if not is_nil(stub_name) do
      req_test = Module.concat([Req, Test])

      if Code.ensure_loaded?(req_test) and function_exported?(req_test, :allow, 3) do
        req_test.allow(stub_name, owner_pid, self())
      end
    end

    :ok
  rescue
    _error -> :ok
  end

  @spec deliver_safely(Alert.t(), WebhookConfig.t(), module(), keyword()) :: :ok
  defp deliver_safely(alert, config, notifier, notifier_opts) do
    try do
      case notifier.deliver(alert, config, notifier_opts) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("alert engine notifier delivery failed: #{inspect(reason)}")
          :ok
      end
    rescue
      error ->
        Logger.warning("alert engine notifier task failed: #{Exception.message(error)}")
        :ok
    catch
      kind, reason ->
        Logger.warning("alert engine notifier task failed: #{inspect({kind, reason})}")
        :ok
    end
  end

  @spec req_test_stub_name(keyword()) :: term() | nil
  defp req_test_stub_name(notifier_opts) do
    case notifier_opts |> Keyword.get(:req_options, []) |> Keyword.get(:plug) do
      {Req.Test, stub_name} -> stub_name
      _other -> nil
    end
  end
end
