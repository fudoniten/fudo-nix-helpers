# fudo-nix-helpers flake
#
# This flake provides helpers for building Clojure projects and container images
# with Nix. The key feature is dependency injection that allows using local
# Clojure libraries without uploading them to Maven.
#
# Main exports (accessible via legacyPackages):
#   - mkClojureLib: Build a Clojure library JAR
#   - mkClojureBin: Build a runnable Clojure CLI application
#   - mkClojureTests: Build and run Clojure tests
#   - makeContainer: Create a Docker-compatible container image
#   - deployContainers: Push containers to a registry
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
    nixpkgs.url = "nixpkgs/nixos-25.05";

    # clj-nix provides the core Clojure packaging functionality
    clj-nix = {
      url = "github:jlesquembre/clj-nix/0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Alternative Clojure-to-Nix converter (kept for compatibility)
    clj2nix.url = "github:hlolli/clj2nix";

    # Utility for generating outputs for multiple systems
    utils.url = "github:numtide/flake-utils";

    # Container image building (alternative to dockerTools)
    nix2container.url = "github:nlewo/nix2container";
  };

  outputs = { self, nixpkgs, clj-nix, utils, nix2container, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        clj-pkgs = clj-nix.packages."${system}";

        # JDK used for running Clojure builds (headless for smaller closure)
        default-jdk = pkgs.jdk17_headless;

        # Version of tools.build injected into all Clojure projects
        cljBuildToolsVersion = "0.10.6";

        # Import dependency injection tools
        dependencyInjection = pkgs.callPackage ./dependency-injection.nix {
          inherit clj-pkgs;
          jdkRunner = default-jdk;
        };

        # Import container helpers
        containerHelpers = pkgs.callPackage ./container-helpers.nix { };

        # Import dependency management tools
        dependencyManagement = pkgs.callPackage ./dependency-management.nix {
          inherit system cljBuildToolsVersion;
          inherit (dependencyInjection) cljInject cljBuildInject;
          deps-lock = clj-nix.packages."${system}".deps-lock;
        };

        # Shared utilities for preparing Clojure sources with injected deps
        # (Internal helper, not exposed in packages)
        clojureHelpers = pkgs.callPackage ./clojure-helpers.nix {
          inherit cljBuildToolsVersion;
          inherit (dependencyInjection) cljInject cljBuildInject;
        };

        # All exports (including functions) - used by consumers
        # Using legacyPackages allows functions without flake check validation
        allExports = with pkgs.lib; rec {

          # --------------------------------------------------------------------
          # Clojure Build Helpers
          # --------------------------------------------------------------------

          # Build a Clojure library JAR file
          # See clojure-lib.nix for parameter documentation
          mkClojureLib = pkgs.callPackage ./clojure-lib.nix {
            inherit (clj-pkgs) mkCljLib;
            inherit clojureHelpers;
            jdkRunner = default-jdk;
          };

          # Build a runnable Clojure CLI application (uberjar)
          # See clojure-bin.nix for parameter documentation
          mkClojureBin = pkgs.callPackage ./clojure-bin.nix {
            inherit (clj-pkgs) mkCljBin;
            inherit clojureHelpers;
            jdkRunner = default-jdk;
          };

          # Build and run Clojure tests
          # See clojure-tests.nix for parameter documentation
          mkClojureTests = pkgs.callPackage ./clojure-tests.nix {
            inherit (clj-pkgs) mkCljLib;
            inherit clojureHelpers;
            jdkRunner = default-jdk;
          };

          # --------------------------------------------------------------------
          # Dependency Management
          # --------------------------------------------------------------------

          # Function to create a script for updating deps-lock.json
          # Consumers should call this with their deps: (updateClojureDeps {})
          # For nix run, use: nix run .#update-clojure-deps
          inherit (dependencyManagement) updateClojureDeps;

          # Pre-instantiated version of updateClojureDeps for direct usage
          # Usage: nix run .#update-clojure-deps
          #        nix run .#update-clojure-deps -- path/to/deps.edn
          update-clojure-deps = dependencyManagement.updateClojureDeps { };

          # Update deps with test alias included (locks test dependencies too)
          # Usage: nix run .#update-clojure-deps-with-tests
          update-clojure-deps-with-tests =
            dependencyManagement.updateClojureDeps { aliases = [ "test" ]; };

          # --------------------------------------------------------------------
          # Dependency Injection Tools
          # --------------------------------------------------------------------

          # Expose dependency injection binaries and functions
          inherit (dependencyInjection)
            cljInjectBin cljInject cljBuildInjectBin cljBuildInject;

          # --------------------------------------------------------------------
          # Container Helpers
          # --------------------------------------------------------------------

          # Expose container helpers
          inherit (containerHelpers) makeContainer deployContainers;
        };

      in {
        # legacyPackages is not validated by 'nix flake check', allowing functions
        # This is the standard way to expose both derivations and functions
        legacyPackages = allExports;

        # packages contains only actual derivations (for 'nix flake check')
        packages = with pkgs.lib; {
          # Only include instantiated derivations, not functions
          inherit (allExports)
            update-clojure-deps update-clojure-deps-with-tests cljInjectBin
            cljBuildInjectBin;
        };
      }) // {
        # Library functions (not system-specific or per-system helpers)
        lib = rec {
          # Package a Ruby script with proper shebang and runtime environment
          writeRubyApplication = import ./write-ruby-application.nix;

          # Helper to get system-specific functions (builders, dependency injection, containers, etc.)
          # Usage: (lib.forSystem "x86_64-linux").mkClojureLib { ... }
          #        (lib.forSystem "x86_64-linux").cljInject { ... }
          #        (lib.forSystem "x86_64-linux").makeContainer { ... }
          forSystem = system:
            let
              pkgs = import nixpkgs { inherit system; };
              clj-pkgs = clj-nix.packages."${system}";
              default-jdk = pkgs.jdk17_headless;
              cljBuildToolsVersion = "0.10.6";

              dependencyInjection =
                pkgs.callPackage ./dependency-injection.nix {
                  inherit clj-pkgs;
                  jdkRunner = default-jdk;
                };

              clojureHelpers = pkgs.callPackage ./clojure-helpers.nix {
                inherit cljBuildToolsVersion;
                inherit (dependencyInjection) cljInject cljBuildInject;
              };

              containerHelpers = pkgs.callPackage ./container-helpers.nix { };

              dependencyManagement =
                pkgs.callPackage ./dependency-management.nix {
                  inherit system cljBuildToolsVersion;
                  inherit (dependencyInjection) cljInject cljBuildInject;
                  deps-lock = clj-nix.packages."${system}".deps-lock;
                };
            in {
              # Clojure builders
              mkClojureLib = pkgs.callPackage ./clojure-lib.nix {
                inherit (clj-pkgs) mkCljLib;
                inherit clojureHelpers;
                jdkRunner = default-jdk;
              };

              mkClojureBin = pkgs.callPackage ./clojure-bin.nix {
                inherit (clj-pkgs) mkCljBin;
                inherit clojureHelpers;
                jdkRunner = default-jdk;
              };

              mkClojureTests = pkgs.callPackage ./clojure-tests.nix {
                inherit (clj-pkgs) mkCljLib;
                inherit clojureHelpers;
                jdkRunner = default-jdk;
              };

              # Dependency management
              inherit (dependencyManagement) updateClojureDeps;

              # Dependency injection
              inherit (dependencyInjection) cljInject cljBuildInject;

              # Container helpers
              inherit (containerHelpers) makeContainer deployContainers;
            };
        };
      };
}
