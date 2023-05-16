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
            inherit cljInject;
            jdkRunner = default-jdk;
          };
          mkClojureBin = pkgs.callPackage ./clojure-bin.nix {
            inherit (clj-pkgs) mkCljBin;
            inherit cljInject;
            jdkRunner = default-jdk;
          };
          updateCljDeps = deps:
            pkgs.writeShellApplication {
              name = "update-deps.sh";
              runtimeInputs =
                [ (cljInject deps) clj-nix.packages."${system}".deps-lock ];
              text = ''
                if [ ! $# -eq 1 ]; then
                  echo "usage: $0 <deps-file>"
                  exit 1
                fi
                DEPS=$1
                SRC=$(pwd)
                TMP=$(mktemp -d)
                clj-inject "$SRC" > "$TMP/deps.edn"
                cd $TMP
                deps-lock
                mv "$TMP/deps-lock.json" "$SRC/deps-lock.json"
              '';
            };
          updateClojureDeps = pkgs.writeShellScriptBin "update-deps.sh"
            "${clj-nix.packages."${system}".deps-lock}/bin/deps-lock";
          cljInjectScript = pkgs.callPackage ./lib/injector/package.nix {
            inherit (clj-pkgs) mkCljBin;
            jdkRunner = default-jdk;
          };
          cljInject = deps:
            pkgs.writeShellApplication {
              name = "clj-inject";
              runtimeInputs = [ cljInjectScript ];
              text = let
                injectionString = concatStringsSep " "
                  (mapAttrsToList (lib: jar: "${lib} ${jar}") deps);
              in ''injector --deps-file="$1" ${injectionString}'';
            };
        };
      }) // {
        lib.writeRubyApplication = import ./write-ruby-application.nix;
      };
}
