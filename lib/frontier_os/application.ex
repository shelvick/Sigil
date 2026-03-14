defmodule FrontierOS.Application do
  @moduledoc """
  OTP Application for FrontierOS.

  Starts the supervision tree with Telemetry, Repo, PubSub, Cache, optional
  StaticData, and Endpoint.
  """

  use Application

  @cache_tables [:assemblies, :characters, :standings, :accounts, :tribes]

  @doc false
  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children =
      [
        FrontierOSWeb.Telemetry,
        FrontierOS.Repo,
        {Phoenix.PubSub, name: FrontierOS.PubSub},
        cache_child()
      ] ++ maybe_static_data() ++ [FrontierOSWeb.Endpoint]

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

  @spec cache_child() :: Supervisor.child_spec()
  defp cache_child do
    Supervisor.child_spec({FrontierOS.Cache, tables: @cache_tables}, id: FrontierOS.Cache)
  end

  @spec maybe_static_data() :: [Supervisor.child_spec()]
  defp maybe_static_data do
    if Application.get_env(:frontier_os, :start_static_data, true) do
      [
        Supervisor.child_spec(
          {FrontierOS.StaticData, dets_dir: static_data_dir()},
          id: FrontierOS.StaticData
        )
      ]
    else
      []
    end
  end

  @spec static_data_dir() :: String.t()
  defp static_data_dir do
    Application.get_env(
      :frontier_os,
      :static_data_dir,
      Application.app_dir(:frontier_os, "priv/static_data")
    )
  end
end
