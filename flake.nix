{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    clj-nix = {
      url = "github:jlesquembre/clj-nix/0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    clj2nix.url = "github:hlolli/clj2nix";
    utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
  };

  outputs = { self, nixpkgs, clj-nix, utils, nix2container, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        clj-pkgs = clj-nix.packages."${system}";

        default-jdk = pkgs.jdk17_headless;

        cljBuildToolsVersion = "0.10.6";
      in {
        packages = with pkgs.lib; rec {
          mkClojureLib = pkgs.callPackage ./clojure-lib.nix {
            inherit (clj-pkgs) mkCljLib;
            inherit cljInject cljBuildInject cljBuildToolsVersion;
            jdkRunner = default-jdk;
          };
          mkClojureBin = pkgs.callPackage ./clojure-bin.nix {
            inherit (clj-pkgs) mkCljBin;
            inherit cljInject cljBuildInject cljBuildToolsVersion;
            jdkRunner = default-jdk;
          };
          updateClojureDeps = deps:
            pkgs.writeShellApplication {
              name = "update-deps.sh";
              runtimeInputs = [
                (cljInject deps)
                (cljBuildInject "build" {
                  "io.github.clojure/tools.build" = cljBuildToolsVersion;
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
                echo "DEPS.EDN:"
                cat "$TMP/deps.edn"
                cd "$TMP"
                deps-lock
                mv "$TMP/deps-lock.json" "$SRC/deps-lock.json"
              '';
            };
          cljInjectBin = pkgs.callPackage ./lib/injector/package.nix {
            inherit (clj-pkgs) mkCljBin;
            jdkRunner = default-jdk;
          };
          cljInject = deps:
            pkgs.writeShellApplication {
              name = "clj-inject";
              runtimeInputs = [ cljInjectBin ];
              text = let
                injectionString = concatStringsSep " "
                  (mapAttrsToList (lib: jar: "${lib} ${jar}") deps);
              in ''injector --deps-file="$1" ${injectionString}'';
            };
          cljBuildInjectBin =
            pkgs.callPackage ./lib/build-injector/package.nix {
              inherit (clj-pkgs) mkCljBin;
              jdkRunner = default-jdk;
            };
          cljBuildInject = ns: deps:
            pkgs.writeShellApplication {
              name = "clj-build-inject";
              runtimeInputs = [ cljBuildInjectBin ];
              text = let
                injectionString = concatStringsSep " "
                  (mapAttrsToList (lib: ver: "${lib} ${ver}") deps);
              in ''
                build-injector --deps-file="$1" --build-namespace=${ns} ${injectionString}'';
            };
          makeContainers = { name, entrypoint, env ? [ ]
            , environmentPackages ? [ ], repo ? "registry.kube.sea.fudo.link"
            , tags ? [ ], ... }:
            let containerPkgs = nix2container.packages."${system}";
            in map (tag:
              containerPkgs.nix2container.buildImage ({
                name = "${repo}/${name}";
                config = {
                  entrypoint = entrypoint;
                  inherit env;
                };
                copyToRoot = pkgs.buildEnv {
                  name = "root";
                  paths = environmentPackages
                    ++ (with pkgs; [ bashInteractive ]);
                  pathsToLink = [ "/bin" ];
                };
              } // (optionalAttrs (!isNull tag) { inherit tag; })))
            (tags ++ [ null ]);

          deployContainers = { name, verbose ? false, ... }@opts:
            let containers = makeContainers opts;
            in pkgs.writeShellScript "deploy-${name}-containers.sh"
            (concatStringsSep "\n" ([
              (optionalString verbose ''
                echo "deploying ${
                  toString (length containers)
                } containers for ${name}..."'')
            ] ++ (map (container: "${container.copyToRegistry}") containers)));
        };
      }) // {
        lib = { writeRubyApplication = import ./write-ruby-application.nix; };
      };
}
