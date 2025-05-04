{pkgs, lock, talosctl, third-party}: {
  schema = pkgs.stdenv.mkDerivation {
    pname = "talos-config-schema";
    version = lock.talos.version;
    src = talosctl.src;
    nativeBuildInputs = [ third-party.cue ];
    phases = ["unpackPhase" "buildPhase"];
    buildPhase = ''
      mkdir -p "$out"
      cue import jsonschema: --outfile "$out/schema.cue" -p config pkg/machinery/config/schemas/config.schema.json
    '';
  };
}
