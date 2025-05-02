{pkgs}: pkgs.cue.overrideAttrs (final: prev: {
  version = "0.13.0-alpha.4";
  src = pkgs.fetchFromGitHub {
    inherit (prev.src) owner repo;
    rev = "v${final.version}";
    hash = "sha256-bW64EjmtuL6n88FZ8yRSxTA5o+YprpDnBBucedWwfb4=";
  };
  vendorHash = "sha256-JXLQ6o9bdJphGXgP1PFtf46u/xtbRX8EtDVDFIyO2A0=";
  ldflags = map (flag:
    # This flag controls the version that cue prints out with `cue version`
    if (builtins.match "^-X cuelang.org/go/cmd/cue/cmd.version=.*$" flag) != null
    then "-X cuelang.org/go/cmd/cue/cmd.version=v${final.version}"
    else flag
  ) prev.ldflags;
})
