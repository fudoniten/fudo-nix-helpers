{ lib, mkCljBin, jdkRunner, cljInject, cljBuildInject, stdenv }:

with lib;

{ name, primaryNamespace, src, version ? "0.1", checkPhase ? null
, buildCommand ? null, cljLibs ? { }, ... }:

let
  depsFile = stdenv.mkDerivation {
    name = "${name}-deps.edn";
    buildInputs = [
      (cljInject cljLibs)
      (cljBuildInject "build" { "io.github.clojure/tools.build" = "0.10.0"; })
    ];
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out
      clj-inject ${src}/deps.edn > pre-deps.edn
      clj-build-inject pre-deps.edn > $out/deps.edn
      cat $out/deps.edn
    '';
  };
  preppedSrc = let buildClj = ./lib/build.clj;
  in stdenv.mkDerivation {
    name = "${name}-prepped";
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir $out
      cp -r ${src}/. $out
      rm $out/deps.edn
      cp ${depsFile}/deps.edn $out
      cp ${buildClj} $out/build.clj
    '';
  };

in mkCljBin ({
  inherit name jdkRunner version;
  projectSrc = preppedSrc;
  main-ns = primaryNamespace;
  checkPhase = optionalString (checkPhase != null) checkPhase;
  lockfile = "${src}/deps-lock.json";
} // (optionalAttrs (buildCommand != null) { inherit buildCommand; }))
