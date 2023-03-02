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
        packages = {
          mkClojureLib = pkgs.callPackage ./clojure-lib.nix {
            inherit (clj-pkgs) mkCljLib;
            jdkRunner = default-jdk;
          };
          mkClojureBin = pkgs.callPackage ./clojure-bin.nix {
            inherit (clj-pkgs) mkCljBin;
            jdkRunner = default-jdk;
          };
          updateClojureDeps = pkgs.writeShellScriptBin "update-deps.sh"
            "${clj-nix.packages."${system}".deps-lock}/bin/deps-lock";
        };
      }) // {
        lib.writeRubyApplication = import ./write-ruby-application.nix;
      };
}
