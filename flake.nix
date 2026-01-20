# fudo-nix-helpers flake
#
# This flake provides helpers for building Clojure projects and container images
# with Nix. The key feature is dependency injection that allows using local
# Clojure libraries without uploading them to Maven.
#
# Main exports:
#   - mkClojureLib: Build a Clojure library JAR
#   - mkClojureBin: Build a runnable Clojure CLI application
#   - makeContainer: Create a Docker-compatible container image
#   - deployContainers: Push containers to a registry
#   - updateClojureDeps: Regenerate deps-lock.json with injected dependencies
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

      in {
        packages = with pkgs.lib; rec {

          # --------------------------------------------------------------------
          # Clojure Build Helpers
          # --------------------------------------------------------------------

          # Shared utilities for preparing Clojure sources with injected deps
          clojureHelpers = pkgs.callPackage ./clojure-helpers.nix {
            inherit cljBuildToolsVersion;
            inherit (dependencyInjection) cljInject cljBuildInject;
          };

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

          # --------------------------------------------------------------------
          # Dependency Management
          # --------------------------------------------------------------------

          # Expose updateClojureDeps from dependency-management module
          inherit (dependencyManagement) updateClojureDeps;

          # --------------------------------------------------------------------
          # Dependency Injection Tools
          # --------------------------------------------------------------------

          # Expose dependency injection tools
          inherit (dependencyInjection)
            cljInjectBin cljInject cljBuildInjectBin cljBuildInject;

          # --------------------------------------------------------------------
          # Container Helpers
          # --------------------------------------------------------------------

          # Expose container helpers
          inherit (containerHelpers) makeContainer deployContainers;
        };
      }) // {
        # Library functions (not system-specific)
        lib = {
          # Package a Ruby script with proper shebang and runtime environment
          writeRubyApplication = import ./write-ruby-application.nix;
        };
      };
}
