{lib, pkgs, lock}: let
  digestParts = lib.strings.splitString ":" lock.talos.talosctl.digest;
  digestAlgo = builtins.elemAt digestParts 0;
  digestHash = builtins.elemAt digestParts 1;
in pkgs.pkgsBuildTarget.stdenv.mkDerivation {
  pname = "talosctl";
  version = lock.talos.version;
  src = pkgs.fetchurl {
    # TODO: obviously this only works on x86_64
    url = "https://github.com/${lock.talos.talosctl.package}/releases/download/${lock.talos.version}/talosctl-linux-amd64";
    ${digestAlgo} = digestHash;
  };
  dontUnpack = true;
  installPhase = "set -e; mkdir -p $out/bin; cp $src $out/bin/talosctl; chmod +x $out/bin/talosctl";
}

