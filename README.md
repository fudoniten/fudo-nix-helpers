# fudo-nix-helpers

A collection of reusable Nix helpers for building Clojure libraries, CLI applications, and container images. This flake provides high-level wrappers around [clj-nix](https://github.com/jlesquembre/clj-nix) with automatic dependency injection to support local Clojure libraries without uploading to Maven.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Clojure Helpers](#clojure-helpers)
  - [mkClojureLib](#mkclojurelib)
  - [mkClojureBin](#mkclojurebin)
  - [Using Local Dependencies](#using-local-dependencies)
  - [Custom Build Scripts](#custom-build-scripts)
- [Dependency Management](#dependency-management)
  - [How It Works](#how-it-works)
  - [Updating Dependencies](#updating-dependencies)
  - [Synchronizing Git Dependencies](#synchronizing-git-dependencies)
- [Container Helpers](#container-helpers)
  - [makeContainer](#makecontainer)
  - [deployContainers](#deploycontainers)
- [Ruby Helper](#ruby-helper)
- [Repository Layout](#repository-layout)
- [Troubleshooting](#troubleshooting)

## Overview

This flake solves a common pain point when using Clojure with Nix: **using local Clojure libraries as dependencies without uploading them to Maven**.

The standard `tools.deps` workflow assumes network access to Maven Central or Clojars, which doesn't work well in Nix's pure build environment. This flake provides dependency injection tools that rewrite `deps.edn` at build time, replacing Maven coordinates with `:local/root` paths pointing to Nix store locations.

## Quick Start

### Using as a Flake Input

Add this flake to your project's `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    fudo-nix-helpers.url = "github:fudoniten/fudo-nix-helpers";
  };

  outputs = { self, nixpkgs, fudo-nix-helpers, ... }:
    let
      system = "x86_64-linux";
      helpers = fudo-nix-helpers.packages.${system};
    in {
      packages.${system}.default = helpers.mkClojureBin {
        name = "my-app";
        src = ./.;
        primaryNamespace = "my.app.core";
        version = "1.0.0";
      };
    };
}
```

### Building a Simple Library

```nix
helpers.mkClojureLib {
  name = "my-library";
  src = ./.;
  version = "1.0.0";
}
```

### Building a CLI Application

```nix
helpers.mkClojureBin {
  name = "my-cli";
  src = ./.;
  primaryNamespace = "my.cli.main";  # Namespace with -main function
  version = "1.0.0";
}
```

## Clojure Helpers

### mkClojureLib

Builds a Clojure library JAR file.

#### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Library name (used in JAR filename) |
| `src` | Yes | - | Path to source directory containing `deps.edn` |
| `version` | No | `"0.1"` | Version string |
| `clojure-src-dirs` | No | `["src"]` | List of Clojure source directories |
| `java-src-dirs` | No | `[]` | List of Java source directories (compiled to Java 16 bytecode) |
| `cljLibs` | No | `{}` | Map of local Clojure library dependencies (see below) |
| `buildCommand` | No | auto-generated | Custom build command override |
| `checkPhase` | No | `null` | Custom check/test phase |

#### Example

```nix
helpers.mkClojureLib {
  name = "my-utils";
  src = ./utils;
  version = "2.0.0";
  clojure-src-dirs = [ "src/clj" ];
  java-src-dirs = [ "src/java" ];
}
```

### mkClojureBin

Builds a runnable Clojure CLI application (uberjar with launcher script).

#### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | Yes | - | Application name |
| `src` | Yes | - | Path to source directory containing `deps.edn` |
| `primaryNamespace` | Yes | - | Namespace containing `-main` function |
| `version` | No | `"0.1"` | Version string |
| `cljLibs` | No | `{}` | Map of local Clojure library dependencies |
| `buildCommand` | No | `null` | Custom build command override |
| `checkPhase` | No | `null` | Custom check/test phase |

#### Example

```nix
helpers.mkClojureBin {
  name = "my-server";
  src = ./server;
  primaryNamespace = "my.server.main";
  version = "1.0.0";
  cljLibs = {
    "org.fudo/my-utils" = myUtilsLib;  # Reference to another mkClojureLib output
  };
}
```

### Using Local Dependencies

The `cljLibs` parameter allows you to specify local Clojure libraries as dependencies. This is the key feature that enables using your own libraries without Maven.

```nix
let
  # Build the library first
  myLib = helpers.mkClojureLib {
    name = "my-lib";
    src = ./lib;
    version = "1.0.0";
  };
in helpers.mkClojureBin {
  name = "my-app";
  src = ./app;
  primaryNamespace = "my.app.main";
  cljLibs = {
    # Key: Maven coordinate as it appears in deps.edn
    # Value: The Nix derivation (JAR file)
    "org.myorg/my-lib" = myLib;
  };
}
```

Your `deps.edn` should reference the dependency normally:

```clojure
{:deps {org.myorg/my-lib {:mvn/version "1.0.0"}}}
```

At build time, the dependency injection tools will replace this with a `:local/root` pointing to the JAR in the Nix store.

### Custom Build Scripts

By default, projects use a shared `build.clj` from this repository. If your project needs custom build logic, create a `build.clj` in your project root and it will be used automatically.

The default build script supports:
- Clojure compilation
- Java compilation (to Java 16 bytecode)
- JAR and uberjar creation
- POM file generation

## Dependency Management

### How It Works

The build process uses two injection tools:

1. **injector** (`lib/injector/`): Replaces Maven dependencies with `:local/root` paths
2. **build-injector** (`lib/build-injector/`): Adds the `:build` alias with `tools.build` configuration

The workflow is:
1. Read your `deps.edn`
2. Run `injector` to replace specified dependencies with local paths
3. Run `build-injector` to add build configuration
4. Pass the modified source to `clj-nix` for building

### Updating Dependencies

After modifying your `deps.edn`, regenerate the lockfile:

```bash
# From your project directory
nix run github:fudoniten/fudo-nix-helpers#updateClojureDeps

# Or with a specific deps file
nix run github:fudoniten/fudo-nix-helpers#updateClojureDeps -- ./path/to/deps.edn
```

This will:
1. Apply dependency injections
2. Run `deps-lock` to resolve all dependencies
3. Write `deps-lock.json` to your project

**Important**: Your project must have a `deps-lock.json` file for builds to work.

### Synchronizing Git Dependencies

If your project uses Git dependencies (`:git/url` and `:git/sha` in `deps.edn`) that are also declared as Flake inputs, you can automatically synchronize them to use the latest commits:

```bash
# Update all Git dependencies to latest commits and update lock files
nix run github:fudoniten/fudo-nix-helpers#update-git-deps

# Preview what would be updated without making changes
nix run github:fudoniten/fudo-nix-helpers#update-git-deps -- --dry-run

# Pin a specific library to a specific commit
nix run github:fudoniten/fudo-nix-helpers#update-git-deps -- --override owner/repo=abc123...

# Update without automatically regenerating lock files
nix run github:fudoniten/fudo-nix-helpers#update-git-deps-no-locks
```

This tool:
1. Finds all `:git/url` and `:git/sha` entries in your `deps.edn`
2. Fetches the latest commit SHA for each repository
3. Updates `deps.edn` with the new SHAs
4. Matches Git dependencies to Flake inputs and updates `flake.nix` to pin the same commits
5. Optionally runs `nix flake lock` and `updateClojureDeps` to update lock files

#### Example Workflow

Your `deps.edn` has a Git dependency:

```clojure
{:deps {com.github.myuser/my-lib {:git/url "https://github.com/myuser/my-lib"
                                  :git/sha "abc123..."}}}
```

Your `flake.nix` declares the same repository as an input:

```nix
{
  inputs = {
    my-lib = {
      url = "github:myuser/my-lib";
      flake = false;
    };
  };
}
```

Running `update-git-deps` will:
- Fetch the latest commit from `github.com/myuser/my-lib`
- Update the `:git/sha` in `deps.edn`
- Update the flake input URL to `github:myuser/my-lib/new-commit-sha`
- Update `flake.lock` and `deps-lock.json` to pin the new version

#### Options

```bash
update-git-deps [OPTIONS]

Options:
  --deps-file FILE       Path to deps.edn (default: deps.edn)
  --flake-file FILE      Path to flake.nix (default: flake.nix)
  --update-locks         Run nix flake lock and updateClojureDeps after updating
  --override LIB=SHA     Pin a specific library to a specific commit
                         Format: github-owner/repo=abc123...
                         Can be specified multiple times
  --dry-run              Show what would be updated without making changes
  --help                 Show help message
```

### Running Injectors Directly

For debugging or manual use:

```bash
# Inject local dependencies
nix run .#cljInject -- --deps-file deps.edn org.myorg/my-lib /nix/store/xxx-my-lib.jar

# Inject build configuration
nix run .#cljBuildInject -- --deps-file deps.edn --build-namespace build io.github.clojure/tools.build 0.10.6
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
├── flake.nix                 # Main entry point
├── flake.lock                # Locked dependencies
├── README.md                 # This file
│
├── clojure-helpers.nix       # Shared Clojure source preparation
├── clojure-lib.nix           # Library builder
├── clojure-bin.nix           # Binary/CLI builder
├── write-ruby-application.nix # Ruby script packager
│
└── lib/
    ├── build.clj             # Default Clojure build script
    ├── injector/             # Dependency injection tool
    │   ├── README.md
    │   ├── package.nix
    │   ├── deps.edn
    │   ├── deps-lock.json
    │   └── src/injector/
    │       ├── cli.clj
    │       └── core.clj
    └── build-injector/       # Build config injection tool
        ├── README.md
        ├── package.nix
        ├── deps.edn
        ├── deps-lock.json
        └── src/build_injector/
            ├── cli.clj
            └── core.clj
```

## Troubleshooting

### "Missing deps-lock.json"

Run `updateClojureDeps` to generate the lockfile:

```bash
nix run github:fudoniten/fudo-nix-helpers#updateClojureDeps
```

### "Dependency not found" during build

Ensure the Maven coordinate in `cljLibs` exactly matches what's in your `deps.edn`:

```nix
# deps.edn has: org.myorg/my-lib {:mvn/version "1.0.0"}
cljLibs = {
  "org.myorg/my-lib" = myLibDerivation;  # Must match exactly
};
```

### Custom build.clj not being used

Ensure your `build.clj` is in the root of your `src` directory (same level as `deps.edn`).

### Container won't start

Check that:
1. The entrypoint is an absolute path to an executable
2. Required environment variables are set
3. The user has permissions to access mounted volumes

### Java compilation errors

The default build script compiles to Java 16. If you need a different version, provide a custom `build.clj` with modified javac options.
