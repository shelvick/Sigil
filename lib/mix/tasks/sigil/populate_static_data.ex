defmodule Mix.Tasks.Sigil.PopulateStaticData do
  @moduledoc """
  Fetches World API static data and writes DETS files into `priv/static_data`.
  """

  use Mix.Task

  alias Sigil.StaticData.Constellation
  alias Sigil.StaticData.DetsFile
  alias Sigil.StaticData.ItemType
  alias Sigil.StaticData.SolarSystem

  @shortdoc "Populate DETS static data files"
  @table_order [:item_types, :solar_systems, :constellations]
  @cli_names %{
    item_types: "types",
    solar_systems: "solar_systems",
    constellations: "constellations"
  }
  @labels %{
    item_types: "Item Types",
    solar_systems: "Solar Systems",
    constellations: "Constellations"
  }
  @table_metadata %{
    solar_systems: %{fetch: :fetch_solar_systems, parser: &SolarSystem.from_json/1},
    item_types: %{fetch: :fetch_types, parser: &ItemType.from_json/1},
    constellations: %{fetch: :fetch_constellations, parser: &Constellation.from_json/1}
  }

  @doc "Runs the static data population task."
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args), do: run(args, [])

  @doc """
  Runs the task with injectable options for test isolation.

  Accepts `:output_dir` and `:world_client` to avoid reading global
  Application env, enabling in-process testing without subprocesses.
  """
  @spec run([String.t()], keyword()) :: :ok
  def run(args, opts) do
    selected_tables = parse_args!(args)

    {:ok, _apps} = Application.ensure_all_started(:req)

    output_dir =
      Keyword.get_lazy(opts, :output_dir, fn ->
        Application.get_env(
          :sigil,
          :static_data_dir,
          Application.app_dir(:sigil, "priv/static_data")
        )
      end)

    client = Keyword.get_lazy(opts, :world_client, fn -> world_client() end)

    File.mkdir_p!(output_dir)

    Mix.shell().info("Sigil Static Data Population")
    Mix.shell().info("==================================")

    results = Enum.map(selected_tables, &populate_table(&1, output_dir, client))
    success_count = Enum.count(results, &match?({_, {:ok, _}}, &1))

    Mix.shell().info("==================================")

    total_count = length(selected_tables)
    Mix.shell().info("Done. #{success_count}/#{total_count} types populated successfully.")

    if success_count < total_count do
      failed_tables =
        Enum.map_join(
          Enum.filter(results, fn {_table_name, result} -> match?({:error, _}, result) end),
          ",",
          fn {table_name, _result} -> Map.fetch!(@cli_names, table_name) end
        )

      Mix.shell().info("Run with --only #{failed_tables} to retry failed types.")
    end

    :ok
  end

  @spec parse_args!([String.t()]) :: [atom()]
  defp parse_args!(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: [only: :string])

    case invalid do
      [] -> parse_only_option(Keyword.get(opts, :only))
      [{option, _value} | _rest] -> Mix.raise("Unknown option: #{option}")
    end
  end

  @spec parse_only_option(String.t() | nil) :: [atom()]
  defp parse_only_option(nil), do: @table_order

  defp parse_only_option(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&table_name_from_cli!/1)
  end

  @spec table_name_from_cli!(String.t()) :: atom()
  defp table_name_from_cli!("types"), do: :item_types
  defp table_name_from_cli!("solar_systems"), do: :solar_systems
  defp table_name_from_cli!("constellations"), do: :constellations

  defp table_name_from_cli!(value) do
    Mix.raise("Unknown type: #{value}. Valid: types, solar_systems, constellations")
  end

  @spec populate_table(atom(), String.t(), module()) ::
          {atom(), {:ok, non_neg_integer()} | {:error, term()}}
  defp populate_table(table_name, output_dir, world_client) do
    Mix.shell().info("Fetching #{fetch_label(table_name)}...")

    path = DetsFile.dets_path(output_dir, table_name)

    result =
      case fetch_rows(table_name, world_client) do
        {:ok, rows} ->
          DetsFile.write_rows!(path, rows)

          Mix.shell().info(
            "  #{Map.fetch!(@labels, table_name)}: OK (#{length(rows)} records, #{path})"
          )

          {:ok, length(rows)}

        {:error, reason} ->
          File.rm(path)
          Mix.shell().info("  #{Map.fetch!(@labels, table_name)}: FAILED (#{inspect(reason)})")
          {:error, reason}
      end

    {table_name, result}
  end

  @spec fetch_label(atom()) :: String.t()
  defp fetch_label(:item_types), do: "item types"
  defp fetch_label(:solar_systems), do: "solar systems"
  defp fetch_label(:constellations), do: "constellations"

  @spec world_client() :: module()
  defp world_client do
    Application.fetch_env!(:sigil, :world_client)
  end

  @spec fetch_rows(atom(), module()) :: {:ok, [{integer(), struct()}]} | {:error, term()}
  defp fetch_rows(table_name, world_client) do
    meta = Map.fetch!(@table_metadata, table_name)

    case apply(world_client, meta.fetch, [[]]) do
      {:ok, records} when is_list(records) ->
        {:ok,
         Enum.map(records, fn record ->
           parsed = meta.parser.(record)
           {parsed.id, parsed}
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
