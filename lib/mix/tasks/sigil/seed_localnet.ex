defmodule Mix.Tasks.Sigil.SeedLocalnet do
  @moduledoc """
  Seeds the localnet environment with UAT data.

  Creates on-chain TribeCustodians with standings, then inserts database
  records (intel reports, alerts, pseudonyms, reputation scores, webhook configs).

  ## Usage

      source .env.localnet
      export EVE_WORLD=localnet
      export SEED_CHAR_A1=0x... SEED_CHAR_B1=0x... SEED_CHAR_C1=0x...
      export SEED_GATE_1=0x... SEED_NWN=0x... SEED_SSU=0x...
      export SEED_TURRET=0x... SEED_GATE_B=0x... SEED_NWN_B=0x...
      export SEED_PLAYER_A_ADDR=0x... SEED_PLAYER_B_ADDR=0x... SEED_ADMIN_ADDR=0x...
      export SEED_ADMIN_KEY_HEX=<64-char-hex> SEED_PLAYER_B_KEY_HEX=<64-char-hex>
      mix sigil.seed_localnet
  """

  use Mix.Task

  alias Sigil.Sui.{BCS, Base58, Signer, TransactionBuilder, TransactionBuilder.PTB, TxCustodian}
  alias Sigil.Diplomacy.LocalSigner

  @shortdoc "Seed localnet with UAT data (Custodians + DB records)"

  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:req)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Sigil.Repo.start_link([])

    configure_runtime_env!()

    info("Seeding localnet UAT data...")

    env = load_env!()
    seed_on_chain!(env)
    seed_database!(env)

    info("Localnet seeding complete!")
  end

  # ── Environment ──────────────────────────────────────────────────────

  defp configure_runtime_env! do
    eve_world = require_env!("EVE_WORLD")
    Application.put_env(:sigil, :eve_world, eve_world)

    worlds = Application.get_env(:sigil, :eve_worlds, %{})
    localnet = Map.get(worlds, "localnet", %{})

    localnet =
      case System.get_env("SUI_LOCALNET_PACKAGE_ID") do
        nil -> localnet
        id -> %{localnet | package_id: id}
      end

    localnet =
      case System.get_env("SUI_LOCALNET_SIGIL_PACKAGE_ID") do
        nil -> localnet
        id -> %{localnet | sigil_package_id: id}
      end

    Application.put_env(:sigil, :eve_worlds, Map.put(worlds, "localnet", localnet))
  end

  defp load_env! do
    player_a_key = require_env!("SUI_LOCALNET_SIGNER_KEY")
    admin_key = require_env!("SEED_ADMIN_KEY_HEX")
    player_b_key = require_env!("SEED_PLAYER_B_KEY_HEX")

    %{
      rpc_url: rpc_url(),
      player_a_key: player_a_key,
      admin_key: admin_key,
      player_b_key: player_b_key,
      char_a1: require_env!("SEED_CHAR_A1"),
      char_b1: require_env!("SEED_CHAR_B1"),
      char_c1: require_env!("SEED_CHAR_C1"),
      gate_1: require_env!("SEED_GATE_1"),
      gate_2: System.get_env("SEED_GATE_2") || "unknown",
      nwn: require_env!("SEED_NWN"),
      ssu: require_env!("SEED_SSU"),
      turret: require_env!("SEED_TURRET"),
      gate_b: require_env!("SEED_GATE_B"),
      nwn_b: require_env!("SEED_NWN_B"),
      player_a_addr: require_env!("SEED_PLAYER_A_ADDR"),
      player_b_addr: require_env!("SEED_PLAYER_B_ADDR"),
      admin_addr: require_env!("SEED_ADMIN_ADDR")
    }
  end

  defp rpc_url do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    Map.get(Map.fetch!(worlds, world), :rpc_url) || "http://localhost:9000"
  end

  defp require_env!(name) do
    case System.get_env(name) do
      nil -> Mix.raise("Missing required env var: #{name}")
      "" -> Mix.raise("Empty required env var: #{name}")
      val -> val
    end
  end

  # ── On-Chain Seeding ─────────────────────────────────────────────────

  defp seed_on_chain!(env) do
    info("=== On-Chain Seeding ===")

    # Discover TribeCustodianRegistry
    registry_ref = discover_registry!(env)
    info("  Registry: #{inspect(registry_ref.initial_shared_version)}")

    # Resolve character refs
    char_a1_ref = resolve_shared_ref!(env.char_a1, env)
    char_b1_ref = resolve_shared_ref!(env.char_b1, env)
    char_c1_ref = resolve_shared_ref!(env.char_c1, env)

    # Create Custodian for tribe 100 (PLAYER_A as creator/leader)
    info("  Creating Custodian for tribe 100...")
    kind_opts = TxCustodian.build_create_custodian(registry_ref, char_a1_ref, [])
    {:ok, digest} = sign_and_submit(kind_opts, env.player_a_key, env.rpc_url)
    info("  Custodian 100 created: #{digest}")

    # Wait for indexer
    :timer.sleep(3_000)

    # Discover the newly created Custodian for tribe 100
    custodian_100_ref = discover_custodian!(100, env)
    info("  Custodian 100 ref: v#{custodian_100_ref.initial_shared_version}")

    # PLAYER_B joins tribe 100 Custodian
    info("  PLAYER_B joining tribe 100 Custodian...")
    kind_opts = TxCustodian.build_join(custodian_100_ref, char_b1_ref, [])
    {:ok, digest} = sign_and_submit(kind_opts, env.player_b_key, env.rpc_url)
    info("  Joined: #{digest}")

    :timer.sleep(2_000)

    # Set standings on tribe 100's Custodian
    info("  Setting tribe 100 standings...")

    kind_opts =
      TxCustodian.build_batch_set_standings(
        custodian_100_ref,
        char_a1_ref,
        [
          # tribe 200 = UNFRIENDLY
          {200, 1},
          # tribe 300 = FRIENDLY (phantom)
          {300, 3},
          # tribe 400 = ALLIED (phantom)
          {400, 4}
        ],
        []
      )

    {:ok, _} = sign_and_submit(kind_opts, env.player_a_key, env.rpc_url)

    :timer.sleep(2_000)

    # Set default standing = NEUTRAL (NBSI)
    kind_opts = TxCustodian.build_set_default_standing(custodian_100_ref, char_a1_ref, 2, [])
    {:ok, _} = sign_and_submit(kind_opts, env.player_a_key, env.rpc_url)

    :timer.sleep(2_000)

    # Set pilot override: ADMIN address = FRIENDLY (overrides tribe 200's UNFRIENDLY)
    admin_bytes = hex_to_bytes!(env.admin_addr)

    kind_opts =
      TxCustodian.build_set_pilot_standing(custodian_100_ref, char_a1_ref, admin_bytes, 3, [])

    {:ok, _} = sign_and_submit(kind_opts, env.player_a_key, env.rpc_url)

    :timer.sleep(2_000)

    # Create Custodian for tribe 200 (ADMIN as creator/leader)
    info("  Creating Custodian for tribe 200...")
    kind_opts = TxCustodian.build_create_custodian(registry_ref, char_c1_ref, [])
    {:ok, digest} = sign_and_submit(kind_opts, env.admin_key, env.rpc_url)
    info("  Custodian 200 created: #{digest}")

    :timer.sleep(3_000)

    custodian_200_ref = discover_custodian!(200, env)

    # Set tribe 200 standings: tribe 100 = HOSTILE
    info("  Setting tribe 200 standings...")
    kind_opts = TxCustodian.build_set_standing(custodian_200_ref, char_c1_ref, 100, 0, [])
    {:ok, _} = sign_and_submit(kind_opts, env.admin_key, env.rpc_url)

    info("  On-chain seeding complete!")
  end

  # ── Transaction Helpers (follows LocalSigner pattern) ────────────────

  defp sign_and_submit(kind_opts, hex_key, rpc_url) do
    {:ok, privkey} = Base.decode16(hex_key, case: :mixed)
    {pubkey, _} = Signer.keypair_from_private_key(privkey)
    sender = Signer.address_from_public_key(pubkey)
    sender_hex = Signer.to_sui_address(sender)

    {:ok, gas_ref} = fetch_gas_coin_ref(rpc_url, sender_hex)

    kind_bytes = TransactionBuilder.build_kind!(kind_opts)

    tx_bytes =
      <<0x00>> <>
        kind_bytes <>
        BCS.encode_address(sender) <>
        PTB.encode_gas_data(%{
          payment: [gas_ref],
          owner: sender,
          price: 1_000,
          budget: 50_000_000
        }) <>
        PTB.encode_transaction_expiration(:none)

    signature =
      tx_bytes
      |> Signer.sign(privkey)
      |> Signer.encode_signature(pubkey)
      |> Base.encode64()

    submit_via_rpc(rpc_url, Base.encode64(tx_bytes), signature)
  end

  defp fetch_gas_coin_ref(rpc_url, sender) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "suix_getCoins",
      "params" => [sender, "0x2::sui::SUI", nil, 1]
    }

    case Req.post(rpc_url, json: body, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"result" => %{"data" => [coin | _]}}}} ->
        coin_id = coin["coinObjectId"]
        version = coin["version"] |> to_string() |> String.to_integer()
        digest_bytes = Base58.decode!(coin["digest"])
        padded = coin_id |> String.trim_leading("0x") |> String.pad_leading(64, "0")
        {:ok, id_bytes} = Base.decode16(padded, case: :mixed)
        {:ok, {id_bytes, version, digest_bytes}}

      _ ->
        {:error, :no_gas_coins}
    end
  end

  defp submit_via_rpc(rpc_url, tx_bytes_b64, signature) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "sui_executeTransactionBlock",
      "params" => [
        tx_bytes_b64,
        [signature],
        %{"showEffects" => true, "showObjectChanges" => true},
        "WaitForEffectsCert"
      ]
    }

    case Req.post(rpc_url, json: body, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"result" => %{"digest" => digest}}}} ->
        {:ok, digest}

      {:ok, %{status: 200, body: %{"error" => error}}} ->
        {:error, {:rpc_error, error["message"] || inspect(error)}}

      {:ok, resp} ->
        {:error, {:unexpected_response, inspect(resp.body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Object Discovery ─────────────────────────────────────────────────

  defp discover_registry!(env) do
    sigil_pkg = sigil_package_id()
    type = "#{sigil_pkg}::tribe_custodian::TribeCustodianRegistry"
    object_id = find_object_by_type!(type, env)
    version = LocalSigner.fetch_initial_shared_version(object_id, world: "localnet")

    %{
      object_id: hex_to_bytes!(object_id),
      initial_shared_version: version
    }
  end

  defp discover_custodian!(tribe_id, env) do
    sigil_pkg = sigil_package_id()
    type = "#{sigil_pkg}::tribe_custodian::Custodian"

    query = """
    { objects(filter: {type: "#{type}"}) {
        nodes { address asMoveObject { contents { json } } owner { ... on Shared { initialSharedVersion } } }
    } }
    """

    case graphql_query(query, env) do
      {:ok, %{"objects" => %{"nodes" => nodes}}} when is_list(nodes) ->
        custodian =
          Enum.find(nodes, fn node ->
            json = get_in(node, ["asMoveObject", "contents", "json"])
            json && to_string(json["tribe_id"]) == to_string(tribe_id)
          end)

        if custodian do
          object_id = custodian["address"]
          version = get_in(custodian, ["owner", "initialSharedVersion"])

          %{
            object_id: hex_to_bytes!(object_id),
            initial_shared_version: version
          }
        else
          Mix.raise("Custodian for tribe #{tribe_id} not found")
        end

      other ->
        Mix.raise("Failed to query Custodians: #{inspect(other)}")
    end
  end

  defp find_object_by_type!(type, env) do
    query = """
    { objects(filter: {type: "#{type}"}) { nodes { address } } }
    """

    case graphql_query(query, env) do
      {:ok, %{"objects" => %{"nodes" => [obj | _]}}} ->
        obj["address"]

      other ->
        Mix.raise("Object of type #{type} not found. Response: #{inspect(other)}")
    end
  end

  defp graphql_query(query, _env) do
    url = graphql_url()

    case Req.post(url, json: %{"query" => query}, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %{status: 200, body: %{"errors" => errors}}} ->
        {:error, {:graphql_errors, errors}}

      {:ok, resp} ->
        {:error, {:unexpected_response, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp graphql_url do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    Map.get(Map.fetch!(worlds, world), :graphql_url) || "http://localhost:9125/graphql"
  end

  defp resolve_shared_ref!(object_id, _env) do
    version = LocalSigner.fetch_initial_shared_version(object_id, world: "localnet")

    %{
      object_id: hex_to_bytes!(object_id),
      initial_shared_version: version
    }
  end

  defp hex_to_bytes!("0x" <> hex) do
    padded = String.pad_leading(hex, 64, "0")
    Base.decode16!(padded, case: :mixed)
  end

  defp hex_to_bytes!(hex) when is_binary(hex) do
    hex_to_bytes!("0x" <> hex)
  end

  defp sigil_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{sigil_package_id: id} = Map.fetch!(worlds, world)
    id
  end

  # ── Database Seeding ─────────────────────────────────────────────────

  defp seed_database!(env) do
    info("=== Database Seeding ===")

    seed_intel_reports!(env)
    seed_intel_listings!(env)
    seed_alerts!(env)
    seed_pseudonyms!(env)
    seed_reputation_scores!()
    seed_webhook_configs!()

    info("  Database seeding complete!")
  end

  defp seed_intel_reports!(env) do
    now = DateTime.utc_now()

    reports = [
      # Tribe 100 location reports
      %{
        tribe_id: 100,
        assembly_id: env.gate_1,
        solar_system_id: 30_002_187,
        label: "Starfall Gate",
        report_type: :location,
        notes: "Gate active at Jita",
        reported_by: env.player_a_addr,
        reported_by_name: "Kira Voss",
        reported_by_character_id: env.char_a1
      },
      %{
        tribe_id: 100,
        assembly_id: env.nwn,
        solar_system_id: 30_000_142,
        label: "Nexus Prime",
        report_type: :location,
        notes: "Network node fueled at Amarr",
        reported_by: env.player_a_addr,
        reported_by_name: "Kira Voss",
        reported_by_character_id: env.char_a1
      },
      # Tribe 100 scouting reports
      %{
        tribe_id: 100,
        solar_system_id: 30_002_659,
        report_type: :scouting,
        notes: "3 hostile turrets spotted in Dodixie — avoid southern gates",
        reported_by: env.player_b_addr,
        reported_by_name: "Jace Morrow",
        reported_by_character_id: env.char_b1
      },
      %{
        tribe_id: 100,
        solar_system_id: 30_002_187,
        report_type: :scouting,
        notes: "Safe corridor through Jita — no hostiles on scan",
        reported_by: env.player_a_addr,
        reported_by_name: "Kira Voss",
        reported_by_character_id: env.char_a1
      },
      # Tribe 200 reports (isolated from tribe 100)
      %{
        tribe_id: 200,
        assembly_id: env.gate_b,
        solar_system_id: 30_045_328,
        label: "Obsidian Gate",
        report_type: :location,
        notes: "Forward gate at Hek",
        reported_by: env.admin_addr,
        reported_by_name: "Nyx Tanaka",
        reported_by_character_id: env.char_c1
      },
      %{
        tribe_id: 200,
        solar_system_id: 30_002_187,
        report_type: :scouting,
        notes: "Tribe 100 has heavy presence in Jita — approach with caution",
        reported_by: env.admin_addr,
        reported_by_name: "Nyx Tanaka",
        reported_by_character_id: env.char_c1
      }
    ]

    for attrs <- reports do
      changeset_fn =
        if attrs[:report_type] == :location,
          do: &Sigil.Intel.IntelReport.location_changeset/2,
          else: &Sigil.Intel.IntelReport.scouting_changeset/2

      %Sigil.Intel.IntelReport{}
      |> changeset_fn.(attrs)
      |> Ecto.Changeset.put_change(:inserted_at, now)
      |> Ecto.Changeset.put_change(:updated_at, now)
      |> Sigil.Repo.insert!()
    end

    info("  Inserted #{length(reports)} intel reports")
  end

  defp seed_intel_listings!(env) do
    now = DateTime.utc_now()

    pseudo_a1 = "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

    listings = [
      %{
        id: fake_id(1),
        seller_address: pseudo_a1,
        client_nonce: 1001,
        price_mist: 100_000_000,
        report_type: 1,
        solar_system_id: 30_002_187,
        description: "Gate locations in Jita corridor",
        status: :active
      },
      %{
        id: fake_id(2),
        seller_address: pseudo_a1,
        client_nonce: 1002,
        price_mist: 250_000_000,
        report_type: 2,
        solar_system_id: 30_000_142,
        description: "Scouting report: Amarr defense grid",
        status: :active,
        restricted_to_tribe_id: 100
      },
      %{
        id: fake_id(3),
        seller_address: env.admin_addr,
        client_nonce: 1003,
        price_mist: 50_000_000,
        report_type: 1,
        solar_system_id: 30_002_659,
        description: "Dodixie gate network survey",
        status: :active
      },
      %{
        id: fake_id(4),
        seller_address: pseudo_a1,
        client_nonce: 1004,
        price_mist: 150_000_000,
        report_type: 2,
        solar_system_id: 30_002_187,
        description: "Jita hostiles: detailed tactical report",
        status: :sold,
        buyer_address: env.player_b_addr
      },
      %{
        id: fake_id(5),
        seller_address: pseudo_a1,
        client_nonce: 1005,
        price_mist: 75_000_000,
        report_type: 1,
        solar_system_id: 30_000_142,
        description: "Amarr station locations (outdated)",
        status: :cancelled
      }
    ]

    for attrs <- listings do
      %Sigil.Intel.IntelListing{}
      |> Sigil.Intel.IntelListing.changeset(attrs)
      |> Ecto.Changeset.put_change(:inserted_at, now)
      |> Ecto.Changeset.put_change(:updated_at, now)
      |> Sigil.Repo.insert!()
    end

    info("  Inserted #{length(listings)} intel listings")
  end

  defp seed_alerts!(env) do
    now = DateTime.utc_now()

    # Assembly IDs for distributing across alerts (avoids unique index violations)
    # {assembly_id, assembly_name, owning_character_name}
    assemblies = [
      {env.gate_1, "Starfall Gate", "frontier-character-a"},
      {env.nwn, "Nexus Prime", "frontier-character-a"},
      {env.turret, "Sentinel Alpha", "frontier-character-a"},
      {env.ssu, "Depot Kappa", "frontier-character-a"},
      {env.gate_b, "Ironveil Gate", "frontier-character-a"},
      {env.nwn_b, "Beacon Tau", "frontier-character-a"}
    ]

    # Build varied alerts
    # Fuel alerts (new)
    # Offline/extension alerts
    # Hostile activity
    # Reputation threshold alerts (no assembly_id)
    # Padding alerts for infinite scroll (>25 total, use dismissed to avoid dedup index)
    alerts =
      build_alerts(env, assemblies, [
        {"fuel_low", "warning", "new", 0, "Fuel below 20% — refuel recommended"},
        {"fuel_low", "warning", "new", 1, "Fuel reserves declining steadily"},
        {"fuel_critical", "critical", "new", 2, "Fuel depletes in under 2 hours!"},
        {"fuel_critical", "critical", "new", 3, "Critical: fuel nearly exhausted"},
        {"fuel_low", "warning", "new", 4, "Fuel below threshold"}
      ]) ++
        build_alerts(env, assemblies, [
          {"assembly_offline", "warning", "new", 0, "Assembly went offline unexpectedly"},
          {"assembly_offline", "warning", "acknowledged", 1, "Assembly offline — investigating"},
          {"assembly_offline", "warning", "acknowledged", 2, "Assembly unreachable"},
          {"extension_changed", "info", "new", 3, "Gate extension was updated"},
          {"extension_changed", "info", "new", 4, "Extension configuration changed"},
          {"extension_changed", "info", "dismissed", 0, "Extension change noted"}
        ]) ++
        build_alerts(env, assemblies, [
          {"hostile_activity", "warning", "new", 1, "Hostile engagement detected nearby"},
          {"hostile_activity", "warning", "dismissed", 2, "Hostile contact — resolved"},
          {"hostile_activity", "critical", "new", 3, "Multiple hostiles in system!"}
        ]) ++
        [
          %{
            type: "reputation_threshold_crossed",
            severity: "info",
            status: "new",
            account_address: env.player_a_addr,
            tribe_id: 100,
            message: "Reputation with Tribe 200 crossed HOSTILE threshold",
            metadata: %{target_tribe_id: 200, new_tier: "hostile"}
          },
          %{
            type: "reputation_threshold_crossed",
            severity: "warning",
            status: "new",
            account_address: env.player_a_addr,
            tribe_id: 100,
            message: "Reputation with Tribe 300 crossed FRIENDLY threshold",
            metadata: %{target_tribe_id: 300, new_tier: "friendly"}
          },
          %{
            type: "reputation_threshold_crossed",
            severity: "info",
            status: "acknowledged",
            account_address: env.player_a_addr,
            tribe_id: 100,
            message: "Reputation threshold change detected",
            metadata: %{target_tribe_id: 400, new_tier: "allied"}
          }
        ] ++
        for i <- 1..17 do
          {asm_id, asm_name, char_name} = Enum.at(assemblies, rem(i, length(assemblies)))

          %{
            type:
              Enum.at(
                ["fuel_low", "assembly_offline", "extension_changed", "hostile_activity"],
                rem(i, 4)
              ),
            severity: Enum.at(["info", "warning", "critical"], rem(i, 3)),
            status: "dismissed",
            assembly_id: asm_id,
            assembly_name: asm_name,
            account_address: env.player_a_addr,
            tribe_id: 100,
            message: "Historical alert ##{i}",
            metadata: %{character_name: char_name},
            dismissed_at: DateTime.add(now, -i * 3600)
          }
        end

    for attrs <- alerts do
      %Sigil.Alerts.Alert{}
      |> Sigil.Alerts.Alert.changeset(attrs)
      |> Ecto.Changeset.put_change(:inserted_at, now)
      |> Ecto.Changeset.put_change(:updated_at, now)
      |> Sigil.Repo.insert!()
    end

    info("  Inserted #{length(alerts)} alerts")
  end

  defp build_alerts(env, assemblies, specs) do
    for {type, severity, status, asm_idx, message} <- specs do
      {asm_id, asm_name, char_name} = Enum.at(assemblies, rem(asm_idx, length(assemblies)))

      base = %{
        type: type,
        severity: severity,
        status: status,
        assembly_id: asm_id,
        assembly_name: asm_name,
        account_address: env.player_a_addr,
        tribe_id: 100,
        message: message,
        metadata: %{character_name: char_name}
      }

      if status == "dismissed" do
        Map.put(base, :dismissed_at, DateTime.utc_now())
      else
        base
      end
    end
  end

  defp seed_pseudonyms!(env) do
    pseudonyms = [
      %{
        account_address: env.player_a_addr,
        pseudonym_address: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        encrypted_private_key: :crypto.strong_rand_bytes(64)
      },
      %{
        account_address: env.player_a_addr,
        pseudonym_address: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        encrypted_private_key: :crypto.strong_rand_bytes(64)
      },
      %{
        account_address: env.player_b_addr,
        pseudonym_address: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        encrypted_private_key: :crypto.strong_rand_bytes(64)
      }
    ]

    for attrs <- pseudonyms do
      %Sigil.Pseudonym{}
      |> Sigil.Pseudonym.changeset(attrs)
      |> Sigil.Repo.insert!()
    end

    info("  Inserted #{length(pseudonyms)} pseudonyms")
  end

  defp seed_reputation_scores! do
    default_thresholds = %{
      hostile_max: -200,
      unfriendly_max: -50,
      friendly_min: 100,
      allied_min: 300
    }

    scores = [
      %{
        source_tribe_id: 100,
        target_tribe_id: 200,
        score: -350,
        pinned: true,
        pinned_standing: 1,
        tier_thresholds: default_thresholds,
        last_event_at: DateTime.utc_now(),
        last_decay_at: DateTime.utc_now()
      },
      %{
        source_tribe_id: 200,
        target_tribe_id: 100,
        score: -700,
        pinned: false,
        tier_thresholds: default_thresholds,
        last_event_at: DateTime.utc_now(),
        last_decay_at: DateTime.utc_now()
      },
      %{
        source_tribe_id: 100,
        target_tribe_id: 300,
        score: 50,
        pinned: false,
        tier_thresholds: default_thresholds,
        last_event_at: DateTime.utc_now(),
        last_decay_at: DateTime.utc_now()
      }
    ]

    for attrs <- scores do
      %Sigil.Reputation.ReputationScore{}
      |> Sigil.Reputation.ReputationScore.changeset(attrs)
      |> Sigil.Repo.insert!()
    end

    info("  Inserted #{length(scores)} reputation scores")
  end

  defp seed_webhook_configs! do
    %Sigil.Alerts.WebhookConfig{}
    |> Sigil.Alerts.WebhookConfig.changeset(%{
      tribe_id: 100,
      webhook_url: "https://discord.com/api/webhooks/000000/placeholder-uat-testing",
      service_type: "discord",
      enabled: true
    })
    |> Sigil.Repo.insert!()

    info("  Inserted 1 webhook config")
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp fake_id(n) do
    "0x" <> String.pad_leading(Integer.to_string(n, 16), 64, "0")
  end

  defp info(msg), do: Mix.shell().info(msg)
end
