# fudo-nix-helpers flake
#
# This flake provides helpers for building Clojure projects and container images
# with Nix. The key feature is dependency injection that allows using local
# Clojure libraries without uploading them to Maven.
#
# Main exports (accessible via legacyPackages, or lib.forSystem):
#   - mkClojureLib: Build a Clojure library JAR
#   - mkClojureBin: Build a runnable Clojure CLI application
#   - mkClojureTests: Build and run Clojure tests
#   - makeContainer: Create a Docker-compatible container image
#   - deployContainers: Push containers to a registry
#   - makeTerminalContainer: Create an SSH-accessible terminal container
#   - deployTerminalContainer: Push terminal containers to a registry
#   - updateClojureDeps: Regenerate deps-lock.json with injected dependencies
#   - cljInject, cljBuildInject: Dependency injection functions
#
# Usage in your flake.nix:
#   inherit (helpers.legacyPackages."${system}") mkClojureLib mkClojureBin;
#
# Note: Use 'legacyPackages' instead of 'packages' to access builder functions.
# This is necessary because Nix flake check requires 'packages' to contain only
# derivations, not functions. This is the standard pattern used by nixpkgs.
#
# See README.md for detailed usage instructions.

{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";

    # clj-nix provides the core Clojure packaging functionality
    clj-nix = {
      url = "github:jlesquembre/clj-nix/0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Utility for generating outputs for multiple systems
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, clj-nix, utils, ... }:
    let
      # Build the full set of helpers for one system. Both legacyPackages and
      # lib.forSystem are views onto this, so there is one place to change.
      mkHelpers = system:
        let
          pkgs = import nixpkgs { inherit system; };

          clj-pkgs = clj-nix.packages."${system}";

          # Default JDK for building and running Clojure projects (headless for
          # a smaller closure). Builders accept `jdk` to override per project.
          defaultJdk = pkgs.jdk25_headless;

          # Version of tools.build injected into all Clojure projects. This is
          # baked into every consumer's deps-lock.json via updateClojureDeps,
          # so bumping it means every consumer must regenerate its lockfile.
          cljBuildToolsVersion = "0.10.6";

          # Dependency injection tools (Babashka-based, no JVM needed)
          dependencyInjection = pkgs.callPackage ./dependency-injection.nix { };

          containerHelpers = pkgs.callPackage ./container-helpers.nix { };

          # SSH-accessible terminal hosts
          terminalContainerHelpers =
            pkgs.callPackage ./terminal-container-helpers.nix { };

          dependencyManagement = pkgs.callPackage ./dependency-management.nix {
            inherit system cljBuildToolsVersion;
            inherit (dependencyInjection) cljInject cljBuildInject;
            deps-lock = clj-pkgs.deps-lock;
          };

          # Shared utilities for preparing Clojure sources with injected deps
          clojureHelpers = pkgs.callPackage ./clojure-helpers.nix {
            inherit cljBuildToolsVersion;
            inherit (dependencyInjection) cljInject cljBuildInject;
          };

        in {
          # --------------------------------------------------------------------
          # Clojure Build Helpers
          # --------------------------------------------------------------------

          # Build a Clojure library JAR file
          # See clojure-lib.nix for parameter documentation
          mkClojureLib = pkgs.callPackage ./clojure-lib.nix {
            inherit (clj-pkgs) mkCljLib;
            inherit clojureHelpers defaultJdk;
          };

          # Build a runnable Clojure CLI application (uberjar)
          # See clojure-bin.nix for parameter documentation
          mkClojureBin = pkgs.callPackage ./clojure-bin.nix {
            inherit (clj-pkgs) mkCljBin;
            inherit clojureHelpers defaultJdk;
          };

          # Build and run Clojure tests
          # See clojure-tests.nix for parameter documentation
          mkClojureTests = pkgs.callPackage ./clojure-tests.nix {
            inherit (clj-pkgs) mkCljLib;
            inherit clojureHelpers defaultJdk;
          };

          # --------------------------------------------------------------------
          # Dependency Management
          # --------------------------------------------------------------------

          # Function to create a script for updating deps-lock.json
          # Consumers should call this with their deps: (updateClojureDeps {})
          inherit (dependencyManagement) updateClojureDeps;

          # Pre-instantiated version of updateClojureDeps for direct usage
          # Usage: nix run .#update-clojure-deps
          #        nix run .#update-clojure-deps -- path/to/deps.edn
          update-clojure-deps = dependencyManagement.updateClojureDeps { };

          # Update deps with test alias included (locks test dependencies too)
          # Usage: nix run .#update-clojure-deps-with-tests
          update-clojure-deps-with-tests =
            dependencyManagement.updateClojureDeps { aliases = [ "test" ]; };

          # Synchronize Git dependencies between deps.edn, flake.nix, and lock files
          # Usage: nix run .#update-git-deps
          #        nix run .#update-git-deps -- --dry-run
          #        nix run .#update-git-deps -- --override owner/repo=commit-sha
          inherit (dependencyManagement)
            update-git-deps update-git-deps-no-locks updateGitDepsBin;

          # --------------------------------------------------------------------
          # Dependency Injection Tools
          # --------------------------------------------------------------------

          inherit (dependencyInjection)
            cljInjectBin cljInject cljBuildInjectBin cljBuildInject;

          # --------------------------------------------------------------------
          # Container Helpers
          # --------------------------------------------------------------------

          inherit (containerHelpers) makeContainer deployContainers;

          # Build SSH-accessible terminal containers for agents/remote development
          # See terminal-container-helpers.nix for parameter documentation
          inherit (terminalContainerHelpers)
            makeTerminalContainer deployTerminalContainer;
        };

    in utils.lib.eachDefaultSystem (system:
      let helpers = mkHelpers system;
      in {
        # legacyPackages is not validated by 'nix flake check', allowing functions
        # This is the standard way to expose both derivations and functions
        legacyPackages = helpers;

        # packages contains only actual derivations (for 'nix flake check')
        packages = {
          inherit (helpers)
            update-clojure-deps update-clojure-deps-with-tests cljInjectBin
            cljBuildInjectBin update-git-deps update-git-deps-no-locks
            updateGitDepsBin;
        };
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
