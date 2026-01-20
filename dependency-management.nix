# Dependency management tools for Clojure projects
#
# This module provides tools for updating and managing Clojure dependencies,
# particularly for regenerating deps-lock.json files with injected dependencies.

{ pkgs, system, cljInject, cljBuildInject, cljBuildToolsVersion, deps-lock }:

{
  # --------------------------------------------------------------------
  # Dependency Management
  # --------------------------------------------------------------------

  # Helper script to regenerate deps-lock.json with all injections applied.
  # Usage: nix run .#updateClojureDeps
  #        nix run .#updateClojureDeps -- path/to/deps.edn
  updateClojureDeps = pkgs.writeShellApplication {
      name = "update-deps.sh";
      runtimeInputs = [
        (cljInject {})
        (cljBuildInject "build" {
          "io.github.clojure/tools.build" = cljBuildToolsVersion;
        })
        deps-lock
      ];
      text = ''
        if [ $# -eq 0 ]; then
          DEPS="$(pwd)/deps.edn"
        elif [ $# -eq 1 ]; then
          DEPS="$1"
        else
          echo "usage: $0 [deps-file]"
          exit 1
        fi
        SRC=$(pwd)
        TMP=$(mktemp -d)
        # First pass: inject local dependency overrides
        clj-inject "$DEPS" > "$TMP/deps-prebuild.edn"
        # Second pass: inject build alias configuration
        clj-build-inject "$TMP/deps-prebuild.edn" > "$TMP/deps.edn"
        echo "DEPS.EDN:"
        cat "$TMP/deps.edn"
        cd "$TMP"
        # Generate the lockfile
        deps-lock
        mv "$TMP/deps-lock.json" "$SRC/deps-lock.json"
      '';
    };
}
