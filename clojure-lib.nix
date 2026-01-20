{ mkCljLib, jdkRunner, clojureHelpers, stdenv, lib }:

with lib;

{ name, src, version ? "0.1", clojure-src-dirs ? [ "src" ], java-src-dirs ? [ ]
, buildCommand ? null, checkPhase ? null, cljLibs ? { }, ... }:

let
  preppedSrc = clojureHelpers.mkPreparedClojureSrc {
    inherit name src cljLibs;
  };

  stageBuild = mkCljLib ({
    inherit jdkRunner version;
    name = "${name}-staging";
    projectSrc = preppedSrc;
    checkPhase = optionalString (checkPhase != null) checkPhase;
    lockfile = "deps-lock.json";
  } // (optionalAttrs (buildCommand != null) { inherit buildCommand; })
    // (optionalAttrs (buildCommand == null) {
      buildCommand = concatStringsSep " " ([
        "clojure -T:build"
        "uberjar"
        ":name"
        name
        ":target ./target"
        ":verbose true"
        ":version"
        version
        ":clj-src"
        (concatStringsSep "," clojure-src-dirs)
      ] ++ (optionals (java-src-dirs != [ ]) [
        ":java-src"
        (concatStringsSep "," java-src-dirs)
      ]));
    }));

in stdenv.mkDerivation {
  name = "${name}-${version}.jar";
  inherit version;
  phases = [ "installPhase" ];
  src = stageBuild;
  installPhase = "cp $src/*.jar $out";
}
