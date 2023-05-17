{ lib, mkCljBin, jdkRunner, cljInject, stdenv }:

with lib;

{ name, primaryNamespace, src, version ? "0.1", checkPhase ? null
, buildCommand ? null, cljLibs ? { }, ... }:

let
  depsFile = stdenv.mkDerivation {
    name = "${name}-deps.edn";
    buildInputs = [ (cljInject cljLibs) ];
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out
      clj-inject ${src}/deps.edn > $out
    '';
  };

in mkCljBin {
  inherit name jdkRunner version;
  projectSrc = src;
  main-ns = primaryNamespace;
  checkPhase = optionalString (checkPhase != null) checkPhase;
  lockfile = "${depsFile}";
  buildCommand = optionalString (buildCommand != null) buildCommand;
}
