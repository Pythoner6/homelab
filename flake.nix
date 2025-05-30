{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-pkgset.url = "github:szlend/nix-pkgset";
    nix-pkgset.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs@{ nixpkgs, nixpkgs-unstable, flake-parts, nix-pkgset, ... }: let
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
      perSystem = { pkgs, pkgs-unstable, system, ... }: let 
        lab = pkgs.callPackage ./default.nix { inherit (nix-pkgset.lib) makePackageSet; inherit pkgs-unstable; };
        rpi-config = {
          arch = "arm64";
          overlay = {
            name = "rpi_generic";
            options.configTxtAppend = ''
              dtparam=spi=on
              dtoverlay=tpm-slb9670
              dtoverlay=dwc2,dr_mode=host
              otg_mode=1
            '';
          };
          extensions = ["kata-containers" "zfs"];
        };
      in {
        _module.args.pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
        inherit lab;
        packages = {
          rpi-installer = lab.third-party.talos.boot-assets.installer rpi-config;
          rpi-image = lab.third-party.talos.boot-assets.rpi-image (lib.attrsets.recursiveUpdate rpi-config {
            customization.extraKernelArgs = ["ip=10.16.2.6::10.16.2.2:255.255.255.0::eth0:off"];
          });
          test3 = lab.nix.cue.cache [lab.third-party.talos.config.schema];
          k8s = lab.nix.cue.cache [lab.third-party.k8s.cuePkg];
        };
        devShells = {
          default = pkgs.mkShell {
            packages = (with pkgs; [
              jq nixd crane kubernetes-helm timoni
            ]) ++ (with lab; [
              third-party.talos.talosctl
              third-party.cue
            ]);
          };
          update-script = pkgs.mkShell {
            packages = (with pkgs; [
              cosign
              git
              (python3.withPackages (pythonPkgs: with pythonPkgs; [
                tomlkit
                gitpython
              ]))
            ]) ++ (with pkgs-unstable; [
              go
            ]);
          };
        };
      };
    };
}
