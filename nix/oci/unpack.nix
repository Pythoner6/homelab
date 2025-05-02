{pkgs, drvName}: oci: pkgs.stdenvNoCC.mkDerivation {
  name = "${drvName oci}-unpack";
  nativeBuildInputs = with pkgs; [ umoci ];
  src = "${oci}:${oci.imageRef}";
  phases = ["unpackPhase"];
  unpackPhase = ''
    runHook preUnpack
    umoci raw unpack --rootless --image "$src" "$out"
    runHook postUnpack
  '';
}
