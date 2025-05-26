{pkgs}: {
  cache = deps: pkgs.linkFarm "cue-pkg-cache" (builtins.map (dep: {
    name = "mod/extract/${dep.module-name}@${dep.version}";
    path = dep;
  }) deps);
}
