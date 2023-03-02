{ pkgs, mkCljLib, jdkRunner }:

with pkgs.lib;

{ name, primaryNamespace, src, version ? "0.1", checkPhase ? null, ... }:

mkCljLib {
  inherit name jdkRunner version;
  projectSrc = src;
  main-ns = primaryNamespace;
  checkPhase = optionalString (checkPhase != null) checkPhase;
  lockfile = "${src}/deps-lock.json";
}
