defmodule FrontierOSWeb.Telemetry do
  @moduledoc """
  Telemetry supervisor for FrontierOS.

  Defines periodic measurements and metrics for monitoring
  Phoenix endpoint and Ecto repository performance.
  """

  use Supervisor

  import Telemetry.Metrics

  @doc """
  Starts the telemetry supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  @spec init(keyword()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the list of telemetry metrics to track.
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      # Phoenix metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        unit: {:native, :millisecond},
        tags: [:route]
      ),

      # Database metrics
      summary("frontier_os.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("frontier_os.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("frontier_os.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("frontier_os.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      )
    ]
  end

  @spec periodic_measurements() :: [{module(), atom(), list()}]
  defp periodic_measurements do
    []
  end
end
