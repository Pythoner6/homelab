{pkgs, images, system, lock, extensions}: let
  runImager = {name,profile}: pkgs.stdenvNoCC.mkDerivation {
    name = "runImager2";
    src = images.imager;
    PROFILE = profile;
    nativeBuildInputs = with pkgs; [bubblewrap umoci jq util-linux];
    unpackPhase = ''
      runHook preUnpack
      unshare -r umoci unpack --image "$src:${images.imager.imageRef}" .
      runHook postUnpack
    '';
    buildPhase = ''
      runHook preBuild
      cwd="$(cat config.json | jq -r .process.cwd)"
      uid="$(cat config.json | jq -r .process.user.uid)"
      gid="$(cat config.json | jq -r .process.user.gid)"
      declare -a args="($(cat config.json | jq -r '.process.args | @sh'))"
      declare -a envs="($(cat config.json | jq -r '.process.env | map(match("([^=]*)=(.*)").captures | ["--setenv"]+map(.string)) | flatten | @sh'))"
      cat "$PROFILE" | bwrap \
        --new-session \
        --clearenv --cap-add ALL \
        --uid "$uid" --gid "$gid" \
        --chdir "$cwd" \
        "''${envs[@]}" \
        --unshare-all \
        --bind rootfs / \
        --ro-bind /nix /nix \
        --dev /dev \
        "''${args[@]}" \
        -
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall

      readarray -t outFiles <<<"$(find ./rootfs/out -type f -mindepth 1)"

      if [[ ''${#outFiles[@]} != 1 ]]; then
        echo "Expecting exactly one output file, but found ''${#outFiles[@]}" 1>&2
        exit 1
      fi

      cp "''${outFiles[0]}" "$out"

      runHook postInstall
    '';
  };
  # TODO
  arch = {
    "x86_64" = "amd64";
    "aarch64" = "arm64";
  }.${pkgs.hostPlatform.parsed.cpu.name};
in {
  # TODO: parameterize this
  installer = runImager {
    name = "installer";
    profile = pkgs.writeText "profile" (builtins.toJSON {
      inherit arch;
      platform = "metal";
      secureboot = false;
      version = lock.talos.version;
      input = {
        baseInstaller = {
          ociPath = images.installer;
          imageRef = images.installer.imageRef;
        };
        systemExtensions = builtins.map (ext: {ociPath = extensions.${ext}; imageRef = extensions.${ext}.imageRef;}) ["kata-containers"];
      };
      output = {
        kind = "installer";
        outFormat = "raw";
      };
    });
  };
}
