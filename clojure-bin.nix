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
      clj-inject ${src}/deps.edn > $out/deps.edn
    '';
  };
  preppedSrc = stdenv.mkDerivation {
    name = "${name}-prepped";
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir $out
      cp -r ${src}/. $out
      rm $out/deps.edn
      cp ${depsFile}/deps.edn $out
    '';
  };

in mkCljBin {
  inherit name jdkRunner version;
  projectSrc = preppedSrc;
  main-ns = primaryNamespace;
  checkPhase = optionalString (checkPhase != null) checkPhase;
  lockfile = "${src}/deps-lock.json";
  # buildCommand = optionalString (buildCommand != null) buildCommand;
}
