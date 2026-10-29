# fudo-nix-helpers

A collection of reusable Nix helpers for building container images, plus a small Ruby packaging helper.

The Clojure build helpers (`mkClojureLib`, `mkClojureBin`, `mkClojureTests`, `updateClojureDeps`, `update-git-deps`, `cljInject`, ...) now live in [nix-clj-helpers](https://github.com/fudoniten/nix-clj-helpers). This flake takes it as an input and re-exports everything under the same names, so existing flakes keep working unchanged; see that repository for their documentation. New Clojure projects can depend on nix-clj-helpers directly.

## Using as a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    fudo-nix-helpers = {
      url = "github:fudoniten/fudo-nix-helpers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, fudo-nix-helpers, ... }:
    let
      system = "x86_64-linux";
      # Builder functions live in legacyPackages; `packages` only holds
      # derivations (flake check rejects functions there).
      helpers = fudo-nix-helpers.legacyPackages.${system};
    in {
      packages.${system}.deploy = helpers.deployContainers {
        name = "my-service";
        repo = "registry.example.com";
        entrypoint = [ "${myApp}/bin/my-app" ];
      };
    };
}
```

## Container Helpers

### makeContainer

Creates a Docker-compatible container image using `dockerTools.buildLayeredImage`.

#### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Container name |
| `repo` | Yes | - | Container registry/repository (e.g., `"docker.io/myuser"`) |
| `tag` | Yes | - | Image tag |
| `entrypoint` | Yes | - | Entrypoint command (string or list) |
| `user` | No | `"executor"` | Username for the container process |
| `env` | No | `{}` | Environment variables (attrs or list) |
| `environmentPackages` | No | `[]` | Additional packages to include |
| `pathEnv` | No | `[]` | Packages to add to PATH |
| `exposedPorts` | No | `[]` | Ports to expose (see below) |
| `volumes` | No | `[]` | Volume mount points |

#### Port Formats

Ports can be specified in multiple formats:

```nix
exposedPorts = [
  8080              # Integer: becomes "8080/tcp"
  "9090/udp"        # String: used as-is
  { port = 443; type = "tcp"; }  # Object: explicit port and protocol
];
```

#### Example

```nix
helpers.makeContainer {
  name = "my-service";
  repo = "docker.io/myuser";
  tag = "v1.0.0";
  entrypoint = "${myApp}/bin/my-app";
  env = {
    DATABASE_URL = "postgres://localhost/mydb";
    LOG_LEVEL = "info";
  };
  exposedPorts = [ 8080 ];
  volumes = [ "/data" ];
  pathEnv = [ pkgs.postgresql ];
}
```

#### Included Base Packages

All containers include:
- `bashInteractive` - Shell access
- `coreutils` - Basic Unix utilities
- `dnsutils` - DNS resolution
- `cacert` - SSL/TLS certificates
- `glibc`, `glibcLocalesUtf8` - Locale support
- `nss` - Name service switch
- `tzdata` - Timezone data

#### Container Configuration

Containers are automatically configured with:
- Non-root user (UID 1000) for security
- Working directory at `/var/lib/{user}`
- SSL certificates for HTTPS
- UTF-8 locale (`C.UTF-8`)
- UTC timezone

### deployContainers

Creates a script to push container images to a registry using `skopeo`.

#### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Container name |
| `repo` | Yes | - | Target registry |
| `tags` | No | `["latest"]` | List of tags to push |
| `verbose` | No | `false` | Print progress messages |
| (other) | - | - | All `makeContainer` parameters |

#### Example

```nix
helpers.deployContainers {
  name = "my-service";
  repo = "docker.io/myuser";
  tags = [ "latest" "v1.0.0" ];
  verbose = true;
  entrypoint = "${myApp}/bin/my-app";
}
```

Run the deployment:

```bash
nix run .#deploy-my-service
```

## Ruby Helper

The `writeRubyApplication` function creates packaged Ruby scripts.

```nix
fudo-nix-helpers.lib.writeRubyApplication {
  name = "my-script";
  pkgs = pkgs;
  text = ''
    puts "Hello from Ruby!"
  '';
  runtimeInputs = [ pkgs.curl ];  # Added to PATH
  libInputs = [ ./lib ];           # Added to RUBYLIB
}
```

## Repository Layout

```
fudo-nix-helpers/
├── flake.nix                      # Entry point; re-exports nix-clj-helpers
├── container-helpers.nix          # makeContainer, deployContainers
├── terminal-container-helpers.nix # makeTerminalContainer, deployTerminalContainer
└── write-ruby-application.nix     # Ruby script packager
```

## Troubleshooting

### Container won't start

Check that:
1. The entrypoint is an absolute path to an executable
2. Required environment variables are set
3. The user has permissions to access mounted volumes
