# Build Injector

`build-injector` augments a `deps.edn` file with extra configuration for
`tools.build`.  It is used by the Nix helpers to ensure the build alias has the
correct namespace and dependencies before invoking the build pipeline.

## Usage

```bash
nix run .#cljBuildInject -- --deps-file path/to/deps.edn --build-namespace build.ns io.github.clojure/tools.build 0.10.6
```

Just like the standard injector, positional arguments are interpreted as
library/version pairs that should be added under the `:aliases :build :deps`
section.  The `--build-namespace` flag controls the namespace where build tasks
are looked up.

## Implementation notes

The CLI lives in `src/build_injector/cli.clj` and delegates to helper functions
in `core.clj` that handle updating nested maps.  The new docstrings describe how
those helpers normalise command line input and ensure the `:aliases :build`
structure exists.
