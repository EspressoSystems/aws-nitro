{ pkgs, lib, nitroBinary }:

let
  basePackages = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    jq
    socat
    procps
    iproute2
    nettools
    util-linux
  ];

  runtimePackages = basePackages
    ++ lib.optionals (pkgs ? nfs-utils) [ pkgs.nfs-utils ];

  runtimePath = lib.makeBinPath runtimePackages;

  entrypointScript = pkgs.runCommand "batch-poster-entrypoint" { } ''
    mkdir -p $out
    cp ${../../docker/aws-nitro-entrypoint.sh} $out/aws-nitro-entrypoint.sh
    cp ${../../docker/server.sh} $out/server.sh
    chmod +x $out/aws-nitro-entrypoint.sh $out/server.sh
  '';

in pkgs.stdenv.mkDerivation {
  pname = "batch-poster-app";
  version = "0.1.0";

  src = entrypointScript;

  dontUnpack = true;

  nativeBuildInputs = with pkgs; [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Copy scripts and substitute paths
    cp $src/aws-nitro-entrypoint.sh $out/bin/aws-nitro-entrypoint.sh
    cp $src/server.sh $out/bin/server.sh
    chmod +x $out/bin/aws-nitro-entrypoint.sh $out/bin/server.sh

    # Replace hardcoded paths with Nix-provided binaries
    substituteInPlace $out/bin/aws-nitro-entrypoint.sh \
      --replace "/usr/local/bin/nitro" "${nitroBinary}/bin/nitro"

    # Create the entrypoint that sets up PATH and runs the script
    cat > $out/bin/entrypoint <<EOF
    #!${pkgs.runtimeShell}
    export PATH=${runtimePath}:$PATH
    export NITRO_BIN="${nitroBinary}/bin/nitro"
    exec $out/bin/aws-nitro-entrypoint.sh
    EOF

    chmod +x $out/bin/entrypoint

    runHook postInstall
  '';
}

