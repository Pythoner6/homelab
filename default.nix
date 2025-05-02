{pkgs, lib, makePackageSet, splicePackages, system}: let
  doImport = path: scope: let
    imported = scope.callPackage path {};
    type = builtins.typeOf imported;
  in if type == "lambda" then {__functor = self: imported;} else imported;

  recursiveImport = name: path: self: let
    entries = builtins.readDir path;
    hasDefault = (entries."default.nix" or null) == "regular";
    isRoot = entries ? "flake.nix";
  in if hasDefault && !isRoot
  then doImport "${path}/default.nix" (builtins.trace self self)
  else makePackageSet name self.newScope (new: (lib.attrsets.concatMapAttrs (entry: type: let
    directory = type == "directory";
    include = directory || (
      type == "regular" &&
      (lib.strings.hasSuffix ".nix" entry) &&
      !isRoot
    );
    attrName = if directory then entry else lib.strings.removeSuffix ".nix" entry;
  in if !include then {} else {
    ${attrName} = if directory then (
      recursiveImport entry "${path}/${entry}" new
    ) else (
      doImport "${path}/${entry}" new
    );
  })) entries);

  baseScope = {
    newScope = extra: lib.callPackageWith ({
      inherit splicePackages pkgs lib system;
      lock = lib.importTOML ./lock.toml;
    } // extra);
  };
in recursiveImport "lab" ./. baseScope
