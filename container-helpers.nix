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
  makeContainer = { name, entrypoint, repo, env ? { }, environmentPackages ? [ ]
    , tag, exposedPorts ? [ ], volumes ? [ ], pathEnv ? [ ], user ? "executor"
    , ... }:
    let
      workDir = "/var/lib/${user}";

      # Base packages included in all containers for common functionality
      basePackages = with pkgs; [
        bashInteractive # Shell access for debugging
        coreutils # Basic Unix utilities
        dnsutils # DNS resolution (dig, nslookup)
        cacert # SSL/TLS root certificates
        glibc # C library
        glibcLocalesUtf8 # UTF-8 locale data
        nss # Name service switch libraries
        tzdata # Timezone data
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
        useradd -u 1000 -p '*' -g ${user} -d ${workDir} -M -r ${user}
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
          LOCALE_ARCHIVE = "${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive";
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
              nameValuePair "${toString port.port}/${port.type or "tcp"}" { })
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
  #   tags:        List of tags to push (default: ["latest"])
  #   verbose:     Print progress messages (default: false)
  #   authfile:    Where the registry credential lives: a containers-auth.json
  #                as written by `skopeo login` or `podman login`. Default is
  #                null, meaning skopeo's own search order (see below).
  #   requireAuth: Fail before building anything when no credential is found
  #                for the registry. Default: true for remote registries,
  #                false for localhost (a port-forwarded registry needs none).
  #
  # Usage: nix run .#deployContainer
  #
  # ## Where the credential comes from
  #
  # skopeo is not given credentials on the command line; it searches, in order:
  #
  #   1. $REGISTRY_AUTH_FILE            <- what `authfile` below sets
  #   2. $XDG_RUNTIME_DIR/containers/auth.json   (`skopeo login` default)
  #   3. ~/.docker/config.json
  #
  # If none of those holds an entry for the registry, skopeo pushes
  # ANONYMOUSLY, and a registry that rejects that answers 403 at the token
  # exchange, which reads like a permissions bug rather than a missing
  # login. Setting `authfile` makes the source explicit, and `requireAuth`
  # turns the silent anonymous push into an error that says what to do.
  #
  # Note (2) is a tmpfs: a plain `skopeo login` does not survive a reboot.
  # Point `authfile` somewhere under $HOME to keep it.
  #
  # ## authfile must be a STRING, not a Nix path
  #
  # `authfile = ./auth.json;` copies the credential into the world-readable
  # Nix store. Write it as a string instead:
  #
  #     authfile = "/home/you/.config/containers/auth.json";
  #
  # Only the path is baked into the script; the file itself is read at run
  # time by the machine doing the push. This is enforced below, not merely
  # documented.
  deployContainers = { name, verbose ? false, repo, tags ? [ "latest" ]
    , authfile ? null, requireAuth ? null, ... }@opts:
    let
      # Docker's rule for splitting a repo into host + namespace: the first
      # component is a registry host only if it contains a '.' or a ':', or
      # is exactly "localhost". Anything else is a Docker Hub namespace.
      #
      #   "ghcr.io/fudoniten"        -> ghcr.io
      #   "registry.example/team"    -> registry.example
      #   "localhost:5000"           -> localhost:5000
      #   "someuser"                 -> docker.io
      firstPart = head (splitString "/" repo);

      registryHost =
        if (hasInfix "." firstPart) || (hasInfix ":" firstPart) || (firstPart
        == "localhost") then
          firstPart
        else
          "docker.io";

      isLocal = (firstPart == "localhost") || (hasPrefix "localhost:" firstPart)
        || (hasPrefix "127.0.0.1" firstPart);

      needAuth = if requireAuth != null then requireAuth else !isLocal;

      # Reject a Nix path before it becomes a store path holding a secret.
      checkedAuthfile = if authfile == null then
        null
      else if !(isString authfile) then
        throw ("deployContainers: `authfile` must be a string, not a Nix path."
          + " A path literal copies the credential into the world-readable Nix"
          + " store. Write it as a string:"
          + " authfile = \"/home/you/.config/containers/auth.json\";")
      else if hasPrefix builtins.storeDir authfile then
        throw ("deployContainers: `authfile` (${authfile}) points into the Nix"
          + " store. Credentials must not live there.")
      else
        authfile;

      # Registry-specific guidance for the "no credential" message. Both of
      # these get the token type wrong often enough to be worth naming.
      loginHintLines = if registryHost == "ghcr.io" then [
        "  The username is your GitHub login. The password is a CLASSIC"
        "  personal access token carrying 'write:packages' and 'read:packages'."
        "  Fine-grained tokens do not work with ghcr.io and fail as a 403."
        "  Create one at https://github.com/settings/tokens"
      ] else if registryHost == "docker.io" then [
        "  The password is an access token, not your account password:"
        "  https://app.docker.com/settings/personal-access-tokens"
      ] else
        [ ];

      # Keep every string below plain ASCII, and free of backticks and '$'.
      # These end up inside single-quoted printf arguments in a script that
      # writeShellApplication runs shellcheck over at build time, where two
      # things bite:
      #
      #   - shellcheck runs under a C locale in the build sandbox, so when it
      #     reports a finding on a line holding a non-ASCII character it dies
      #     encoding its own output ("commitBuffer: invalid argument") rather
      #     than printing the finding.
      #   - a backtick or a '$' inside single quotes is SC2016, which is what
      #     produces a finding for it to choke on in the first place.
      #
      # The two compound: the encoding crash only surfaces once something
      # else has already warned, so non-ASCII text can sit here harmlessly
      # until an unrelated edit trips a warning.
      printfLines = lines:
        "printf '%s\\n' "
        + (concatStringsSep " " (map escapeShellArg lines)) + " >&2";

      # Generate push commands for each tag
      containerPushScript = concatStringsSep "\n" (map (tag:
        let container = makeContainer (opts // { inherit tag; });
        in concatStringsSep "\n"
        ((optional verbose ''echo "pushing ${name} -> ${repo}/${name}:${tag}"'')
          ++ [
            ''push ${escapeShellArg container} ${
              escapeShellArg "${repo}/${name}:${tag}"
            }''
          ])) tags);

      # Policy that accepts any image (required for local builds)
      # Note: This is permissive; for production, consider stricter policies
      policyJson = pkgs.writeText "containers-policy.json" (builtins.toJSON {
        default = [{ type = "reject"; }];
        transports = {
          docker = { "" = [{ type = "insecureAcceptAnything"; }]; };
          docker-archive = { "" = [{ type = "insecureAcceptAnything"; }]; };
        };
      });
    in pkgs.writeShellApplication {
      name = "deployContainers";
      runtimeInputs = with pkgs; [ skopeo coreutils ];
      text = ''
        set -euo pipefail

        ${optionalString (checkedAuthfile != null) ''
          # Set here so a push does not depend on whatever ambient credential
          # state this particular machine happens to have. Both skopeo login
          # and skopeo copy honour this variable.
          export REGISTRY_AUTH_FILE=${escapeShellArg checkedAuthfile}
        ''}

        ${optionalString needAuth ''
          if ! skopeo login --get-login ${
            escapeShellArg registryHost
          } >/dev/null 2>&1; then
            # Resolve which file skopeo actually consulted, so the message
            # below names a real path rather than a list of candidates.
            if [ -n "''${REGISTRY_AUTH_FILE:-}" ]; then
              authfile_path="$REGISTRY_AUTH_FILE"
            elif [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
              authfile_path="$XDG_RUNTIME_DIR/containers/auth.json"
            else
              authfile_path="''${HOME:-}/.docker/config.json"
            fi
            ${
              printfLines [
                ""
                "deployContainers: no credential found for ${registryHost}."
                ""
              ]
            }
            printf '  Looked in: %s\n\n' "$authfile_path" >&2
            ${
              printfLines ([
                "  Log in once, then re-run this command:"
                ""
                "      skopeo login ${registryHost} -u USERNAME --password-stdin"
                ""
              ] ++ loginHintLines ++ [ "" ])
            }
            exit 1
          fi
        ''}

        # Wrapped so a 403 explains itself rather than just ending the run.
        push() {
          if skopeo copy --policy ${policyJson} "docker-archive:$1" "docker://$2"; then
            return 0
          fi
          ${
            printfLines [
              ""
              "deployContainers: push failed."
              ""
              "If that was a 403 while requesting a bearer token, the credential"
              "was found but may not write there. The usual causes:"
              ""
              "  - the namespace in 'repo' is not one this account can push to."
              "    On ghcr.io it must be a GitHub user or org login, not a"
              "    domain name that merely looks right."
              "  - the token lacks a write scope, or is a fine-grained token."
              "  - the org has SAML SSO and the token is not authorised for it."
              ""
            ]
          }
          exit 1
        }

        ${containerPushScript}
      '';
    };
}
