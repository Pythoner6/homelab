{pkgs, pkgs-unstable, lock}: pkgs-unstable.talosctl.overrideAttrs (final: prev: {
  version = lock.talos.version;
  src = pkgs.fetchFromGitHub {
    inherit (prev.src) owner repo;
    rev = final.version;
    hash = lock.talos.talosctl.srcHash;
  };
  vendorHash = lock.talos.talosctl.vendorHash;
})

