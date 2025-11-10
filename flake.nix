{
  description = "Reproducible AWS Nitro EIF builds for the batch poster using nix-enclaver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-enclaver = {
      url = "github:joshdoman/nix-enclaver/v0.6.1";
      inputs.nixpkgs.follows = "nixpkgs";
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
        nitroBinary = nix-enclaver.packages.${system}.enclaver;

        appPackage = pkgs.callPackage ./nix/app { inherit nitroBinary; };

        nativeEif = enclaverLib.makeAppEif {
          appPackage = appPackage;
          configFile = enclaverYaml;
        };

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
          default = nativeEif.eif;
          eif = nativeEif.eif;
          rootfs = nativeEif.rootfs;
          app = appPackage;
          enclaver = nix-enclaver.packages.${system}.enclaver;
          x86_64-eif = x86Eif.eif;
          aarch64-eif = armEif.eif;
        };

        apps = {
          default = {
            type = "app";
            program = "${nix-enclaver.packages.${system}.enclaver}/bin/enclaver";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            nix-enclaver.packages.${system}.enclaver
            pkgs.jq
            pkgs.socat
          ]
          ++ lib.optionals (pkgs.stdenv.isLinux && pkgs ? nfs-utils) [ pkgs.nfs-utils ]
          ++ lib.optionals (pkgs.stdenv.isLinux && pkgs ? aws-nitro-enclaves-cli) [ pkgs.aws-nitro-enclaves-cli ]
          ++ lib.optionals (pkgs ? awscli2) [ pkgs.awscli2 ];

          shellHook = ''
            echo "Run 'nix build .#eif' to produce the enclave image file."
          '';
        };
      }) // {
        lib = nix-enclaver.lib;
      };
}

