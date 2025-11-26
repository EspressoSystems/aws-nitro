{
  description = "Reproducible AWS Nitro EIF builds using nix-enclaver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    nix-enclaver = {
      url = "github:joshdoman/nix-enclaver/v0.6.1";
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
        nitroBinary = pkgs.stdenv.mkDerivation {
          pname = "nitro-node";
          version = "extracted";
          src = ./build-outputs/nitro;
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/bin
            cp $src $out/bin/nitro
            chmod +x $out/bin/nitro
          '';
          meta.platforms = [ "x86_64-linux" ];
        };

        appPackage = pkgs.callPackage ./nix/app { inherit nitroBinary; };

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
