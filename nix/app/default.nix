{ pkgs, lib, nitroBinary }:

let
  runtimePackages = with pkgs; [
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
    nfs-utils
  ];

  runtimePath = lib.makeBinPath runtimePackages;

  entrypointScript = pkgs.runCommand "batch-poster-entrypoint" {
    SOURCE_DATE_EPOCH = "0";
  } ''
    mkdir -p $out
    cp ${../../docker/aws-nitro-entrypoint.sh} $out/aws-nitro-entrypoint.sh
    cp ${../../docker/server.sh} $out/server.sh
    chmod +x $out/aws-nitro-entrypoint.sh $out/server.sh
  '';

  srsFile = pkgs.fetchurl {
    url = "https://github.com/EspressoSystems/ark-srs/releases/download/v0.2.0/kzg10-aztec20-srs-1048584.bin";
    sha256 = "17ghkq397r1f8c093lwaah9gwm39k57kf3rfrgjgwjab5vl87vfd";
  };

in pkgs.stdenv.mkDerivation {
  pname = "batch-poster-app";
  version = "0.1.0";
  src = entrypointScript;
  dontUnpack = true;
  SOURCE_DATE_EPOCH = "0";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/home/user

    cp $src/aws-nitro-entrypoint.sh $out/bin/
    cp $src/server.sh $out/bin/
    chmod +x $out/bin/aws-nitro-entrypoint.sh $out/bin/server.sh

    cp ${srsFile} $out/home/user/kzg10-aztec20-srs-1048584.bin

    substituteInPlace $out/bin/aws-nitro-entrypoint.sh \
      --replace "/usr/local/bin/nitro" "${nitroBinary}/bin/nitro"
    
    substituteInPlace $out/bin/server.sh \
      --replace "/usr/local/bin/nitro" "${nitroBinary}/bin/nitro"

    cat > $out/bin/entrypoint <<EOF
#!/bin/sh
export PATH="${runtimePath}:\$PATH"
export AZTEC_SRS_PATH="/home/user/kzg10-aztec20-srs-1048584.bin"
export HOME="/home/user"
exec $out/bin/aws-nitro-entrypoint.sh "\$@"
EOF
    chmod +x $out/bin/entrypoint

    runHook postInstall
  '';
}
