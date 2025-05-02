{lib, images, nix, system}: let
  arch = {
    "x86_64-linux" = "amd64";
    "aarch64-linux" = "arm64";
  }.${system};
  lines = lib.strings.splitString "\n" (builtins.readFile "${nix.oci.unpack images.extensions}/image-digests");
  parseRef = str: let
    match = builtins.match "^(.*):(.*)@(.*)$" str;
  in if match == null then throw "Couldn't parse image ref: ${str}" else {
    image = builtins.elemAt match 0;
    tag = builtins.elemAt match 1;
    digest = builtins.elemAt match 2;
    inherit arch;
  };
  refs = (builtins.filter (line: line != "" && line != null) (builtins.map lib.strings.trim lines));
in builtins.listToAttrs (builtins.map (refStr: let ref = parseRef refStr; in {
  name = lib.strings.removePrefix "ghcr.io/siderolabs/" ref.image;
  value = nix.oci.pull ref;
}) refs)
