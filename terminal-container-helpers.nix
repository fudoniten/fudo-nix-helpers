# Terminal container image building helpers
#
# This module provides functions for creating SSH-accessible terminal containers
# suitable for use as remote development environments or agent execution hosts.
#
# The containers use tini as init (for proper signal handling and zombie reaping)
# with sshd as the main service.

{ pkgs }:

with pkgs.lib;

rec {
  # --------------------------------------------------------------------
  # Terminal Container Helpers
  # --------------------------------------------------------------------

  # Create an SSH-accessible terminal container image.
  #
  # This builds a lightweight container with OpenSSH server that can be used
  # as a terminal host for remote agents or development. Unlike full NixOS
  # containers, this runs without systemd and is suitable for standard
  # Kubernetes deployments.
  #
  # Required parameters:
  #   name: Container name
  #   repo: Registry/repository (e.g., "docker.io/myuser")
  #   tag: Image tag
  #   authorizedKeys: List of SSH public keys for authentication
  #
  # Optional parameters:
  #   user: Primary user name (default: "hermes")
  #   uid: User ID (default: 1000)
  #   gid: Group ID (default: 1000)
  #   shell: User's shell (default: bashInteractive)
  #   sshPort: SSH port (default: 22)
  #   packages: Additional packages to include
  #   env: Environment variables
  #   extraSshdConfig: Additional sshd_config options
  #   workDir: Working directory (default: /home/<user>)
  #   enableGit: Include git (default: true)
  #   enableNix: Include nix package manager (default: false)
  #   volumes: Volume mount points to declare
  #
  makeTerminalContainer = { name, repo, tag, authorizedKeys, user ? "hermes"
    , uid ? 1000, gid ? 1000, shell ? pkgs.bashInteractive, sshPort ? 22
    , packages ? [ ], env ? { }, extraSshdConfig ? "", workDir ? null
    , enableGit ? true, enableNix ? false, volumes ? [ ], ... }:
    let
      # Compute working directory
      homeDir = if workDir != null then workDir else "/home/${user}";

      # Base packages always included
      basePackages = with pkgs; [
        tini # Minimal init for containers
        bashInteractive # Interactive shell
        coreutils # Basic Unix utilities
        findutils # find, xargs
        gnugrep # grep
        gnused # sed
        gawk # awk
        procps # ps, top, etc.
        less # Pager
        openssh # SSH server and client
        cacert # SSL/TLS certificates
        glibc # C library
        glibcLocalesUtf8 # UTF-8 locale support
        nss # Name service switch
        tzdata # Timezone data
        dnsutils # DNS tools
        curl # HTTP client
        wget # HTTP client
        which # which command
        file # file type detection
      ];

      # Optional packages based on flags
      optionalPackages = (optional enableGit pkgs.git)
        ++ (optionals enableNix [ pkgs.nix pkgs.nixos-rebuild ]);

      # All packages for the container
      allPackages = basePackages ++ optionalPackages ++ packages ++ [ shell ];

      # Create authorized_keys file
      authorizedKeysFile =
        pkgs.writeText "authorized_keys" (concatStringsSep "\n" authorizedKeys);

      # Generate sshd_config
      sshdConfig = pkgs.writeText "sshd_config" ''
        # SSH daemon configuration for terminal container
        Port ${toString sshPort}
        AddressFamily any
        ListenAddress 0.0.0.0
        ListenAddress ::

        # Host keys (generated at container startup)
        HostKey /etc/ssh/ssh_host_ed25519_key
        HostKey /etc/ssh/ssh_host_rsa_key

        # Security settings
        PermitRootLogin no
        PasswordAuthentication no
        PermitEmptyPasswords no
        ChallengeResponseAuthentication no
        KbdInteractiveAuthentication no
        UsePAM no
        PubkeyAuthentication yes
        AuthorizedKeysFile %h/.ssh/authorized_keys

        # Session settings
        X11Forwarding no
        PrintMotd no
        AcceptEnv LANG LC_*

        # Subsystems
        Subsystem sftp /run/current-system/sw/libexec/sftp-server

        # Keepalive
        ClientAliveInterval 60
        ClientAliveCountMax 3

        # Logging
        LogLevel INFO
        SyslogFacility AUTH

        ${extraSshdConfig}
      '';

      # Create initialization script that runs before sshd
      initScript = pkgs.writeShellScript "init-terminal" ''
        set -e

        # Ensure /etc/ssh exists
        mkdir -p /etc/ssh

        # Generate host keys if they don't exist
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
        fi
        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
        fi

        # Ensure user home and .ssh directory exist with correct permissions
        mkdir -p ${homeDir}/.ssh

        # Only copy default authorized_keys if none exists (allows K8s secret injection)
        if [ ! -f ${homeDir}/.ssh/authorized_keys ]; then
          cp ${authorizedKeysFile} ${homeDir}/.ssh/authorized_keys
        fi

        chmod 700 ${homeDir}/.ssh
        chmod 600 ${homeDir}/.ssh/authorized_keys
        chown -R ${toString uid}:${toString gid} ${homeDir}

        # Create required directories for sshd
        mkdir -p /run/sshd

        # Start sshd in foreground
        exec ${pkgs.openssh}/bin/sshd -D -f ${sshdConfig} -e
      '';

      # Entrypoint using tini
      entrypoint = [ "${pkgs.tini}/bin/tini" "--" "${initScript}" ];

    in pkgs.dockerTools.buildLayeredImage {
      name = "${repo}/${name}";
      inherit tag;
      contents = allPackages;

      enableFakechroot = true;

      fakeRootCommands = ''
        ${pkgs.dockerTools.shadowSetup}

        # Create sshd user for privilege separation
        groupadd -r sshd
        useradd -r -g sshd -d /var/empty -s /sbin/nologin -c "SSH privilege separation" sshd

        # Create the user and group
        groupadd -g ${toString gid} ${user}
        useradd -u ${
          toString uid
        } -g ${user} -d ${homeDir} -s ${shell}/bin/bash -M ${user}

        # Unlock the user account to allow SSH key authentication
        # Set password to * (allows key-based auth, blocks password auth)
        usermod -p '*' ${user}

        # Create home directory
        mkdir -p ${homeDir}
        chown -R ${toString uid}:${toString gid} ${homeDir}

        # Create /etc/ssh for host keys (will be populated at runtime)
        mkdir -p /etc/ssh

        # Create /run/sshd (required by sshd)
        mkdir -p /run/sshd

        # Create /tmp with proper permissions
        mkdir -p /tmp
        chmod 1777 /tmp

        # Create /var/empty for sshd privilege separation
        mkdir -p /var/empty
        chmod 755 /var/empty

        # Create symlink for sftp-server
        mkdir -p /run/current-system/sw/libexec
        ln -sf ${pkgs.openssh}/libexec/sftp-server /run/current-system/sw/libexec/sftp-server
      '';

      config = {
        User = "root"; # Init script needs root, sshd drops privileges
        WorkingDir = homeDir;

        Env = let
          mkEnv = e:
            if (isAttrs e) then
              mapAttrsToList (k: v: "${k}=${toString v}") e
            else
              e;
        in (mkEnv env) ++ (mkEnv {
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          LOCALE_ARCHIVE = "${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive";
          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";
          TZ = "UTC";
          HOME = homeDir;
          USER = user;
          PATH = makeBinPath allPackages;
          SHELL = "${shell}/bin/bash";
        });

        Entrypoint = entrypoint;

        ExposedPorts = { "${toString sshPort}/tcp" = { }; };

        Volumes = if (isList volumes) then
          listToAttrs
          (map (vol: nameValuePair vol { }) (volumes ++ [ homeDir ]))
        else
          volumes // { "${homeDir}" = { }; };
      };
    };

  # Create a script to push terminal containers to a registry.
  #
  # Takes all makeTerminalContainer parameters plus:
  #   tags: List of tags to push (default: ["latest"])
  #   verbose: Print progress messages (default: false)
  #
  # Usage: nix build .#deployTerminalContainer && ./result/bin/deployContainers
  deployTerminalContainer =
    { name, verbose ? false, repo, tags ? [ "latest" ], ... }@opts:
    let
      # Generate push commands for each tag
      containerPushScript = concatStringsSep "\n" (map (tag:
        let container = makeTerminalContainer (opts // { inherit tag; });
        in concatStringsSep "\n"
        ((optional verbose ''echo "pushing ${name} -> ${repo}/${name}:${tag}"'')
          ++ [
            ''
              skopeo copy --policy ${policyJson} docker-archive:"${container}" "docker://${repo}/${name}:${tag}"''
          ])) tags);

      # Policy that accepts any image (required for local builds)
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
        ${containerPushScript}
      '';
    };
}
