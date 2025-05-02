{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-pkgset.url = "github:szlend/nix-pkgset";
    nix-pkgset.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs@{ nixpkgs, flake-parts, nix-pkgset, ... }: let
    lib = nixpkgs.lib;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [(flake-parts.lib.mkTransposedPerSystemModule {
        name = "lab";
        option = nixpkgs.lib.mkOption {
          type = nixpkgs.lib.types.lazyAttrsOf nixpkgs.lib.types.unspecified; 
          default = {};
        };
        file = ./flake.nix;
      })];
      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = { pkgs, system, ... }: let 
        lab = pkgs.callPackage ./default.nix { inherit (nix-pkgset.lib) makePackageSet; };
      in {
        inherit lab;
        packages = {
        };
        devShells = {
          default = pkgs.mkShell {
            packages = (with pkgs; [
              jq oras
            ]) ++ (with lab; [
              third-party.talos.talosctl
            ]);
          };
          update-script = pkgs.mkShell {
            packages = with pkgs; [
              cosign
              git
              (python3.withPackages (pythonPkgs: with pythonPkgs; [
                tomlkit
                gitpython
              ]))
            ];
          };
        };
      };
    };
}
