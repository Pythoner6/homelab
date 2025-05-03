# === nix.oci.run ===
# Given an oci image (as a layout derivation), run it as a container inside a derivation
# Uses unshare/bubblewrap to setup an isolated environment and mimic running using
# an actual container runtime. Probably won't cover all cases, but good enough for
# the needs I have at the moment
{pkgs, drvName}: {
  image,
  entrypoint ? null,
  cmd ? null,
  volumes ? {},
  stdin ? null,
  install,
  extraNativeBuildInputs ? [],
}: pkgs.stdenvNoCC.mkDerivation ((if stdin == null then {} else {STDIN=stdin;}) // {
  name = "run-${drvName image}";
  src = image;
  ENTRYPOINT = builtins.toJSON entrypoint;
  CMD = builtins.toJSON cmd;
  VOLUMES = builtins.toJSON volumes;
  nativeBuildInputs = (with pkgs; [bubblewrap jq util-linux podman gnutar]) ++ extraNativeBuildInputs;
  unpackPhase = let
    unpack = pkgs.writeShellScript "unpack.sh" ''
      set -eo pipefail
      mkdir -p /sys/fs/cgroup
      mount -t cgroup2 none /sys/fs/cgroup
      mkdir -p /etc/containers
      echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json
      id="$(podman create "oci:$src")"
      podman export "$id" > rootfs.tar
      podman container inspect "$id" | jq .[].Config > config.json
    '';
  in ''
    runHook preUnpack
    bwrap \
      --cap-add ALL \
      --uid 0 --gid 0 \
      --unshare-all \
      --ro-bind /nix /nix \
      --dev /dev \
      --proc /proc \
      --bind "$TMPDIR" "$TMPDIR" \
      --bind "$(pwd)" "$(pwd)" \
      ${unpack}
    runHook postUnpack
  '';
  configurePhase = let
    configure = pkgs.writeShellScript "parse-config.sh" ''
      set -eo pipefail
      query="$(cat <<'EOF'
      (.User | split(":")) as [$user,$group] ?// [$user]
      | {
        user: $user,
        group: $group,
        args: [
          try $entrypoint[] // $entrypoint // try .Entrypoint[] // .Entrypoint // empty,
          try $cmd[] // $cmd // try .Cmd[] // .Cmd // empty
        ],
        cwd: (.WorkingDir // "/"),
        envs: (.Env // []) | map(
          match("([^=]*)=(.*)").captures
        | map(.string) as [$name,$value]
        | ["--setenv",$name,$value]
        ) | flatten,
        volumes: $volumes | to_entries | map(
          ["--bind", .key, .value]
        ) | flatten,
      }
      | to_entries
      | .[]
      | .key + "=" + (
        if .value == null
        then empty
        else if .value | type == "array"
          then "(" + (.value | @sh) + ")"
          else .value | @sh
          end
        end
      )
      EOF
      )"
      jq -r "$query" --argjson volumes "$VOLUMES" --argjson entrypoint "$ENTRYPOINT" --argjson cmd "$CMD" config.json
    '';
  in ''
    ${configure} > config-vars.sh
  '';
  buildPhase = let
    build = pkgs.writeShellScript "build.sh" ''
      set -eo pipefail
      . config-vars.sh
      mkdir rootfs
      tar -xf rootfs.tar -C rootfs

      if [[ -z "$user" ]]; then
        user=0
      fi

      user="''${user#[[:space:]]}"
      user="''${user%[[:space:]]}"

      if [[ "$user" != +([0-9]) ]]; then
        user="$(gawk -F : -v USER="$user" 'USER == $1 {printf "%s",$3; exit}' rootfs/etc/passwd)"
        defaultgid="$(gawk -F : -v USER="$user" 'USER == $1 {printf "%s",$4; exit}' rootfs/etc/passwd)"
      fi

      if [[ -z "$group" ]]; then
        if [[ -n "$defaultgid" ]] then
          group="$defaultgid"
        else
          group="$user"
        fi
      fi

      group="''${group#[[:space:]]}"
      group="''${group%[[:space:]]}"

      run() {
        bwrap \
        --new-session \
        --unshare-all \
        --clearenv \
        --uid "$user" --gid "$group" \
        --chdir "$cwd" \
        "''${envs[@]}" \
        --bind rootfs / \
        --dev /dev \
        --proc /proc \
        "''${volumes[@]}" \
        -- \
        "''${args[@]}"
      }

      if [[ -n "$STDIN" ]]; then
        cat "$STDIN" | run
      else
        run
      fi
    '';
  in ''
    runHook preBuild
    unshare --keep-caps -Ur bash ${build}
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    cd rootfs
    ${install}
    runHook postInstall
  '';
})
