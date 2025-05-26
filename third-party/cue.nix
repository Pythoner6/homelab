{pkgs}: pkgs.cue.overrideAttrs (final: prev: {
  version = "0.13.0";
  src = pkgs.fetchFromGitHub {
    inherit (prev.src) owner repo;
    rev = "v${final.version}";
    hash = "sha256-RvdjZ3wSc3IhQvYJL989x33qOtVZ4paoQTLFzWF9xj0=";
  };
  vendorHash = "sha256-J9Ox9Yt64PmL2AE+GRdWDHlBtpfmDtxgUbEPaka5JSo=";
  ldflags = map (flag:
    # This flag controls the version that cue prints out with `cue version`
    if (builtins.match "^-X cuelang.org/go/cmd/cue/cmd.version=.*$" flag) != null
    then "-X cuelang.org/go/cmd/cue/cmd.version=v${final.version}"
    else flag
  ) prev.ldflags;
})
