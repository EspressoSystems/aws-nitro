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
  runtimePackagePaths = lib.concatStringsSep " " (map (pkg: "${pkg}") runtimePackages);

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

    mkdir -p $out/bin $out/libexec

    cp ${entrypointScript}/aws-nitro-entrypoint.sh $out/libexec/aws-nitro-entrypoint.sh
    cp ${entrypointScript}/server.sh $out/libexec/server.sh
    chmod +x $out/libexec/aws-nitro-entrypoint.sh $out/libexec/server.sh

    substituteInPlace $out/libexec/aws-nitro-entrypoint.sh \
      --replace "/usr/local/bin/nitro" "${nitroBinary}/bin/nitro" \
      --replace "SYSTEM:./server.sh" "SYSTEM:$out/libexec/server.sh"

    mkdir -p $out/libexec/bin $out/libexec/lib

    for pkg in ${runtimePackagePaths}; do
      if [ -d "$pkg/bin" ] && [ "$(ls -A "$pkg/bin" 2>/dev/null)" != "" ]; then
        cp -L "$pkg/bin"/* $out/libexec/bin/
      fi
      if [ -d "$pkg/lib" ]; then
        cp -Lr "$pkg/lib/." $out/libexec/lib/
      fi
    done

    for binary in $out/libexec/bin/*; do
      if [ -f "$binary" ]; then
        ln -sf $binary $out/bin/$(basename "$binary")
      fi
    done

    cat > $out/bin/entrypoint <<EOF
#!${pkgs.runtimeShell}
export PATH=${runtimePath}:$PATH:$out/libexec/bin
export LD_LIBRARY_PATH=$out/libexec/lib
export NITRO_BIN="${nitroBinary}/bin/nitro"
exec $out/libexec/aws-nitro-entrypoint.sh
EOF

    chmod +x $out/bin/entrypoint

    runHook postInstall
  '';
}

