defmodule Sigil.GameState.AssemblyEventParserTest do
  @moduledoc """
  Covers assembly event parsing helpers used by the assembly event router.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.GameState.AssemblyEventParser}

  alias Sigil.GameState.AssemblyEventParser

  @assembly_event_types [
    :assembly_status_changed,
    :assembly_fuel_changed,
    :assembly_extension_authorized
  ]

  test "assembly_event? returns true for all assembly event types" do
    Enum.each(@assembly_event_types, fn event_type ->
      assert AssemblyEventParser.assembly_event?(event_type)
    end)
  end

  test "assembly_event? returns false for non-assembly event types" do
    Enum.each([:killmail_created, :jump, :priority_list_updated, :unknown_event], fn event_type ->
      refute AssemblyEventParser.assembly_event?(event_type)
    end)
  end

  test "extracts assembly_id from status changed event" do
    assert {:ok, "0xabc"} =
             AssemblyEventParser.extract_assembly_id(
               :assembly_status_changed,
               %{"assembly_id" => "0xabc", "status" => "ONLINE"}
             )
  end

  test "extracts assembly_id from fuel event" do
    assert {:ok, "0xdef"} =
             AssemblyEventParser.extract_assembly_id(
               :assembly_fuel_changed,
               %{"assembly_id" => "0xdef", "new_quantity" => "10"}
             )
  end

  test "extracts assembly_id from extension authorized event" do
    assert {:ok, "0x123"} =
             AssemblyEventParser.extract_assembly_id(
               :assembly_extension_authorized,
               %{"assembly_id" => "0x123", "extension_type" => "gate"}
             )
  end

  test "returns error when assembly_id key is missing from raw data" do
    assert {:error, :missing_assembly_id} =
             AssemblyEventParser.extract_assembly_id(
               :assembly_status_changed,
               %{"status" => "ONLINE"}
             )
  end

  test "returns error when assembly_id is nil or empty string" do
    assert {:error, :missing_assembly_id} =
             AssemblyEventParser.extract_assembly_id(
               :assembly_fuel_changed,
               %{"assembly_id" => nil}
             )

    assert {:error, :missing_assembly_id} =
             AssemblyEventParser.extract_assembly_id(
               :assembly_extension_authorized,
               %{"assembly_id" => ""}
             )
  end

  test "returns error for non-assembly event type" do
    assert {:error, :not_assembly_event} =
             AssemblyEventParser.extract_assembly_id(:killmail_created, %{
               "assembly_id" => "0xabc"
             })
  end

  test "assembly_event_types returns all three event type atoms" do
    assert AssemblyEventParser.assembly_event_types() == @assembly_event_types
  end

  test "functions are pure with no side effects" do
    raw_data = %{"assembly_id" => "0xpure", "status" => "ONLINE"}
    snapshot = raw_data
    {:message_queue_len, mailbox_before} = Process.info(self(), :message_queue_len)

    assert AssemblyEventParser.assembly_event?(:assembly_status_changed)

    assert {:ok, "0xpure"} =
             AssemblyEventParser.extract_assembly_id(:assembly_status_changed, raw_data)

    assert AssemblyEventParser.assembly_event_types() == @assembly_event_types
    assert raw_data == snapshot
    assert Process.info(self(), :message_queue_len) == {:message_queue_len, mailbox_before}
  end
end
