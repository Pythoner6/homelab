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

  fetchImage = {image, digest, arch, tag ? null}: let
    manifestDrv = orasFetch "manifest" {inherit image digest tag;};
    manifest = lib.importJSON manifestDrv;
    # If we get an index, pick a manifest from it and recurse
    desc = builtins.head (builtins.filter (m: m.platform.architecture == arch) manifest.manifests);
    fetchedImage = fetchImage {inherit image arch; digest = desc.digest;};
    # If we got a manifest, fetch it's config and all the layer blobs
    config = orasFetch "blob" { inherit image; digest = manifest.config.digest; };
    configParsed = lib.importJSON config;
    linkFarm = (pkgs.linkFarm "${image}-image-${digest}" (
      [
        { name = "manifest.json"; path = manifestDrv; }
        { name = builtins.elemAt (lib.strings.splitString ":" manifest.config.digest) 1; path = orasFetch "blob" {inherit image; digest = manifest.config.digest; }; }
        { name = "version"; path = pkgs.writeText "version" ''
          Directory Transport Version: 1.1
        ''; }
      ] ++
      (builtins.map (l: {name = builtins.elemAt (lib.strings.splitString ":" l.digest) 1; path = orasFetch "blob" {inherit image; digest = l.digest;};}) manifest.layers)
    )) // {imageConfig = configParsed;};
  in {
    "application/vnd.oci.image.index.v1+json" = fetchedImage;
    "application/vnd.docker.distribution.manifest.list.v2+json" = fetchedImage;
    "application/vnd.oci.image.manifest.v1+json" = linkFarm;
    "application/vnd.docker.distribution.manifest.v2+json" = linkFarm;
  }.${manifest.mediaType};
in args@{image, tag, digest, arch}: let
  imageDrv = fetchImage args;
  platform = (
    if imageDrv.imageConfig ? os then {os = imageDrv.imageConfig.os;} else {}
  ) // (
    if imageDrv.imageConfig ? architecture then {architecture = imageDrv.imageConfig.architecture;} else {}
  );
# TODO: could probably build the oci layout directly
# instead of using the dir: transport and copying with skopeo?
in pkgs.stdenvNoCC.mkDerivation {
  name = builtins.replaceStrings ["/" ":"] ["-" "-"] "${image}-${digest}-${arch}";
  src = imageDrv;
  phases = ["buildPhase"];
  IMAGE_REF = "${image}:${tag}";
  PLATFORM = builtins.toJSON platform;
  nativeBuildInputs = with pkgs; [
    skopeo moreutils jq
  ];
  buildPhase = ''
    runHook preBuild
    skopeo copy --insecure-policy "dir:$src" "oci:$out:$IMAGE_REF"
    jq -c --argjson platform "$PLATFORM" '.manifests[0].platform = $platform' "$out/index.json" | sponge "$out/index.json"
    runHook postBuild
  '';
  passthru = {
    imageRef = "${image}:${tag}";
  };
}
