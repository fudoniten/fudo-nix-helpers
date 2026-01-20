{ lib, mkCljBin, jdkRunner, clojureHelpers }:

with lib;

{ name, primaryNamespace, src, version ? "0.1", checkPhase ? null
, buildCommand ? null, cljLibs ? { }, ... }:

let
  preppedSrc = clojureHelpers.mkPreparedClojureSrc {
    inherit name src cljLibs;
  };

in mkCljBin ({
  inherit name jdkRunner version;
  projectSrc = preppedSrc;
  main-ns = primaryNamespace;
  checkPhase = optionalString (checkPhase != null) checkPhase;
  lockfile = "deps-lock.json";
} // (optionalAttrs (buildCommand != null) { inherit buildCommand; }))
