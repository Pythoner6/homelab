# === nix.oci.pull ===
{pkgs, lib}:  let
  orasFetch = type: {image, tag ? null, digest}: let
    fetchType = if type == "blob" || type == "manifest" then type else throw "orasFetch type must be blob or manifest, got ${type}";
    digestParts = lib.strings.splitString ":" digest;
    algo = builtins.elemAt digestParts 0;
    hash = builtins.elemAt digestParts 1;
  in pkgs.stdenvNoCC.mkDerivation {
    name = builtins.replaceStrings ["/" ":"] ["-" "-"] "${image}-${fetchType}-${digest}";
    nativeBuildInputs = with pkgs; [
      oras
    ];
    phases = ["installPhase"];
    IMAGE_REF = "${image}${if tag != null then ":${tag}" else ""}@${digest}";
    installPhase = ''
      runHook preInstall
      oras ${fetchType} fetch "$IMAGE_REF" --output "$out"
      runHook postInstall
    '';
    outputHashMode = "flat";
    outputHashAlgo = algo;
    outputHash = hash;
  };

  fetchImage = {image, digest, arch, tag, descriptor ? null}: let
    manifestDrv = orasFetch "manifest" {inherit image digest tag;};
    manifest = lib.importJSON manifestDrv;
    # If we get an index, pick a manifest from it and recurse
    desc = builtins.head (builtins.filter (m: m.platform.architecture == arch) manifest.manifests);
    fetchedImage = fetchImage {
      inherit image arch tag;
      digest = desc.digest;
      descriptor = desc;
    };
    # If we got a manifest, fetch it's config and all the layer blobs
    ociLayoutPath = digest: "blobs/${lib.strings.replaceStrings [":"] ["/"] digest}";
    linkFarm = (pkgs.linkFarm "${image}-image-${digest}" (
      [
        { name = ociLayoutPath digest; path = manifestDrv; }
        { name = ociLayoutPath manifest.config.digest; path = orasFetch "blob" {inherit image; digest = manifest.config.digest; }; }
        { name = "oci-layout"; path = pkgs.writeText "oci-layout" ''{"imageLayoutVersion":"1.0.0"}''; }
        {
          name = "index.json";
          path = pkgs.stdenvNoCC.mkDerivation {
            name = "${image}-index-${digest}";
            phases = ["installPhase"];
            nativeBuildInputs = with pkgs; [jq];
            DESC = builtins.toJSON (lib.attrsets.recursiveUpdate descriptor {annotations."org.opencontainers.image.ref.name" = tag;});
            installPhase = ''
              runHook preInstall
              jq -n -c --sort-keys --argjson desc "$DESC" "$(
              cat <<'EOF'
              {
                schemaVersion: 2,
                manifests: [$desc],
              }
              EOF
              )" > "$out"
              runHook postInstall
            '';
          };
        }
      ] ++
      (builtins.map (l: {name = ociLayoutPath l.digest; path = orasFetch "blob" {inherit image; digest = l.digest;};}) manifest.layers)
    ));
  in {
    "application/vnd.oci.image.index.v1+json" = fetchedImage;
    "application/vnd.docker.distribution.manifest.list.v2+json" = fetchedImage;
    "application/vnd.oci.image.manifest.v1+json" = linkFarm;
    "application/vnd.docker.distribution.manifest.v2+json" = linkFarm;
  }.${manifest.mediaType} // {imageRef = tag;};
in args@{image,digest,arch,tag}: fetchImage args
