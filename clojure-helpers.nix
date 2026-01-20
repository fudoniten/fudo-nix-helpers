# Shared helpers for Clojure library and binary builders
{ lib, stdenv, cljInject, cljBuildInject, cljBuildToolsVersion }:

with lib;

{
  # Prepare a Clojure project source with injected dependencies and build configuration.
  # Returns a derivation containing the modified source tree.
  mkPreparedClojureSrc = { name, src, cljLibs ? { } }:
    let
      cljLibsStringified = mapAttrs (_: path: "${path}") cljLibs;

      # Build the modified deps.edn with injected local dependencies
      depsFile = stdenv.mkDerivation {
        name = "${name}-deps.edn";
        buildInputs = [
          (cljInject cljLibsStringified)
          (cljBuildInject "build" {
            "io.github.clojure/tools.build" = cljBuildToolsVersion;
          })
        ];
        phases = [ "installPhase" ];
        installPhase = ''
          mkdir -p $out
          clj-inject ${src}/deps.edn > pre-deps.edn
          clj-build-inject pre-deps.edn > $out/deps.edn
          cat $out/deps.edn
        '';
      };

      # Use project's build.clj if it exists, otherwise use the default
      defaultBuildClj = ./lib/build.clj;
      projectBuildClj = "${src}/build.clj";

    in stdenv.mkDerivation {
      name = "${name}-prepped";
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir $out
        cp -r ${src}/. $out
        rm $out/deps.edn
        cp ${depsFile}/deps.edn $out

        # Use project's build.clj if present, otherwise use default
        if [ -f "${projectBuildClj}" ]; then
          echo "Using project's build.clj"
        else
          echo "Using default build.clj"
          cp ${defaultBuildClj} $out/build.clj
        fi
      '';
    };
}
