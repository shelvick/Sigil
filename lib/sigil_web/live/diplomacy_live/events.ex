defmodule SigilWeb.DiplomacyLive.Events do
  @moduledoc """
  Event and mailbox handlers for the diplomacy LiveView.
  """

  import Phoenix.LiveView, only: [clear_flash: 1, put_flash: 3]

  alias Sigil.Diplomacy
  alias SigilWeb.DiplomacyLive.{State, Transactions}

  @doc "Handles diplomacy LiveView events."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("create_custodian", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> Transactions.build_transaction(&Diplomacy.build_create_custodian_tx/1)}
  end

  def handle_event("retry_discovery", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> State.discover_custodian_state()
     |> State.load_standings()}
  end

  def handle_event("add_tribe_standing", %{"tribe_id" => tid, "standing" => s}, socket) do
    case Integer.parse(tid) do
      {tribe_id, ""} ->
        {:noreply,
         socket
         |> clear_flash()
         |> Transactions.build_transaction(
           &Diplomacy.build_set_standing_tx(tribe_id, String.to_integer(s), &1)
         )}

      _invalid ->
        {:noreply, put_flash(socket, :error, "Tribe ID must be a number")}
    end
  end

  def handle_event("set_standing", %{"standing" => ""}, socket), do: {:noreply, socket}

  def handle_event("set_standing", %{"tribe_id" => tid, "standing" => s}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> Transactions.build_transaction(
       &Diplomacy.build_set_standing_tx(String.to_integer(tid), String.to_integer(s), &1)
     )}
  end

  def handle_event("batch_set_standings", %{"updates" => updates}, socket) do
    parsed =
      Enum.map(updates, fn %{"tribe_id" => tid, "standing" => s} ->
        {String.to_integer(tid), String.to_integer(s)}
      end)

    {:noreply,
     socket
     |> clear_flash()
     |> Transactions.build_transaction(&Diplomacy.build_batch_set_standings_tx(parsed, &1))}
  end

  def handle_event("add_pilot_override", %{"pilot_address" => pilot, "standing" => s}, socket) do
    if State.valid_address?(pilot) do
      {:noreply,
       socket
       |> clear_flash()
       |> Phoenix.Component.assign(pilot_error: nil)
       |> Transactions.build_transaction(
         &Diplomacy.build_set_pilot_standing_tx(pilot, String.to_integer(s), &1)
       )}
    else
      {:noreply, Phoenix.Component.assign(socket, pilot_error: "Invalid address format")}
    end
  end

  def handle_event("set_default_standing", %{"standing" => standing_str}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> Transactions.build_transaction(
       &Diplomacy.build_set_default_standing_tx(String.to_integer(standing_str), &1)
     )}
  end

  def handle_event("toggle_governance", _params, socket) do
    {:noreply,
     Phoenix.Component.assign(socket, :governance_expanded, !socket.assigns.governance_expanded)}
  end

  def handle_event("vote_leader", %{"candidate" => candidate}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> Transactions.build_transaction(&Diplomacy.build_vote_leader_tx(candidate, &1))}
  end

  def handle_event("claim_leadership", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> Transactions.build_transaction(&Diplomacy.build_claim_leadership_tx/1)}
  end

  def handle_event("filter_tribes", params, socket) do
    query = params["value"] || params["query"] || ""
    {:noreply, Phoenix.Component.assign(socket, :tribe_filter, query)}
  end

  def handle_event("change_oracle_address", %{"oracle_address" => oracle_address}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :oracle_address_input, oracle_address)}
  end

  def handle_event("set_oracle", params, socket) do
    if socket.assigns.is_leader do
      oracle_address =
        Map.get(params, "oracle_address", socket.assigns.oracle_address_input || "")

      if State.valid_address?(oracle_address) do
        {:noreply,
         socket
         |> Phoenix.Component.assign(:oracle_address_input, oracle_address)
         |> clear_flash()
         |> Transactions.build_transaction(
           &Diplomacy.set_oracle_address(socket.assigns.tribe_id, oracle_address, &1)
         )}
      else
        {:noreply, put_flash(socket, :error, "Invalid oracle address")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the tribe leader can modify standings")}
    end
  end

  def handle_event("remove_oracle", _params, socket) do
    if socket.assigns.is_leader do
      {:noreply,
       socket
       |> clear_flash()
       |> Transactions.build_transaction(
         &Diplomacy.remove_oracle_address(socket.assigns.tribe_id, &1)
       )}
    else
      {:noreply, put_flash(socket, :error, "Only the tribe leader can modify standings")}
    end
  end

  def handle_event(
        "pin_standing",
        %{"target_tribe_id" => target_tribe_id, "standing" => standing},
        socket
      ) do
    if socket.assigns.is_leader do
      with {target_tribe_id_int, ""} <- Integer.parse(target_tribe_id),
           {:ok, standing_atom} <- State.standing_from_param(standing),
           :ok <-
             Diplomacy.pin_standing(
               target_tribe_id_int,
               standing_atom,
               State.diplomacy_opts(socket)
             ) do
        {:noreply, State.load_standings(socket)}
      else
        _error -> {:noreply, put_flash(socket, :error, "Failed to pin standing")}
      end
    else
      {:noreply, put_flash(socket, :error, "Failed to pin standing")}
    end
  end

  def handle_event("unpin_standing", %{"target_tribe_id" => target_tribe_id}, socket) do
    if socket.assigns.is_leader do
      with {target_tribe_id_int, ""} <- Integer.parse(target_tribe_id),
           :ok <- Diplomacy.unpin_standing(target_tribe_id_int, State.diplomacy_opts(socket)) do
        {:noreply, State.load_standings(socket)}
      else
        _error -> {:noreply, put_flash(socket, :error, "Failed to unpin standing")}
      end
    else
      {:noreply, put_flash(socket, :error, "Failed to unpin standing")}
    end
  end

  def handle_event("transaction_signed", %{"bytes" => tx_bytes, "signature" => signature}, socket) do
    tx_bytes = socket.assigns.pending_tx_bytes || tx_bytes
    ignore_governance = SigilWeb.DiplomacyLive.Governance.governance_tx?(socket, tx_bytes)

    case Diplomacy.submit_signed_transaction(tx_bytes, signature, State.diplomacy_opts(socket)) do
      {:ok, %{digest: _digest, effects_bcs: effects_bcs}} ->
        socket =
          socket
          |> Phoenix.Component.assign(
            page_state: socket.assigns.return_page_state,
            pending_tx_bytes: nil,
            ignore_governance_update: ignore_governance
          )
          |> State.maybe_refresh_after_submission()

        socket =
          if effects_bcs,
            do:
              Phoenix.LiveView.push_event(socket, "report_transaction_effects", %{
                effects: effects_bcs
              }),
            else: socket

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Transaction failed")
         |> Phoenix.Component.assign(
           page_state: socket.assigns.return_page_state,
           pending_tx_bytes: nil
         )}
    end
  end

  def handle_event("transaction_error", %{"reason" => reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Transaction failed: #{reason}")
     |> Phoenix.Component.assign(
       page_state: socket.assigns.return_page_state,
       pending_tx_bytes: nil
     )}
  end

  def handle_event("wallet_detected", _params, socket), do: {:noreply, socket}
  def handle_event("wallet_error", _params, socket), do: {:noreply, socket}

  @doc "Handles diplomacy LiveView mailbox messages."
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:standing_updated, _data}, socket),
    do: {:noreply, State.load_standings(socket)}

  def handle_info({:pilot_standing_updated, _data}, socket),
    do: {:noreply, State.load_standings(socket)}

  def handle_info({:default_standing_updated, _standing}, socket),
    do: {:noreply, State.load_standings(socket)}

  def handle_info({:custodian_discovered, custodian}, socket),
    do:
      {:noreply, socket |> State.apply_discovered_custodian(custodian) |> State.load_standings()}

  def handle_info({:custodian_created, _custodian}, socket),
    do: {:noreply, socket |> State.apply_cached_custodian_state() |> State.load_standings()}

  def handle_info(:rediscover_custodian, socket),
    do: {:noreply, socket |> State.discover_custodian_state() |> State.load_standings()}

  def handle_info(
        {:governance_updated, %{tribe_id: tribe_id}},
        %{assigns: %{tribe_id: tribe_id, ignore_governance_update: true}} = socket
      ),
      do: {:noreply, Phoenix.Component.assign(socket, ignore_governance_update: false)}

  def handle_info(
        {:governance_updated, %{tribe_id: tribe_id}},
        %{assigns: %{tribe_id: tribe_id}} = socket
      ),
      do: {:noreply, State.load_standings(socket)}

  def handle_info({:reputation_updated, _payload}, socket),
    do: {:noreply, State.load_standings(socket)}

  def handle_info({:reputation_pinned, _payload}, socket),
    do: {:noreply, State.load_standings(socket)}

  def handle_info({:reputation_unpinned, _payload}, socket),
    do: {:noreply, State.load_standings(socket)}

  def handle_info(_msg, socket), do: {:noreply, socket}
end
