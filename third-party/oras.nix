{pkgs, pkgs-unstable}: pkgs-unstable.oras.overrideAttrs (final: prev: {
  version = "1.3.0-beta.3";
  src = pkgs.fetchFromGitHub {
    inherit (prev.src) owner repo;
    rev = "v${final.version}";
    hash = "sha256-a+Xoi6uwnqmwwQ5kzC2fBYh/rMGUK37UsLpzu/5yHkE=";
  };
  vendorHash = "sha256-yqFUgBg5UN6FS7iJpCkOZixy549tI55H52NbQ/Fuw+s=";
})
