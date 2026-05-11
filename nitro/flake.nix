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

        # SRS file for AZTEC KZG proof system
        # To get the hash: run `nix build` and copy the hash from the error output
        srsFile = pkgs.fetchurl {
          url = "https://github.com/EspressoSystems/ark-srs/releases/download/v0.2.0/kzg10-aztec20-srs-1048584.bin";
          sha256 = "sha256-ze2D6C5LSf7kyy4PN0+ZaVT+ElSK05EAQy7kkwae8J0=";
        };

        # Self-contained AWS CLI v2 bundle (includes its own Python interpreter)
        # Mirrors what Dockerfile.aws-nitro-poster installs via apt.
        # To get the hash: run `nix build` and copy the hash from the error output
        awsCliBundleZip = pkgs.fetchzip {
          url = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip";
          sha256 = "sha256-uFKl/li1xaymb34EPFc88glqkOa/Azwq1Q3p5YWdRIk=";
          # fetchzip strips the single top-level 'aws/' dir, so dist/ is at the root
        };

        # Build-time parameters (config hashes, AWS config) written by CI before
        # `nix build`. Falls back to an empty file for local builds.
        buildParamsScript = if builtins.pathExists ./build-params.sh
          then ./build-params.sh
          else pkgs.writeText "build-params.sh" "";

        # Docker image config — CI overwrites nitro-image.json via nix-prefetch-docker
        imageConfig = builtins.fromJSON (builtins.readFile ./nitro-image.json);

        nitroSealedApp =
          let
            dockerImage = pkgs.dockerTools.pullImage {
              imageName = imageConfig.imageName;
              imageDigest = imageConfig.imageDigest;
              sha256 = imageConfig.hash;
              finalImageTag = imageConfig.finalImageTag;
            };

            extractedDockerImage = pkgs.runCommand "extracted-docker-rootfs" {
              nativeBuildInputs = [ pkgs.jq pkgs.gnutar pkgs.gzip pkgs.skopeo ];
            } ''
              mkdir -p $out/temp
              cd $out/temp

              tar -xf ${dockerImage}

              LAYERS=$(jq -r '.[0].Layers[]' manifest.json)

              mkdir -p $out/fs
              for layer in $LAYERS; do
                tar -xf "$layer" -C $out/fs 2>/dev/null || true
              done

              rm -rf temp
            '';

            sealedAppPackage = pkgs.stdenv.mkDerivation {
              name = "nitro-sealed-app";
              src = extractedDockerImage;
              dontPatchShebangs = true;

              env = {};

              installPhase = ''
                mkdir -p $out

                # Copy Docker rootfs but skip standard binary dirs — Debian-linked binaries
                # in $out/bin would shadow nix tools at build time (makeAppEif adds appPackage
                # to nativeBuildInputs). Static busybox/bash/jq/socat from makeAppEif covers
                # all system tools at enclave runtime.
                for dir in fs/*/; do
                  name=$(basename "$dir")
                  case "$name" in
                    bin|sbin) ;;  # skip — Debian-linked, conflicts with nix build tools
                    usr)
                      mkdir -p $out/usr
                      for subdir in fs/usr/*/; do
                        subname=$(basename "$subdir")
                        case "$subname" in
                          bin|sbin) ;;  # skip
                          *) cp -r "$subdir" $out/usr/ 2>/dev/null || true ;;
                        esac
                      done
                      ;;
                    *) cp -r "$dir" $out/ 2>/dev/null || true ;;
                  esac
                done

                mkdir -p $out/bin
                mkdir -p $out/home/user/.arbitrum
                mkdir -p $out/config
                mkdir -p $out/mnt/config

                cp ${srsFile} $out/home/user/kzg10-aztec20-srs-1048584.bin

                mkdir -p $out/usr/local/aws-cli $out/usr/local/bin
                cp -r ${awsCliBundleZip}/dist/. $out/usr/local/aws-cli/
                ln -sf /usr/local/aws-cli/aws $out/usr/local/bin/aws
                ln -sf /usr/local/aws-cli/aws_completer $out/usr/local/bin/aws_completer

                mkdir -p $out/etc
                install -m644 ${buildParamsScript} $out/etc/build-params.sh

                install -m755 ${./docker/aws-nitro-entrypoint.sh} $out/bin/entrypoint
                install -m755 ${./docker/server.sh} $out/bin/server.sh
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
