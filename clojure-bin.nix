{ pkgs, mkCljBin, jdkRunner, cljInject }:

with pkgs.lib;

{ name, primaryNamespace, src, version ? "0.1", checkPhase ? null
, buildCommand ? null, cljLibs ? { }, ... }:

let
  depsFile = pkgs.stdenv.mkDerivation {
    name = "${name}-deps.edn";
    buildInputs = [ (cljInject cljLibs) ];
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out
      clj-inject ${src}/deps.edn > $out/deps.edn
    '';
  };
  preppedSrc = pkgs.stdenv.mkDerivation {
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
  lockfile = "${preppedSrc}/deps-lock.json";
  buildCommand = optionalString (buildCommand != null) buildCommand;
}
