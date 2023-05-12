{ lib, pkgs, jdkRunner, mkCljBin, ... }:

with lib;
mkCljBin {
  inherit jdkRunner;
  name = "org.fudo/injector";
  version = "0.1";
  projectSrc = ./.;
  main-ns = "injector.cli";
  lockfile = "${src}/deps-lock.json";
}
