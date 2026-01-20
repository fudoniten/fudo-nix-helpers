# Container image building and deployment helpers
#
# This module provides functions for creating Docker-compatible container images
# and deploying them to container registries.

{ pkgs }:

with pkgs.lib;

rec {
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
}
