defmodule Mix.Tasks.Sigil.ZkSetup do
  @moduledoc """
  Builds ZK circuit artifacts and copies them to `priv/static/zk/`.

  This task compiles the Poseidon commitment circuit, runs the Groth16
  trusted setup ceremony, exports the verification key, and generates
  test vectors used by Move and JS tests.

  ## Prerequisites

    * `circom` — Circom compiler (install via `cargo install circom` or
      download from https://github.com/iden3/circom/releases)
    * `node` / `npm` — Node.js runtime for snarkjs

  ## Usage

      # Build everything (compile + setup + copy)
      mix sigil.zk_setup

      # Only regenerate test vectors (circuit already built)
      mix sigil.zk_setup --only vectors

  ## What it produces

    * `priv/static/zk/intel_commitment.wasm` — Circuit WASM (browser witness generation)
    * `priv/static/zk/intel_commitment_final.zkey` — Ceremony zkey (browser proof generation)
    * `priv/static/zk/verification_key.json` — Verification key (Move contract PVK reference)
    * `priv/static/zk/test_vectors.json` — Known-good proof for tests

  ## Important

  The `.zkey` is ceremony-specific (non-deterministic). Once the Move contract
  is deployed with a matching `PreparedVerifyingKey`, the `.zkey` must not be
  regenerated — proofs would no longer verify. Before contract deployment,
  regeneration is safe.
  """

  use Mix.Task

  @shortdoc "Build ZK circuit artifacts for intel marketplace"

  @circuits_dir Path.join(File.cwd!(), "circuits")
  @priv_zk_dir Path.join([File.cwd!(), "priv", "static", "zk"])
  @build_dir Path.join(@circuits_dir, "build")

  @artifacts [
    {"intel_commitment_js/intel_commitment.wasm", "intel_commitment.wasm"},
    {"intel_commitment_final.zkey", "intel_commitment_final.zkey"},
    {"verification_key.json", "verification_key.json"}
  ]

  @doc "Builds ZK circuit artifacts. See module docs for options."
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [only: :string])

    case Keyword.get(opts, :only) do
      "vectors" ->
        ensure_npm_deps()
        generate_test_vectors()

      nil ->
        check_prerequisites()
        ensure_npm_deps()
        build_circuit()
        copy_artifacts()
        generate_test_vectors()
        print_summary()

      other ->
        Mix.raise("Unknown --only value: #{other}. Valid: vectors")
    end

    :ok
  end

  defp check_prerequisites do
    circom = find_circom()

    unless circom do
      Mix.raise("""
      circom not found on $PATH or at ~/.local/bin/circom.

      Install via:
        curl -sL https://github.com/iden3/circom/releases/download/v2.2.3/circom-linux-amd64 \\
          -o ~/.local/bin/circom && chmod +x ~/.local/bin/circom

      Or via Rust:
        cargo install --locked circom
      """)
    end

    unless System.find_executable("node") do
      Mix.raise("node not found. Install Node.js (v18+) for snarkjs.")
    end

    Mix.shell().info("Prerequisites: circom=#{circom}, node=#{System.find_executable("node")}")
  end

  defp find_circom do
    local = Path.join([System.user_home!(), ".local", "bin", "circom"])

    case {File.exists?(local), System.find_executable("circom")} do
      {true, _} -> local
      {false, exe} when is_binary(exe) -> exe
      {false, _} -> nil
    end
  end

  defp ensure_npm_deps do
    unless File.exists?(Path.join(@circuits_dir, "node_modules")) do
      Mix.shell().info("Installing circuit npm dependencies...")
      run_cmd("npm", ["install"], @circuits_dir)
    end
  end

  defp build_circuit do
    Mix.shell().info("\n=== Building ZK circuit ===\n")
    File.mkdir_p!(@build_dir)
    File.mkdir_p!(@priv_zk_dir)

    run_cmd("npm", ["run", "build"], @circuits_dir)
  end

  defp copy_artifacts do
    Mix.shell().info("\nCopying artifacts to priv/static/zk/...")

    for {src, dest} <- @artifacts do
      src_path = Path.join(@build_dir, src)
      dest_path = Path.join(@priv_zk_dir, dest)

      if File.exists?(src_path) do
        File.cp!(src_path, dest_path)
        size = File.stat!(dest_path).size |> div(1024)
        Mix.shell().info("  #{dest} (#{size} KB)")
      else
        Mix.shell().error("  WARNING: #{src} not found in build/")
      end
    end
  end

  defp generate_test_vectors do
    Mix.shell().info("\nGenerating test vectors...")
    run_cmd("npm", ["run", "test-vectors"], @circuits_dir)

    # Copy test vectors to priv/static/zk/ for dev convenience
    tv_src = Path.join([@build_dir, "test_vectors", "test_vectors.json"])
    tv_dest = Path.join(@priv_zk_dir, "test_vectors.json")

    if File.exists?(tv_src) do
      File.cp!(tv_src, tv_dest)
      Mix.shell().info("  test_vectors.json copied to priv/static/zk/")
    end
  end

  defp print_summary do
    Mix.shell().info("""

    === ZK Setup Complete ===

    Artifacts in: priv/static/zk/
    Circuit: intel_commitment.circom (Poseidon with 4 inputs on BN254)

    Artifacts are committed to git (required for Gigalixir deploy).
    Regenerate with: mix sigil.zk_setup
    Regenerate test vectors only: mix sigil.zk_setup --only vectors
    """)
  end

  defp run_cmd(cmd, args, cwd) do
    case System.cmd(cmd, args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} ->
        Mix.shell().info(output)

      {output, code} ->
        Mix.shell().error(output)
        Mix.raise("#{cmd} #{Enum.join(args, " ")} failed with exit code #{code}")
    end
  end
end
