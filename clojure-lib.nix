{ pkgs, mkCljLib, jdkRunner }:

with pkgs.lib;

{ name, src, version ? "0.1", buildCommand ? null, checkPhase ? null, ... }:

mkCljLib {
  inherit name jdkRunner version;
  projectSrc = src;
  checkPhase = optionalString (checkPhase != null) checkPhase;
  lockfile = "${src}/deps-lock.json";
  buildCommand = optionalString (buildCommand != null) buildCommand;
}
