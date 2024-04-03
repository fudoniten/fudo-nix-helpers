{ mkCljLib, jdkRunner, cljInject, cljBuildInject, stdenv, lib }:

with lib;

{ name, src, version ? "0.1", buildCommand ? null, checkPhase ? null
, cljLibs ? { }, ... }:

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
  stageBuild = mkCljLib ({
    inherit jdkRunner version;
    name = "${name}-staging";
    projectSrc = preppedSrc;
    checkPhase = optionalString (checkPhase != null) checkPhase;
    lockfile = "${src}/deps-lock.json";
  } // (optionalAttrs (!isNull buildCommand) { inherit buildCommand; })
    // (optionalAttrs (isNull buildCommand) {
      buildCommand = let
        cmd = concatStringsSep " " [
          "clojure -T:build"
          "uberjar"
          ":name"
          name
          ":target ./target"
          ":verbose true"
          ":version"
          version
          ":clj-src"
          "${preppedSrc}"
        ];
      in ''
        echo ${cmd}
        ${cmd}
      '';
    }));

in stdenv.mkDerivation {
  name = "${name}-${version}.jar";
  inherit version;
  phases = [ "installPhase" ];
  installPhase = "cp ${stageBuild}/*.jar $out";
}
