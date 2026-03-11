defmodule FrontierOS.Application do
  @moduledoc """
  OTP Application for FrontierOS.

  Starts the supervision tree with Telemetry, Repo, PubSub, and Endpoint.
  """

  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      FrontierOSWeb.Telemetry,
      FrontierOS.Repo,
      {Phoenix.PubSub, name: FrontierOS.PubSub},
      FrontierOSWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: FrontierOS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Callback invoked when the endpoint configuration changes at runtime.
  """
  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    FrontierOSWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
