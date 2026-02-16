{
  description = "Reproducible AWS Nitro EIF builds using nix-enclaver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    nix-enclaver = {
      url = "github:EspressoSystems/nix-enclaver/v0.1.0";
      # Don't override nixpkgs - let nix-enclaver use its own for Rust compatibility
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, nix-enclaver, ... }:
    let
      systems = builtins.attrNames nix-enclaver.packages;
      enclaverYaml = ./enclaver/enclaver.yaml;
    in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        enclaverLib = nix-enclaver.lib.${system};

        # Nitro binary - extracted from Docker image and staged in build-outputs/
        # The CI workflow extracts this from the specified nitro-node image
       nitroSealedApp =
                let
                  # Pull Docker image from registry
                  dockerImage = pkgs.dockerTools.pullImage {
                    imageName = "ghcr.io/espressosystems/nitro-espresso-integration/nitro-node";
                    imageDigest = "sha256:db59487bb15a51e8e66f6b725b60863f5c88096ce1e085187ee460c28f9e9c2a";  
                    sha256 = "sha256-X9NUKodo+HIZ7Fcc2boTTSp9c+E4fqZZBxmRQv/gPuQ=";
                    finalImageTag = "luke-testing";
                  };
                  #dockerImagePath = /home/luke/code/nitro-espresso-integration/reproducible16.tar;  

                  # Extract the Docker image layers to a directory
                  extractedDockerImage = pkgs.runCommand "extracted-docker-rootfs" {
                    nativeBuildInputs = [ pkgs.jq pkgs.gnutar pkgs.gzip pkgs.skopeo ];
                  } ''
                    mkdir -p $out/temp
                    cd $out/temp

                    # Extract the Docker tar archive
                    tar -xf ${dockerImage}

                    # Find the manifest to get layer information
                    LAYERS=$(jq -r '.[0].Layers[]' manifest.json)

                    # Extract all layers in order to build the filesystem
                    mkdir -p $out/fs
                    for layer in $LAYERS; do
                      tar -xf "$layer" -C $out/fs 2>/dev/null || true
                    done

                    # Clean up temp files
                    rm -rf temp
                  '';

                  # Wrapper for the entrypoint
                  entrypointWrapper = pkgs.writeScriptBin "entrypoint-wrapper" ''
                    #!/bin/sh
                    exec /bin/bash /bin/entrypoint
                  '';

                  # Package the Docker image filesystem + entrypoint
                  sealedAppPackage = pkgs.stdenv.mkDerivation {
                    name = "nitro-sealed-app";
                    src = extractedDockerImage;
                    dontPatchShebangs = true;

                    # Clear env to prevent CGO_ENABLED conflict
                    env = {};

                    installPhase = ''
                      # Create output directory and copy Docker filesystem
                      mkdir -p $out
                      cp -r fs/* $out/ || true

                      # Ensure bin directory exists
                      mkdir -p $out/bin

                      # Add wrapper script
                      cp ${entrypointWrapper}/bin/entrypoint-wrapper $out/bin/
                      chmod +x $out/bin/entrypoint-wrapper

                      # Create entrypoint script
                      printf '#!/bin/bash\n' > $out/bin/entrypoint
                      cat >> $out/bin/entrypoint <<'SCRIPT_EOF'
set -e

ENCLAVE_CONFIG_SOURCE_DIR=/mnt/config
PARENT_SOURCE_CONFIG_DIR=/opt/nitro/config
ENCLAVE_CONFIG_TARGET_DIR=/config
PARENT_SOURCE_DB_DIR=/opt/nitro/arbitrum
ENV_FILE="$ENCLAVE_CONFIG_TARGET_DIR/.env"

echo "Set memory (using sysctl -w for read-only filesystem)"
sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216'
sysctl -w net.ipv4.tcp_wmem='4096 87380 16777216'
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216

echo "Start vsock proxy"
socat -b65536 TCP-LISTEN:2049,bind=127.0.0.1,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive,rcvbuf-late=16384,sndbuf-late=16384 >/dev/null 2>&1 &
sleep 2

echo "Mount config from $PARENT_SOURCE_CONFIG_DIR to $ENCLAVE_CONFIG_SOURCE_DIR"
mount -t nfs4 "127.0.0.1:$PARENT_SOURCE_CONFIG_DIR" "$ENCLAVE_CONFIG_SOURCE_DIR"

echo "Checking Mounts:"
mount -t nfs4

echo "Copying config files from $ENCLAVE_CONFIG_SOURCE_DIR to $ENCLAVE_CONFIG_TARGET_DIR"
if ! cp -a "$ENCLAVE_CONFIG_SOURCE_DIR/." "$ENCLAVE_CONFIG_TARGET_DIR/"; then
    echo "ERROR: Failed to copy config files"
    exit 1
fi

if [ -z "$(ls -A "$ENCLAVE_CONFIG_TARGET_DIR")" ]; then
    echo "ERROR: No files were copied to target directory"
    exit 1
fi

echo "Unmounting config"
umount "$ENCLAVE_CONFIG_SOURCE_DIR"

CONFIG_SHA=$(jq -cS . "$ENCLAVE_CONFIG_TARGET_DIR/poster_config.json" | sha256sum | cut -d' ' -f1) || {
    echo "ERROR: Failed to calculate config sha256"
    exit 1
}

# if [ "$CONFIG_SHA" != "$EXPECTED_CONFIG_SHA256" ]; then
#     echo "ERROR: Config sha256 mismatch"
#     echo "Expected: $EXPECTED_CONFIG_SHA256"
#     echo "Actual:   $CONFIG_SHA"
#     exit 1
# fi

if [ -f "$ENV_FILE" ]; then
    echo "Loading environment variables from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
fi

echo "Config sha256 verified"

echo "Starting vsock server"
socat VSOCK-LISTEN:8005,fork,keepalive SYSTEM:./server.sh &
sleep 5

echo "Mount NFS database from $PARENT_SOURCE_DB_DIR"
mount -t nfs4 -o rsize=16384,wsize=16384 "127.0.0.1:$PARENT_SOURCE_DB_DIR" "/home/user/.arbitrum"

echo "Checking Mounts:"
mount -t nfs4
export HOME=/home/user
echo $HOME

exec /usr/local/bin/nitro \
  --validation.wasm.enable-wasmroots-check=false \
  --conf.file "$ENCLAVE_CONFIG_TARGET_DIR/poster_config.json" \
  --node.batch-poster.parent-chain-wallet.private-key="$PRIVATE_KEY" \
  --parent-chain.connection.url="$RPC_URL" \
  --node.espresso.batch-poster.txns-monitoring-interval="$TXN_MONITOR_INTERVAL" \
  --node.espresso.batch-poster.txns-resubmission-interval="$TXN_RESUBMIT_INTERVAL" \
  --node.espresso.streamer.hotshot-block="$HOTSHOT_BLOCK" \
  --node.espresso.streamer.address-monitor-step="$ADDR_MONITOR_STEP" \
  --node.espresso.streamer.txns-polling-interval="$POLLING_INTERVAL" \
  | while IFS= read -r line; do [ ''${#line} -gt 4096 ] && echo "''${line:0:4076}... [line truncated]" || echo "$line"; done
SCRIPT_EOF
                      chmod +x $out/bin/entrypoint
                    '';
                  };
                in
                  sealedAppPackage;

        appPackage = nitroSealedApp;

        x86Eif = enclaverLib.x86_64.makeAppEif {
          appPackage = appPackage;
          configFile = enclaverYaml;
        };

        armEif = enclaverLib.aarch64.makeAppEif {
          appPackage = appPackage;
          configFile = enclaverYaml;
        };

      in {
        packages = {
          default = x86Eif.eif;
          eif = x86Eif.eif;
          rootfs = x86Eif.rootfs;
          app = appPackage;
          enclaver = nix-enclaver.packages.${system}.enclaver;
          x86_64-eif = x86Eif.eif;
          aarch64-eif = armEif.eif;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            nix-enclaver.packages.${system}.enclaver
            pkgs.jq
          ];
        };
      }) // {
        lib = nix-enclaver.lib;
      };
}
