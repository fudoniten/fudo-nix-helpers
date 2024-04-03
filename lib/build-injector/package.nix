{ lib, pkgs, jdkRunner, mkCljBin, ... }:

with lib;
let projectSrc = ./.;
in mkCljBin {
  inherit jdkRunner projectSrc;
  name = "org.fudo/build-injector";
  version = "0.1";
  main-ns = "build-injector.cli";
  lockfile = "${projectSrc}/deps-lock.json";
}