#!/usr/bin/env bash
set -euo pipefail

ADAPTER_DIR="$HOME/.opencli/clis/linkedin"
SOURCE_DIR="$(cd "$(dirname "$0")/adapters" && pwd)"

mkdir -p "$ADAPTER_DIR"

for yaml in "$SOURCE_DIR"/*.yaml; do
  [ -f "$yaml" ] || continue
  name=$(basename "$yaml")
  # Skip built-in adapters
  if [[ "$name" == "search.yaml" || "$name" == "timeline.yaml" ]]; then
    echo "SKIP $name (built-in)"
    continue
  fi
  ln -sf "$yaml" "$ADAPTER_DIR/$name"
  echo "LINK $name → $ADAPTER_DIR/$name"
done

echo "Done. Run 'opencli linkedin --help' to see all commands."
