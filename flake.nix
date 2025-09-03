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

          makeContainer = { name, entrypoint, env ? { }
            , environmentPackages ? [ ], repo, tag, exposedPorts ? [ ]
            , volumes ? [ ], pathEnv ? [ ], user ? "executor", ... }:
            let workDir = "/var/lib/${user}";
            in pkgs.dockerTools.buildLayeredImage {
              name = "${repo}/${name}";
              inherit tag;
              contents = with pkgs;
                [
                  bashInteractive
                  coreutils
                  dnsutils
                  cacert
                  glibc
                  glibcLocalesUtf8
                  nss
                  tzdata
                ] ++ environmentPackages ++ pathEnv;
              enableFakechroot = true;
              fakeRootCommands = ''
                ${pkgs.dockerTools.shadowSetup}
                groupadd -g 1000 ${user}
                useradd -u 1000 -g ${user} -d ${workDir} -M -r ${user}
                mkdir -p ${workDir}
                chown -R ${user}:${user} ${workDir}
                # link certs/locale for happy TLS + UTF-8 logs
              '';
              config = {
                User = user;
                WorkingDir = workDir;
                Env = let
                  mkEnv = env:
                    if (isAttrs env) then
                      mapAttrsToList (k: v: "${k}=${toString v}") env
                    else
                      env;
                in (mkEnv env) ++ (mkEnv (rec {
                  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
                  NIX_SSL_CERT_FILE = SSL_CERT_FILE;
                  LOCALE_ARCHIVE =
                    "${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive";
                  LANG = "C.UTF-8";
                  LC_ALL = "C.UTF-8";
                  TZ = "UTC";
                  PATH = makeBinPath pathEnv;
                }));
                Entrypoint =
                  if (isString entrypoint) then [ entrypoint ] else entrypoint;
                ExposedPorts = if (isList exposedPorts) then
                  listToAttrs (map (port:
                    if (isString port) then
                      nameValuePair port { }
                    else if (isInt port) then
                      nameValuePair "${toString port}/tcp" { }
                    else
                      nameValuePair
                      "${toString port.port}/${port.type or "tcp"}")
                    exposedPorts)
                else
                  mapAttrs' (_:
                    { port, type, ... }@opts:
                    nameValuePair "${toString port}/${type}" { }) exposedPorts;

                Volumes = if (isList volumes) then
                  listToAttrs (map (vol: nameValuePair vol { }) volumes)
                else
                  volumes;
              };
            };

          deployContainers = { name, verbose ? false
            , repo ? "registry.kube.sea.fudo.link", tags ? [ "latest" ], ...
            }@opts:
            let
              containerPushScript = map (tag:
                let container = makeContainer (opts // { inherit tag; });
                in concatStringsSep "\n" ((optional verbose
                  "echo pushing ${name} -> ${repo}/${name}:${tag}") ++ [
                    ''
                      skopeo copy --policy ${policyJson} docker-archive:"${container}" "docker://${repo}/${name}:${tag}"''
                  ])) tags;
              policyJson = pkgs.writeText "containers-policy.json"
                (builtins.toJSON {
                  default = [{ type = "reject"; }];
                  transports = {
                    docker = { "" = [{ type = "insecureAcceptAnything"; }]; };
                    docker-archive = {
                      "" = [{ type = "insecureAcceptAnything"; }];
                    };
                  };
                });
            in pkgs.writeShellApplication {
              name = "deployContainers";
              runtimeInputs = with pkgs; [ skopeo coreutils ];
              text = ''
                set -euo pipefail
                ${containerPushScript}
              '';
            };
        };
      }) // {
        lib = { writeRubyApplication = import ./write-ruby-application.nix; };
      };
}
