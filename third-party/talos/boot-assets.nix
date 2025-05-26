{pkgs, lib, nix, images, lock, extensions, overlays}: let
  hostArch = {
    "x86_64" = "amd64";
    "aarch64" = "arm64";
  }.${pkgs.hostPlatform.parsed.cpu.name};

  makeProfile = let
    extensions' = extensions;
  in {
    arch ? hostArch,
    overlay ? null,
    extensions ? [],
    platform ? "metal",
    secureboot ? { enabled = false; },
    customization ? null
  }: (if customization == null then {} else {
    inherit customization;
  }) // (if overlay == null then {} else {
    overlay = overlay // {
      image = let
        name = if overlay ? image then overlay.image else overlay.name;
      in if !(builtins.isString name) then throw "Custom overlays not supported yet"
      else {
        ociPath = (overlays hostArch).${name};
        imageRef = "localhost:${(overlays hostArch).${name}.imageRef}";
      };
    };
  }) // {
    inherit arch platform;
    secureboot = secureboot.enabled;
    version = lock.talos.version;
    input = (if overlay == null then {} else {
      overlayInstaller = let
          name = if overlay ? image then overlay.image else overlay.name;
      in if !(builtins.isString name) then throw "Custom overlays not supported yet"
      else {
        ociPath = (overlays arch).${name};
        imageRef = "localhost:${(overlays arch).${name}.imageRef}";
      };
    }) // {
      baseInstaller = let
        img = images.installer arch;
      in {
        ociPath = img;
        imageRef = "localhost:${img.imageRef}";
      };
      systemExtensions = builtins.map (ext: let
        image = if lib.attrsets.isDerivation ext then ext else (extensions' arch).${ext};
      in{
        ociPath = image;
        imageRef = "localhost:${image.imageRef}";
      }) extensions;
    };
  };
in {
  installer = profile: nix.oci.run {
    image = images.imager hostArch;
    cmd = ["-"];
    volumes = {
      "." = "/out";
      "/nix" = "/nix";
    };
    stdin = pkgs.writeText "profile" (builtins.toJSON (makeProfile profile // {
      output = {
        kind = "installer";
        outFormat = "raw";
      };
    }));
    extraNativeBuildInputs = with pkgs; [skopeo];
    install = ''
      readarray -t outFiles <<<"$(find . -type f -mindepth 1)"

      if [[ ''${#outFiles[@]} != 1 ]]; then
        echo "Expecting exactly one output file, but found ''${#outFiles[@]}" 1>&2
        exit 1
      fi

      export HOME="$TMPDIR"
      mkdir -p "$HOME/.config/containers/"
      echo '{"default":[{"type":"insecureAcceptAnything"}]}' > "$HOME/.config/containers/policy.json"
      skopeo copy "docker-archive:''${outFiles[0]}" "oci:$out"
    '';
  };
  rpi-image = profile: nix.oci.run {
    image = images.imager hostArch;
    cmd = ["-"];
    volumes = {
      "." = "/out";
      "/nix" = "/nix";
      "/dev" = "/dev";
    };
    stdin = pkgs.writeText "profile" (builtins.toJSON (makeProfile profile // {
      output = {
        kind = "image";
        imageOptions = {
          # Defaults from rpi overlay profile
          diskSize = 1306525696;
          diskFormat = "raw";
          bootloader = "grub";
        };
        outFormat = ".xz";
      };
    }));
    install = ''
      readarray -t outFiles <<<"$(find . -type f -mindepth 1)"

      if [[ ''${#outFiles[@]} != 1 ]]; then
        echo "Expecting exactly one output file, but found ''${#outFiles[@]}" 1>&2
        exit 1
      fi

      rm -rf "$out"
      cp "''${outFiles[0]}" "$out"
    '';
  };
  iso = profile: nix.oci.run {
    image = images.imager hostArch;
    cmd = ["-"];
    volumes = {
      "." = "/out";
      "/nix" = "/nix";
      "/dev" = "/dev";
    };
    stdin = pkgs.writeText "profile" (builtins.toJSON (makeProfile profile // {
      output = {
        kind = "iso";
      };
    }));
    install = ''
      readarray -t outFiles <<<"$(find . -type f -mindepth 1)"

      if [[ ''${#outFiles[@]} != 1 ]]; then
        echo "Expecting exactly one output file, but found ''${#outFiles[@]}" 1>&2
        exit 1
      fi

      cp "''${outFiles[0]}" "$out"
    '';
  };
}
