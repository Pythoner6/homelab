# === nix.oci.unpack ===
# Unpacks an oci-layout derivation into it's rootfs
#
# Uses podman because it handles more cases than umoci
# e.g. umoci will not accept application/vnd.docker.distribution.manifest.v2+json
# where podman will. However, this does require running podman in a bubblewrap
# so we can mount a cgroup fs for it to be happy
{pkgs, drvName}: oci: let
  script = pkgs.writeShellScript "script" ''
    set -eo pipefail
    # Podman needs cgroup mounted at the standard location
    mkdir -p /sys/fs/cgroup
    mount -t cgroup2 none /sys/fs/cgroup

    mkdir -p /etc/containers
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json

    id="$(podman create oci:$src)"
    podman export "$id" | tar -x -C $out
  '';
in pkgs.stdenvNoCC.mkDerivation {
  name = "${drvName oci}-unpack";
  nativeBuildInputs = with pkgs; [ podman bubblewrap util-linux ];
  src = oci;
  phases = ["unpackPhase"];
  unpackPhase = ''
    runHook preUnpack
    export HOME=/root
    mkdir "$out"
    bwrap \
      --cap-add ALL \
      --uid 0 --gid 0 \
      --unshare-all \
      --ro-bind /nix /nix \
      --dev /dev \
      --proc /proc \
      --bind "$TMPDIR" "$TMPDIR" \
      --bind "$(pwd)" "$(pwd)" \
      --bind "$out" "$out" \
      bash ${script}
    runHook postUnpack
  '';
}
