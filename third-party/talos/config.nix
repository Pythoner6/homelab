{pkgs, lock, talosctl, third-party}: {
  schema = pkgs.stdenv.mkDerivation (let
    module-name = "pythoner6.dev/third-party/talos/config";
  in {
    pname = "talos-config-schema";
    version = lock.talos.version;
    src = talosctl.src;
    nativeBuildInputs = [ third-party.cue ];
    phases = ["unpackPhase" "buildPhase"];
    buildPhase = ''
      mkdir -p "$out/cue.mod"

      cat <<EOF > "$out/cue.mod/module.cue"
      module: "${module-name}"
      language: {
        version: "v0.13.0"
      }
      source: {
        kind: "self"
      }
      EOF

      cue import jsonschema: --outfile "$out/config.schema.cue" -p config pkg/machinery/config/schemas/config.schema.json
    '';
    passthru = {
      inherit module-name;
    };
  });
}
