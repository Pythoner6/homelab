{lib, pkgs, images, nix, system}: arch: let
  parseRef = str: digest: let
    match = builtins.match "^(.*):(.*)$" str;
  in if match == null then throw "Couldn't parse image ref: ${str}" else {
    image = builtins.elemAt match 0;
    tag = builtins.elemAt match 1;
    inherit digest arch;
  };
in builtins.listToAttrs (
  map
  ({name,image,digest}: {inherit name;value=nix.oci.pull (parseRef image digest);})
  (lib.importJSON (pkgs.stdenvNoCC.mkDerivation {
    name = "get-overlays";
    nativeBuildInputs = with pkgs; [yq-go];
    phases=["installPhase"];
    installPhase = ''
      yq ${nix.oci.unpack (images.overlays arch)}/overlays.yaml -o json > "$out"
    '';
  })).overlays
)
