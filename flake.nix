{
  inputs = {
    clj-nix = {
      url = "github:jlesquembre/clj-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    clj2nix.url = "github:hlolli/clj2nix";
    nixpkgs.url = "nixpkgs/nixos-22.11";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, clj2nix, clj-nix, utils, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        clj-pkgs = clj-nix.packages."${system}";

        default-jdk = pkgs.jdk17_headless;
      in {
        packages = with pkgs.lib; rec {
          mkClojureLib = pkgs.callPackage ./clojure-lib.nix {
            inherit (clj-pkgs) mkCljLib;
            inherit cljInject cljBuildInject;
            jdkRunner = default-jdk;
          };
          mkClojureBin = pkgs.callPackage ./clojure-bin.nix {
            inherit (clj-pkgs) mkCljBin;
            inherit cljInject cljBuildInject;
            jdkRunner = default-jdk;
          };
          updateClojureDeps = deps:
            pkgs.writeShellApplication {
              name = "update-deps.sh";
              runtimeInputs = [
                (cljInject deps)
                (cljBuildInject "build" {
                  "io.github.clojure/tools.build" = "0.10.0";
                })
                clj-nix.packages."${system}".deps-lock
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
                clj-inject "$DEPS" > "$TMP/deps-prebuild.edn"
                clj-build-inject "$TMP/deps-prebuild.edn" > "$TMP/deps.edn"
                cat "DEPS.EDN:"
                cat "$TMP/deps.edn"
                cd "$TMP"
                deps-lock
                mv "$TMP/deps-lock.json" "$SRC/deps-lock.json"
              '';
            };
          # updateClojureDeps = pkgs.writeShellScriptBin "update-deps.sh"
          #   "${clj-nix.packages."${system}".deps-lock}/bin/deps-lock";
          cljInject = deps:
            let
              script = pkgs.callPackage ./lib/injector/package.nix {
                inherit (clj-pkgs) mkCljBin;
                jdkRunner = default-jdk;
              };
            in pkgs.writeShellApplication {
              name = "clj-inject";
              runtimeInputs = [ script ];
              text = let
                injectionString = concatStringsSep " "
                  (mapAttrsToList (lib: jar: "${lib} ${jar}") deps);
              in ''injector --deps-file="$1" ${injectionString}'';
            };
          cljBuildInject = ns: deps:
            let
              script = pkgs.callPackage ./lib/build-injector/package.nix {
                inherit (clj-pkgs) mkCljBin;
                jdkRunner = default-jdk;
              };
            in pkgs.writeShellApplication {
              name = "clj-build-inject";
              runtimeInputs = [ script ];
              text = let
                injectionString = concatStringsSep " "
                  (mapAttrsToList (lib: ver: "${lib} ${ver}") deps);
              in ''
                build-injector --deps-file="$1" --build-namespace=${ns} ${injectionString}'';
            };
        };
      }) // {
        lib.writeRubyApplication = import ./write-ruby-application.nix;
      };
}
