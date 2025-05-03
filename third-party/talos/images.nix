{lib, lock, nix, system}: lib.attrsets.mapAttrs (name: details: arch: nix.oci.pull {
  image = details.ref;
  tag = lock.talos.version;
  digest = details.digest;
  inherit arch;
}) lock.talos.images
