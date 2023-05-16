{ pkgs, mkCljLib, jdkRunner }:

with pkgs.lib;

{ name, src, version ? "0.1", buildCommand ? null, checkPhase ? null, injector
, ... }:

let
  depsFile = pkgs.stdenv.mkDerivation {
    name = "${name}-deps.edn";
    buildInputs = [ injector ];
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

in mkCljLib {
  inherit name jdkRunner version;
  projectSrc = preppedSrc;
  checkPhase = optionalString (checkPhase != null) checkPhase;
  lockfile = "${preppedSrc}/deps-lock.json";
  buildCommand = optionalString (buildCommand != null) buildCommand;
}
