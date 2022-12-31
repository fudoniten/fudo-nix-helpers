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
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
      in {
        packages = { inherit (pkgs) mkClojureLib mkClojureBin; };
        devShells.clojure = let
          update-deps = pkgs.writeShellScriptBin "update-deps.sh"
            "${clj-nix.packages."${system}".deps-lock}/bin/deps-lock";
        in pkgs.devshell.mkShell {
          packages = with pkgs; [ clojure update-deps ];
        };
      }) // {
        lib = { writeRubyApplication = import ./write-ruby-application.nix; };
        overlays.default = final: prev:
          let
            clj-pkgs = clj-nix.packages."${prev.system}";
            default-jdk = prev.jdk18_headless;
          in {
            mkClojureLib = final.callPackage ./clojure-lib.nix {
              inherit (clj-pkgs) mkCljLib;
              jdkRunner = default-jdk;
            };
            mkClojureBin = final.callPackage ./clojure-bin.nix {
              inherit (clj-pkgs) mkCljBin;
              jdkRunner = default-jdk;
            };
          };
      };
}
