#!/usr/bin/env bash
# Substitute __CATALOG__/__SCHEMA__ placeholders in requirements.txt.tpl
# and write the result to app/requirements.txt (which DAB will sync to the workspace).
#
# Usage: ./scripts/build_requirements.sh <catalog> <schema>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <catalog> <schema>" >&2
  exit 1
fi

CATALOG="$1"
SCHEMA="$2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$REPO_ROOT/requirements.txt.tpl"
OUT="$REPO_ROOT/app/requirements.txt"

if [[ ! -f "$TPL" ]]; then
  echo "Template not found: $TPL" >&2
  exit 1
fi

sed -e "s|__CATALOG__|$CATALOG|g" -e "s|__SCHEMA__|$SCHEMA|g" "$TPL" > "$OUT"
echo "Wrote $OUT (catalog=$CATALOG, schema=$SCHEMA)"
