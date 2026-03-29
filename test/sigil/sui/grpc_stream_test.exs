defmodule Sigil.Sui.GrpcStreamTest do
  @moduledoc """
  Covers checkpoint streaming, reconnect, and cursor persistence contracts.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Sui.GrpcStream}

  alias Sigil.Repo
  alias Sigil.Sui.GrpcStream
  alias Sigil.Sui.GrpcStream.Codec

  setup %{sandbox_owner: sandbox_owner} do
    pubsub = unique_pubsub_name()
    topic = unique_topic()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, topic)

    {:ok, pubsub: pubsub, topic: topic, sandbox_owner: sandbox_owner}
  end

  @tag :acceptance
  test "starting the stream broadcasts matching chain events for downstream consumers", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn endpoint, cursor ->
            send(test_pid, {:connect_called, self(), endpoint, cursor})
            {:ok, make_ref()}
          end,
          schedule_fun: fn pid, message, delay_ms ->
            send(test_pid, {:scheduled, pid, message, delay_ms})
            make_ref()
          end,
          event_filter_fun: fn event ->
            event_type(event) == "0x2::killmail::KillmailCreatedEvent"
          end
        )
      )

    assert_receive {:connect_called, ^pid, "grpc.test.invalid:443", nil}, 1_000
    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 30_000}, 1_000

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(101, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{
           "killer" => "0xkiller-1",
           "victim" => "0xvictim-1",
           "solar_system" => "0xsystem-1",
           "loss_type" => "ship"
         }),
         event_fixture("0x2::unrelated::IgnoredEvent", %{"ignored" => true})
       ])}
    )

    assert_receive {:chain_event, :killmail_created, raw_event_data, 101}, 1_000
    assert raw_event_data["killer_character_id"] == "0xkiller-1"
    assert raw_event_data["victim_character_id"] == "0xvictim-1"
    assert raw_event_data["solar_system_id"] == "0xsystem-1"
    assert raw_event_data["loss_type"] == "ship"
    refute_received {:chain_event, :jump, _, 101}
    refute_received {:chain_event, :priority_list_updated, _, 101}
  end

  test "filters checkpoint events to only broadcast reputation-relevant types", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor ->
            send(test_pid, :connected)
            {:ok, make_ref()}
          end,
          schedule_fun: fn _pid, _message, _delay_ms ->
            make_ref()
          end,
          event_filter_fun: fn event ->
            String.ends_with?(event_type(event), "JumpEvent")
          end
        )
      )

    assert_receive :connected, 1_000

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(55, [
         event_fixture("0x2::jump::JumpEvent", %{
           "character" => "0xchar-7",
           "source_gate" => "0xgate-1",
           "destination_gate" => "0xgate-2"
         }),
         event_fixture("0x2::noise::SomeOtherEvent", %{"ignored" => true})
       ])}
    )

    assert_receive {:chain_event, :jump, raw_event_data, 55}, 1_000
    assert raw_event_data["character_id"] == "0xchar-7"
    assert raw_event_data["source_gate_id"] == "0xgate-1"
    assert raw_event_data["destination_gate_id"] == "0xgate-2"
    refute_received {:chain_event, :killmail_created, _, 55}
  end

  test "reconnects with exponential backoff after stream disconnect", context do
    test_pid = self()
    attempts = start_supervised!({Agent, fn -> 0 end})

    pid =
      start_grpc_stream!(
        stream_opts(context,
          load_cursor_fun: fn -> 77 end,
          connect_fun: fn endpoint, cursor ->
            attempt = Agent.get_and_update(attempts, fn current -> {current + 1, current + 1} end)
            send(test_pid, {:connect_called, self(), endpoint, cursor, attempt})

            case attempt do
              1 -> {:error, :closed}
              2 -> {:error, :closed}
              _ -> {:ok, make_ref()}
            end
          end,
          schedule_fun: fn scheduled_pid, message, delay_ms ->
            send(test_pid, {:scheduled, scheduled_pid, message, delay_ms})
            make_ref()
          end,
          reconnect_base_ms: 5,
          reconnect_max_ms: 20,
          flush_interval_ms: 25
        )
      )

    assert_receive {:connect_called, ^pid, "grpc.test.invalid:443", 77, 1}, 1_000
    assert_receive {:scheduled, ^pid, {:reconnect, _}, 5}, 1_000

    send(pid, :reconnect)

    assert_receive {:connect_called, ^pid, "grpc.test.invalid:443", 77, 2}, 1_000
    assert_receive {:scheduled, ^pid, {:reconnect, _}, 10}, 1_000

    send(pid, :reconnect)

    assert_receive {:connect_called, ^pid, "grpc.test.invalid:443", 77, 3}, 1_000
    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 25}, 1_000
  end

  test "resets backoff counter after successful reconnection", context do
    test_pid = self()
    attempts = start_supervised!({Agent, fn -> 0 end})

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor ->
            attempt = Agent.get_and_update(attempts, fn current -> {current + 1, current + 1} end)

            case attempt do
              1 ->
                send(test_pid, {:connect_attempt, self(), attempt, nil})
                {:error, :closed}

              _ ->
                stream_ref = make_ref()
                send(test_pid, {:connect_attempt, self(), attempt, stream_ref})
                {:ok, stream_ref}
            end
          end,
          schedule_fun: fn scheduled_pid, message, delay_ms ->
            send(test_pid, {:scheduled, scheduled_pid, message, delay_ms})
            make_ref()
          end,
          reconnect_base_ms: 5,
          reconnect_max_ms: 20
        )
      )

    assert_receive {:connect_attempt, ^pid, 1, nil}, 1_000
    assert_receive {:scheduled, ^pid, {:reconnect, _}, 5}, 1_000

    send(pid, :reconnect)

    assert_receive {:connect_attempt, ^pid, 2, stream_ref}, 1_000
    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 30_000}, 1_000

    send(pid, {:stream_closed, stream_ref, :closed})

    assert_receive {:scheduled, ^pid, {:reconnect, _}, 5}, 1_000
  end

  test "ignores checkpoint, stream errors, and close messages from stale stream refs", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor ->
            stream_ref = make_ref()
            send(test_pid, {:connected, self(), stream_ref})
            {:ok, stream_ref}
          end,
          schedule_fun: fn scheduled_pid, message, delay_ms ->
            send(test_pid, {:scheduled, scheduled_pid, message, delay_ms})
            make_ref()
          end,
          event_filter_fun: fn _event -> true end
        )
      )

    assert_receive {:connected, ^pid, active_stream_ref}, 1_000
    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 30_000}, 1_000

    stale_stream_ref = make_ref()

    send(
      pid,
      {:checkpoint, stale_stream_ref,
       checkpoint_fixture(900, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 900})
       ])}
    )

    refute_received {:chain_event, _, _, 900}

    send(pid, {:stream_closed, stale_stream_ref, :closed})
    send(pid, {:stream_error, stale_stream_ref, :closed})

    # Synchronize by forcing the monitor to process a known active-stream checkpoint
    # before asserting stale stream messages did not schedule reconnect.
    send(
      pid,
      {:checkpoint, active_stream_ref,
       checkpoint_fixture(901, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 901})
       ])}
    )

    assert_receive {:chain_event, :killmail_created, %{"id" => 901}, 901}, 1_000
    refute_received {:scheduled, ^pid, {:reconnect, _}, _}

    send(pid, {:stream_closed, active_stream_ref, :closed})

    assert_receive {:scheduled, ^pid, {:reconnect, _}, 1_000}, 1_000
  end

  test "stream_error triggers reconnect and flushes dirty cursor", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
          schedule_fun: fn scheduled_pid, message, delay_ms ->
            send(test_pid, {:scheduled, scheduled_pid, message, delay_ms})
            make_ref()
          end,
          save_cursor_fun: fn cursor ->
            send(test_pid, {:cursor_saved, cursor})
            :ok
          end,
          event_filter_fun: fn _event -> true end
        )
      )

    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 30_000}, 1_000

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(777, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 777})
       ])}
    )

    send(pid, {:stream_error, :transport_closed})

    assert_receive {:cursor_saved, 777}, 1_000
    assert_receive {:scheduled, ^pid, {:reconnect, _}, 1_000}, 1_000
  end

  test "reader crashes trigger reconnect for the active stream", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor ->
            stream_ref = make_ref()
            monitor_ref = make_ref()
            send(test_pid, {:connected, self(), stream_ref, monitor_ref})
            {:ok, %{stream_ref: stream_ref, monitor_ref: monitor_ref}}
          end,
          schedule_fun: fn scheduled_pid, message, delay_ms ->
            send(test_pid, {:scheduled, scheduled_pid, message, delay_ms})
            make_ref()
          end
        )
      )

    assert_receive {:connected, ^pid, active_stream_ref, active_monitor_ref}, 1_000
    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 30_000}, 1_000

    send(pid, {:DOWN, active_monitor_ref, :process, active_stream_ref, :boom})

    assert_receive {:scheduled, ^pid, {:reconnect, _}, 1_000}, 1_000
  end

  test "flushes cursor to persistence after flush_count checkpoints", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
          schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end,
          save_cursor_fun: fn cursor ->
            send(test_pid, {:cursor_saved, cursor})
            :ok
          end,
          flush_count: 2,
          event_filter_fun: fn _event -> true end
        )
      )

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(10, [event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 1})])}
    )

    first_state = :sys.get_state(pid)
    assert first_state.cursor == 10
    assert first_state.checkpoints_since_flush == 1
    assert first_state.last_flushed_cursor == nil
    refute_received {:cursor_saved, 10}

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(11, [event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 2})])}
    )

    second_state = :sys.get_state(pid)
    assert second_state.cursor == 11
    assert second_state.checkpoints_since_flush == 0
    assert second_state.last_flushed_cursor == 11
    assert_receive {:cursor_saved, 11}, 1_000
  end

  test "flushes cursor to persistence on periodic flush messages", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
          schedule_fun: fn scheduled_pid, message, delay_ms ->
            send(test_pid, {:scheduled, scheduled_pid, message, delay_ms})
            make_ref()
          end,
          save_cursor_fun: fn cursor ->
            send(test_pid, {:cursor_saved, cursor})
            :ok
          end
        )
      )

    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 30_000}, 1_000

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(205, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 205})
       ])}
    )

    _state_after_checkpoint = :sys.get_state(pid)

    flush_state_before = :sys.get_state(pid)
    send(pid, {:flush_cursor, flush_state_before.flush_timer_token})

    flushed_state = :sys.get_state(pid)
    assert flushed_state.last_flushed_cursor == 205
    assert flushed_state.checkpoints_since_flush == 0
    assert_receive {:cursor_saved, 205}, 1_000
    assert_receive {:scheduled, ^pid, {:flush_cursor, _}, 30_000}, 1_000
  end

  test "loads persisted cursor on startup and resumes the stream from that position", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        context
        |> stream_opts(
          stream_id: "test-stream",
          load_cursor_fun: fn -> 404 end,
          connect_fun: fn endpoint, cursor ->
            send(test_pid, {:connect_called, self(), endpoint, cursor})
            {:ok, make_ref()}
          end,
          schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end
        )
      )

    assert_receive {:connect_called, ^pid, "grpc.test.invalid:443", 404}, 1_000
  end

  test "terminate flushes a dirty cursor to persistence", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
          schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end,
          save_cursor_fun: fn cursor ->
            send(test_pid, {:cursor_saved, cursor})
            :ok
          end,
          event_filter_fun: fn _event -> true end
        )
      )

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(88, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 88})
       ])}
    )

    _state = :sys.get_state(pid)

    assert :ok = GenServer.stop(pid, :normal, :infinity)
    assert_receive {:cursor_saved, 88}, 1_000
  end

  test "returns :ignore when start_grpc_stream config is false" do
    assert :ignore = GrpcStream.init([])
  end

  test "loads persisted cursor from default Postgres storage", context do
    stream_id = "grpc_stream_cursor_load_#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             Repo.query(
               "INSERT INTO checkpoint_cursors (stream_id, cursor, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW())",
               [stream_id, 512]
             )

    test_pid = self()

    opts =
      context
      |> stream_opts(
        stream_id: stream_id,
        connect_fun: fn endpoint, cursor ->
          send(test_pid, {:connect_called, self(), endpoint, cursor})
          {:ok, make_ref()}
        end,
        schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end
      )
      |> Keyword.drop([:load_cursor_fun, :save_cursor_fun])

    pid = start_grpc_stream!(opts)

    assert_receive {:connect_called, ^pid, "grpc.test.invalid:443", 512}, 1_000
  end

  test "persists cursor to default Postgres storage on flush", context do
    stream_id = "grpc_stream_cursor_save_#{System.unique_integer([:positive])}"

    opts =
      context
      |> stream_opts(
        stream_id: stream_id,
        connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
        schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end,
        event_filter_fun: fn _event -> true end
      )
      |> Keyword.drop([:load_cursor_fun, :save_cursor_fun])

    pid = start_grpc_stream!(opts)

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(733, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{"id" => 733})
       ])}
    )

    flush_state = :sys.get_state(pid)
    send(pid, {:flush_cursor, flush_state.flush_timer_token})
    _post_flush_state = :sys.get_state(pid)

    assert {:ok, %{rows: [[733]]}} =
             Repo.query("SELECT cursor FROM checkpoint_cursors WHERE stream_id = $1", [stream_id])
  end

  test "broadcasts chain_event with the expected message shape", context do
    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
          schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end,
          event_filter_fun: fn event ->
            String.ends_with?(event_type(event), "PriorityListUpdatedEvent")
          end
        )
      )

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(303, [
         event_fixture("0x2::priority_list::PriorityListUpdatedEvent", %{
           "turret_id" => "0xturret-77",
           "priority_list" => [
             %{"character_id" => "0xagg-77", "is_aggressor" => true},
             %{"character_id" => "0xpilot-12", "is_aggressor" => false}
           ]
         })
       ])}
    )

    assert_receive {:chain_event, event_name, raw_event_data, 303}, 1_000
    assert event_name == :priority_list_updated
    assert raw_event_data["turret_id"] == "0xturret-77"
    assert raw_event_data["aggressor_character_id"] == "0xagg-77"
    assert is_list(raw_event_data["priority_list"])
  end

  test "default event filter passes assembly lifecycle events" do
    assert Codec.default_event_filter(
             event_fixture("0x2::assembly::StatusChangedEvent", %{"assembly_id" => "0xasm-1"})
           )

    assert Codec.default_event_filter(
             event_fixture("0x2::assembly::FuelEvent", %{"assembly_id" => "0xasm-1"})
           )

    assert Codec.default_event_filter(
             event_fixture("0x2::assembly::ExtensionAuthorizedEvent", %{
               "assembly_id" => "0xasm-1"
             })
           )
  end

  test "assembly event normalization extracts assembly_id" do
    status_payload =
      Codec.normalize_event_payload("0x2::assembly::StatusChangedEvent", %{
        "assembly" => "0xasm-1"
      })

    fuel_payload =
      Codec.normalize_event_payload("0x2::assembly::FuelEvent", %{"assembly" => "0xasm-2"})

    extension_payload =
      Codec.normalize_event_payload("0x2::assembly::ExtensionAuthorizedEvent", %{
        "assembly" => "0xasm-3"
      })

    assert status_payload["assembly_id"] == "0xasm-1"
    assert fuel_payload["assembly_id"] == "0xasm-2"
    assert extension_payload["assembly_id"] == "0xasm-3"
  end

  test "normalizes StatusChangedEvent with status and action fields" do
    payload =
      Codec.normalize_event_payload("0x2::assembly::StatusChangedEvent", %{
        "assembly" => "0xasm-status",
        "status" => "ONLINE",
        "action" => "online"
      })

    assert payload["assembly_id"] == "0xasm-status"
    assert payload["status"] == "ONLINE"
    assert payload["action"] == "online"
  end

  test "normalizes FuelEvent with quantity and burning fields" do
    payload =
      Codec.normalize_event_payload("0x2::assembly::FuelEvent", %{
        "assembly" => "0xasm-fuel",
        "old_quantity" => "10",
        "new_quantity" => "8",
        "is_burning" => true,
        "action" => "burning"
      })

    assert payload["assembly_id"] == "0xasm-fuel"
    assert payload["old_quantity"] == "10"
    assert payload["new_quantity"] == "8"
    assert payload["is_burning"] == true
    assert payload["action"] == "burning"
  end

  test "normalizes ExtensionAuthorizedEvent with extension fields" do
    payload =
      Codec.normalize_event_payload("0x2::assembly::ExtensionAuthorizedEvent", %{
        "assembly" => "0xasm-ext",
        "extension_type" => "gate",
        "previous_extension" => "turret",
        "owner_cap_id" => "0xowner-cap-9"
      })

    assert payload["assembly_id"] == "0xasm-ext"
    assert payload["extension_type"] == "gate"
    assert payload["previous_extension"] == "turret"
    assert payload["owner_cap_id"] == "0xowner-cap-9"
  end

  test "broadcasts assembly lifecycle events with normalized payloads", context do
    pid =
      context
      |> stream_opts(
        connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
        schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end
      )
      |> Keyword.drop([:event_filter_fun])
      |> start_grpc_stream!()

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(451, [
         event_fixture("0x2::assembly::StatusChangedEvent", %{
           "assembly" => "0xasm-451",
           "status" => "ONLINE",
           "action" => "online"
         }),
         event_fixture("0x2::assembly::FuelEvent", %{
           "assembly" => "0xasm-451",
           "old_quantity" => "12",
           "new_quantity" => "11",
           "is_burning" => true,
           "action" => "burning"
         }),
         event_fixture("0x2::assembly::ExtensionAuthorizedEvent", %{
           "assembly" => "0xasm-451",
           "extension_type" => "gate",
           "previous_extension" => "turret",
           "owner_cap_id" => "0xowner-cap-451"
         })
       ])}
    )

    assert_receive {:chain_event, :assembly_status_changed, status_data, 451}, 1_000
    assert status_data["assembly_id"] == "0xasm-451"
    assert status_data["status"] == "ONLINE"
    assert status_data["action"] == "online"

    assert_receive {:chain_event, :assembly_fuel_changed, fuel_data, 451}, 1_000
    assert fuel_data["assembly_id"] == "0xasm-451"
    assert fuel_data["old_quantity"] == "12"
    assert fuel_data["new_quantity"] == "11"
    assert fuel_data["is_burning"] == true
    assert fuel_data["action"] == "burning"

    assert_receive {:chain_event, :assembly_extension_authorized, extension_data, 451}, 1_000
    assert extension_data["assembly_id"] == "0xasm-451"
    assert extension_data["extension_type"] == "gate"
    assert extension_data["previous_extension"] == "turret"
    assert extension_data["owner_cap_id"] == "0xowner-cap-451"
  end

  test "skips malformed checkpoint data without advancing the cursor", context do
    test_pid = self()

    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
          schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end,
          save_cursor_fun: fn cursor ->
            send(test_pid, {:cursor_saved, cursor})
            :ok
          end
        )
      )

    send(pid, {:checkpoint, %{"sequenceNumber" => 13}})

    malformed_state = :sys.get_state(pid)
    assert malformed_state.cursor == nil

    malformed_flush_state = :sys.get_state(pid)
    send(pid, {:flush_cursor, malformed_flush_state.flush_timer_token})
    _post_flush_state = :sys.get_state(pid)
    refute_received {:cursor_saved, 13}
    refute_received {:chain_event, _, _, _}

    send(
      pid,
      {:checkpoint,
       checkpoint_fixture(14, [
         event_fixture("0x2::killmail::KillmailCreatedEvent", %{
           "killer" => "0xkiller-14",
           "victim" => "0xvictim-14",
           "loss_type" => "ship"
         })
       ])}
    )

    valid_state = :sys.get_state(pid)
    send(pid, {:flush_cursor, valid_state.flush_timer_token})

    assert_receive {:cursor_saved, 14}, 1_000
  end

  test "grpc stream is not a named process", context do
    pid =
      start_grpc_stream!(
        stream_opts(context,
          connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
          schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end
        )
      )

    assert Process.info(pid, :registered_name) == {:registered_name, []}
  end

  test "child_spec generates a unique id for each stream instance" do
    spec_one = GrpcStream.child_spec([])
    spec_two = GrpcStream.child_spec([])

    assert spec_one.start == {GrpcStream, :start_link, [[]]}
    assert spec_two.start == {GrpcStream, :start_link, [[]]}
    refute spec_one.id == spec_two.id
  end

  defp start_grpc_stream!(opts) do
    start_supervised!({GrpcStream, opts})
  end

  defp stream_opts(context, overrides) do
    Keyword.merge(
      [
        enabled?: true,
        endpoint: "grpc.test.invalid:443",
        pubsub: context.pubsub,
        topic: context.topic,
        load_cursor_fun: fn -> nil end,
        save_cursor_fun: fn _cursor -> :ok end,
        event_filter_fun: fn event ->
          type = event_type(event)

          String.ends_with?(type, "KillmailCreatedEvent") or
            String.ends_with?(type, "JumpEvent") or
            String.ends_with?(type, "PriorityListUpdatedEvent")
        end,
        flush_interval_ms: 30_000,
        flush_count: 100,
        reconnect_base_ms: 1_000,
        reconnect_max_ms: 60_000,
        connect_fun: fn _endpoint, _cursor -> {:ok, make_ref()} end,
        schedule_fun: fn _pid, _message, _delay_ms -> make_ref() end,
        sandbox_owner: context.sandbox_owner
      ],
      overrides
    )
  end

  defp checkpoint_fixture(sequence_number, events) do
    %{
      "sequenceNumber" => sequence_number,
      "transactions" => [
        %{"events" => events}
      ]
    }
  end

  defp event_fixture(type, json) do
    %{
      "type" => %{"repr" => type},
      "json" => json
    }
  end

  defp event_type(%{"type" => %{"repr" => type}}), do: type

  defp unique_pubsub_name do
    :"grpc_stream_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_topic do
    "chain_events:#{System.unique_integer([:positive])}"
  end
end
