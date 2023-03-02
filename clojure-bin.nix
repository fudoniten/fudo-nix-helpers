{ pkgs, mkCljBin, jdkRunner }:

with pkgs.lib;

{ name, primaryNamespace, src ? ./., version ? "0.1", checkPhase ? null, ... }:

mkCljBin {
  inherit name jdkRunner version;
  projectSrc = src;
  main-ns = primaryNamespace;
  checkPhase = mkIf (checkPhase != null) checkPhase;
  lockfile = toPath "${src}/deps-lock.json";
}
