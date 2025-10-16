# Injector

`injector` is a small helper that rewrites `deps.edn` files so that selected
libraries resolve from local paths during a Nix build.  It is primarily used by
`clj-nix` through the `cljInject` wrapper exposed by this flake.

## Usage

```bash
nix run .#cljInject -- --deps-file path/to/deps.edn my.lib ./local/path
```

Each pair of positional arguments represents a library coordinate and the local
path to use.  The tool reads the provided deps file, updates all nested `:deps`
entries with `:local/root` overrides and prints the result to stdout.

## Implementation notes

The implementation lives in `src/injector/core.clj` and recursively walks the
`deps.edn` map to ensure every nested dependency map gets updated.  The
additional comments in the source explain the helper functions used to perform
this traversal.
