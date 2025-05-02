{lib, lock, nix, system}: lib.attrsets.mapAttrs (name: details: nix.oci.pull {
  image = details.ref;
  tag = lock.talos.version;
  digest = details.digest;
  arch = {
    "x86_64-linux" = "amd64";
    "aarch64-linux" = "arm64";
  }.${system};
}) lock.talos.images
