# fudo-nix-helpers flake
#
# This flake provides helpers for building container images with Nix, and
# re-exports the Clojure build helpers from nix-clj-helpers so existing
# consumers keep working unchanged.
#
# Main exports (accessible via legacyPackages, or lib.forSystem):
#   - makeContainer: Create a Docker-compatible container image
#   - deployContainers: Push containers to a registry
#   - makeTerminalContainer: Create an SSH-accessible terminal container
#   - deployTerminalContainer: Push terminal containers to a registry
#   - mkClojureLib, mkClojureBin, mkClojureTests, updateClojureDeps, ...:
#     re-exported from nix-clj-helpers (new projects can use it directly)
#
# Usage in your flake.nix:
#   inherit (helpers.legacyPackages."${system}") makeContainer deployContainers;
#
# Note: Use 'legacyPackages' instead of 'packages' to access builder functions.
# This is necessary because Nix flake check requires 'packages' to contain only
# derivations, not functions. This is the standard pattern used by nixpkgs.
#
# See README.md for detailed usage instructions.

{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";

    # Clojure build helpers, re-exported below for existing consumers
    nix-clj-helpers = {
      url = "github:fudoniten/nix-clj-helpers";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };

    # Utility for generating outputs for multiple systems
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nix-clj-helpers, utils, ... }:
    let
      # Build the full set of helpers for one system. Both legacyPackages and
      # lib.forSystem are views onto this, so there is one place to change.
      mkHelpers = system:
        let
          pkgs = import nixpkgs { inherit system; };

          containerHelpers = pkgs.callPackage ./container-helpers.nix { };

          # SSH-accessible terminal hosts
          terminalContainerHelpers =
            pkgs.callPackage ./terminal-container-helpers.nix { };

        in nix-clj-helpers.lib.forSystem system // {
          # --------------------------------------------------------------------
          # Container Helpers
          # --------------------------------------------------------------------

          inherit (containerHelpers) makeContainer deployContainers;

          # Build SSH-accessible terminal containers for agents/remote development
          # See terminal-container-helpers.nix for parameter documentation
          inherit (terminalContainerHelpers)
            makeTerminalContainer deployTerminalContainer;
        };

    in utils.lib.eachDefaultSystem (system: {
      # legacyPackages is not validated by 'nix flake check', allowing functions
      # This is the standard way to expose both derivations and functions
      legacyPackages = mkHelpers system;

      # Re-exported from nix-clj-helpers so `nix run` against this flake keeps
      # working (update-clojure-deps, update-git-deps, ...)
      packages = nix-clj-helpers.packages."${system}";
    }) // {
      # Library functions (not system-specific or per-system helpers)
      lib = {
        # Package a Ruby script with proper shebang and runtime environment
        writeRubyApplication = import ./write-ruby-application.nix;

        # Helper to get system-specific functions (builders, dependency injection, containers, etc.)
        # Usage: (lib.forSystem "x86_64-linux").mkClojureLib { ... }
        #        (lib.forSystem "x86_64-linux").makeContainer { ... }
        forSystem = mkHelpers;
      };
    };
}
