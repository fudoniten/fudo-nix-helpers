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
      in {
        packages = with pkgs.lib; rec {

          # --------------------------------------------------------------------
          # Clojure Build Helpers
          # --------------------------------------------------------------------

          # Shared utilities for preparing Clojure sources with injected deps
          clojureHelpers = pkgs.callPackage ./clojure-helpers.nix {
            inherit cljInject cljBuildInject cljBuildToolsVersion;
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

          # Helper script to regenerate deps-lock.json with all injections applied.
          # Usage: nix run .#updateClojureDeps
          #        nix run .#updateClojureDeps -- path/to/deps.edn
          updateClojureDeps = pkgs.writeShellApplication {
              name = "update-deps.sh";
              runtimeInputs = [
                (cljInject {})
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
                # First pass: inject local dependency overrides
                clj-inject "$DEPS" > "$TMP/deps-prebuild.edn"
                # Second pass: inject build alias configuration
                clj-build-inject "$TMP/deps-prebuild.edn" > "$TMP/deps.edn"
                echo "DEPS.EDN:"
                cat "$TMP/deps.edn"
                cd "$TMP"
                # Generate the lockfile
                deps-lock
                mv "$TMP/deps-lock.json" "$SRC/deps-lock.json"
              '';
            };

          # --------------------------------------------------------------------
          # Dependency Injection Tools
          # --------------------------------------------------------------------

          # The injector binary - replaces Maven deps with :local/root paths
          cljInjectBin = pkgs.callPackage ./lib/injector/package.nix {
            inherit (clj-pkgs) mkCljBin;
            jdkRunner = default-jdk;
          };

          # Wrapper that invokes injector with a map of dependencies to inject.
          # deps: { "org.myorg/my-lib" = /nix/store/...-my-lib.jar; }
          cljInject = deps:
            pkgs.writeShellApplication {
              name = "clj-inject";
              runtimeInputs = [ cljInjectBin ];
              text = let
                # Build CLI arguments: 'lib-coord' 'jar-path' pairs
                # Single quotes protect against special characters in paths
                injectionString = concatStringsSep " "
                  (mapAttrsToList (lib: jar: "'${lib}' '${jar}'") deps);
              in ''injector --deps-file="$1" ${injectionString}'';
            };

          # The build-injector binary - adds :build alias with tools.build
          cljBuildInjectBin =
            pkgs.callPackage ./lib/build-injector/package.nix {
              inherit (clj-pkgs) mkCljBin;
              jdkRunner = default-jdk;
            };

          # Wrapper that invokes build-injector with namespace and dependencies.
          # ns: Build namespace (typically "build")
          # deps: { "io.github.clojure/tools.build" = "0.10.6"; }
          cljBuildInject = ns: deps:
            pkgs.writeShellApplication {
              name = "clj-build-inject";
              runtimeInputs = [ cljBuildInjectBin ];
              text = let
                # Build CLI arguments: 'lib-coord' 'version' pairs
                injectionString = concatStringsSep " "
                  (mapAttrsToList (lib: ver: "'${lib}' '${ver}'") deps);
              in ''
                build-injector --deps-file="$1" --build-namespace='${ns}' ${injectionString}'';
            };

          # --------------------------------------------------------------------
          # Container Helpers
          # --------------------------------------------------------------------

          # Create a Docker-compatible container image.
          #
          # Required parameters:
          #   name: Container name
          #   repo: Registry/repository (e.g., "docker.io/myuser")
          #   tag: Image tag
          #   entrypoint: Command to run (string or list)
          #
          # Optional parameters:
          #   user: Container user (default: "executor")
          #   env: Environment variables (attrs or list)
          #   environmentPackages: Additional packages to include
          #   pathEnv: Packages to add to PATH
          #   exposedPorts: Ports to expose (int, string, or {port, type} attrs)
          #   volumes: Volume mount points
          makeContainer = { name, entrypoint, repo, env ? { }
            , environmentPackages ? [ ], tag, exposedPorts ? [ ], volumes ? [ ]
            , pathEnv ? [ ], user ? "executor", ... }:
            let
              workDir = "/var/lib/${user}";

              # Base packages included in all containers for common functionality
              basePackages = with pkgs; [
                bashInteractive      # Shell access for debugging
                coreutils            # Basic Unix utilities
                dnsutils             # DNS resolution (dig, nslookup)
                cacert               # SSL/TLS root certificates
                glibc                # C library
                glibcLocalesUtf8     # UTF-8 locale data
                nss                  # Name service switch libraries
                tzdata               # Timezone data
              ];
            in pkgs.dockerTools.buildLayeredImage {
              name = "${repo}/${name}";
              inherit tag;
              contents = basePackages ++ environmentPackages ++ pathEnv;

              # Enable fakechroot for proper /etc setup during build
              enableFakechroot = true;

              # Commands run as root during image creation
              fakeRootCommands = ''
                ${pkgs.dockerTools.shadowSetup}
                # Create non-root user for security (UID 1000 for compatibility)
                groupadd -g 1000 ${user}
                useradd -u 1000 -g ${user} -d ${workDir} -M -r ${user}
                mkdir -p ${workDir}
                chown -R ${user}:${user} ${workDir}
              '';

              config = {
                User = user;
                WorkingDir = workDir;

                # Build environment variables from user-provided and defaults
                Env = let
                  # Normalize env to list format (supports attrs or list input)
                  mkEnv = env:
                    if (isAttrs env) then
                      mapAttrsToList (k: v: "${k}=${toString v}") env
                    else
                      env;
                in (mkEnv env) ++ (mkEnv (rec {
                  # SSL certificates for HTTPS connections
                  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
                  NIX_SSL_CERT_FILE = SSL_CERT_FILE;
                  # UTF-8 locale for proper text handling
                  LOCALE_ARCHIVE =
                    "${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive";
                  LANG = "C.UTF-8";
                  LC_ALL = "C.UTF-8";
                  TZ = "UTC";
                  # PATH includes base packages and user-specified pathEnv
                  PATH = makeBinPath (basePackages ++ pathEnv);
                }));

                # Normalize entrypoint to list format
                Entrypoint =
                  if (isString entrypoint) then [ entrypoint ] else entrypoint;

                # Normalize port specifications to Docker format
                # Supports: int (8080), string ("8080/udp"), attrs ({port=8080; type="tcp";})
                ExposedPorts = if (isList exposedPorts) then
                  listToAttrs (map (port:
                    if (isString port) then
                      nameValuePair port { }
                    else if (isInt port) then
                      nameValuePair "${toString port}/tcp" { }
                    else
                      nameValuePair
                      "${toString port.port}/${port.type or "tcp"}" { })
                    exposedPorts)
                else
                  mapAttrs' (_:
                    { port, type, ... }@opts:
                    nameValuePair "${toString port}/${type}" { }) exposedPorts;

                # Normalize volume specifications
                Volumes = if (isList volumes) then
                  listToAttrs (map (vol: nameValuePair vol { }) volumes)
                else
                  volumes;
              };
            };

          # Create a script to push container images to a registry.
          #
          # Takes all makeContainer parameters plus:
          #   tags: List of tags to push (default: ["latest"])
          #   verbose: Print progress messages (default: false)
          #
          # Usage: nix build .#deployContainers && ./result/bin/deployContainers
          deployContainers =
            { name, verbose ? false, repo, tags ? [ "latest" ], ... }@opts:
            let
              # Generate push commands for each tag
              containerPushScript = concatStringsSep "\n" (map (tag:
                let container = makeContainer (opts // { inherit tag; });
                in concatStringsSep "\n" ((optional verbose
                  ''echo "pushing ${name} -> ${repo}/${name}:${tag}"'') ++ [
                    ''
                      skopeo copy --policy ${policyJson} docker-archive:"${container}" "docker://${repo}/${name}:${tag}"''
                  ])) tags);

              # Policy that accepts any image (required for local builds)
              # Note: This is permissive; for production, consider stricter policies
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
        # Library functions (not system-specific)
        lib = {
          # Package a Ruby script with proper shebang and runtime environment
          writeRubyApplication = import ./write-ruby-application.nix;
        };
      };
}
