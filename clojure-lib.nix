{ mkCljLib, jdkRunner, cljInject, stdenv, lib }:

with lib;

{ name, src, version ? "0.1", buildCommand ? null, checkPhase ? null
, cljLibs ? { }, ... }:

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
  stageBuild = mkCljLib ({
    inherit jdkRunner version;
    name = "${name}-staging";
    projectSrc = preppedSrc;
    checkPhase = optionalString (checkPhase != null) checkPhase;
    lockfile = "${src}/deps-lock.json";
  } // (optionalAttrs (buildCommand != null) { inherit buildCommand; }));

in stdenv.mkDerivation {
  name = "${name}-${version}.jar";
  inherit version;
  phases = [ "installPhase" ];
  installPhase = "cp ${stageBuild}/*.jar $out";
}
