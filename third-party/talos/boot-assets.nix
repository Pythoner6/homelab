{pkgs, images, system, lock, extensions}: let
  runImager = {name, profile}: pkgs.vmTools.runInLinuxVM (pkgs.stdenvNoCC.mkDerivation {
    inherit name;
    dontUnpack = true;
    nativeBuildInputs = with pkgs; [
      podman util-linux yq-go jq
    ];
    memSize = 4096;
    src = profile;
    IMAGER = images.imager;
    configurePhase = ''
      runHook preConfigure
      export HOME="$TMPDIR/home"
      mkdir -p $HOME/.config/containers/
      cat <<EOF > $HOME/.config/containers/policy.json
      {
        "default": [{"type": "reject"}],
        "transports": {"oci": {"": [{"type": "insecureAcceptAnything"}]}}
      }
      EOF

      mkdir -p /sys/fs/cgroup
      mount -t cgroup2 none /sys/fs/cgroup
      tmpOut="$TMPDIR/out"
      mkdir "$tmpOut"
      runHook postConfiugre
    '';
    buildPhase = ''
      runHook preBuild
      cat "$src" | podman run -i -v $tmpOut:/out -v /nix/store:/nix/store --rm "oci:$IMAGER" -
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall

      readarray -t outFiles <<<"$(find "$tmpOut" -type f -mindepth 1)"

      if [[ ''${#outFiles[@]} != 1 ]]; then
        echo "Expecting exactly one output file, but found ''${#outFiles[@]}" 1>&2
        exit 1
      fi

      rm -rf "$out"
      cp "''${outFiles[0]}" "$out"

      runHook postInstall
    '';
  });
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
