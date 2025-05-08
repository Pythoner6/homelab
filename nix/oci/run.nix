# === nix.oci.run ===
# Given an oci image (as a layout derivation), run it as a container inside a derivation
# Uses podman inside runInLinuxVM
{pkgs, lib, drvName}: {
  image,
  entrypoint ? null,
  cmd ? [],
  volumes ? {},
  stdin ? null,
  install,
  extraNativeBuildInputs ? [],
}: let
  podmanCmd = builtins.toJSON (lib.lists.flatten [
    "podman" "run" "-i" "--rm" "--privileged"
    (lib.attrsets.mapAttrsToList (k: v: ["-v" "${k}:${v}"]) volumes)
    (if entrypoint == null then [] else ["--entrypoint" (
      if builtins.isList entrypoint then (builtins.toJSON entrypoint)
      else entrypoint
    )])
    "oci:${image}"
    cmd
  ]);
in pkgs.vmTools.runInLinuxVM (pkgs.stdenvNoCC.mkDerivation ((if stdin == null then {} else {
  STDIN = stdin;
}) // {
    name = "run-${drvName image}";
    dontUnpack = true;
    nativeBuildInputs = with pkgs; [
      podman util-linux yq-go jq kmod
    ] ++ extraNativeBuildInputs;
    memSize = 4096;
    CMD = podmanCmd;
    configurePhase = ''
      runHook preConfigure
      export HOME="$(mktemp -d)"
      mkdir -p $HOME/.config/containers/
      cat <<EOF > $HOME/.config/containers/policy.json
      {
        "default": [{"type": "reject"}],
        "transports": {"oci": {"": [{"type": "insecureAcceptAnything"}]}}
      }
      EOF

      mkdir -p /sys/fs/cgroup
      mount -t cgroup2 none /sys/fs/cgroup
      modprobe loop
      runHook postConfiugre
    '';
    buildPhase = ''
      runHook preBuild
      declare -a command="($(echo "$CMD" | jq -r '@sh'))"
      mkdir "$TMPDIR/rundir"
      pushd "$TMPDIR/rundir" > /dev/null
      if [[ -n "$STDIN" ]]; then
        cat "$STDIN" | "''${command[@]}"
      else
        "''${command[@]}"
      fi
      popd
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      pushd "$TMPDIR/rundir" > /dev/null
      ${install}
      popd
      runHook postInstall
    '';
  }))
