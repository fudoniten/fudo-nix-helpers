#!/usr/bin/env bash
# Update deps-lock.json files for lib/injector and lib/build-injector
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Updating deps-lock.json for lib/injector..."
cd "$SCRIPT_DIR/lib/injector"
nix run "$SCRIPT_DIR#updateClojureDeps" -- deps.edn

echo ""
echo "Updating deps-lock.json for lib/build-injector..."
cd "$SCRIPT_DIR/lib/build-injector"
nix run "$SCRIPT_DIR#updateClojureDeps" -- deps.edn

echo ""
echo "Done! Updated:"
echo "  - lib/injector/deps-lock.json"
echo "  - lib/build-injector/deps-lock.json"
