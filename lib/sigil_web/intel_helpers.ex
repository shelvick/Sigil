defmodule SigilWeb.IntelHelpers do
  @moduledoc """
  Shared display helpers for intel LiveViews.
  """

  @doc """
  Formats a timestamp relative to the provided `now` time.
  """
  @spec relative_timestamp_label(DateTime.t(), DateTime.t()) :: String.t()
  def relative_timestamp_label(%DateTime{} = timestamp, %DateTime{} = now) do
    now
    |> DateTime.diff(timestamp, :second)
    |> max(0)
    |> relative_bucket_label(timestamp)
  end

  @doc """
  Formats a timestamp relative to the current UTC time.
  """
  @spec relative_timestamp_label(DateTime.t()) :: String.t()
  def relative_timestamp_label(%DateTime{} = timestamp) do
    relative_timestamp_label(timestamp, DateTime.utc_now())
  end

  @spec relative_bucket_label(non_neg_integer(), DateTime.t()) :: String.t()
  defp relative_bucket_label(seconds_ago, _timestamp) when seconds_ago < 60, do: "Just now"

  defp relative_bucket_label(seconds_ago, _timestamp) when seconds_ago < 3_600,
    do: "#{div(seconds_ago, 60)}m ago"

  defp relative_bucket_label(seconds_ago, _timestamp) when seconds_ago < 86_400,
    do: "#{div(seconds_ago, 3_600)}h ago"

  defp relative_bucket_label(seconds_ago, _timestamp) when seconds_ago < 604_800,
    do: "#{div(seconds_ago, 86_400)}d ago"

  defp relative_bucket_label(_seconds_ago, timestamp),
    do: Calendar.strftime(timestamp, "%b %d, %Y %H:%M UTC")
end
