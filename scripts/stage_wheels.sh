#!/usr/bin/env bash
# Download linux/x86_64 wheels for every package in requirements.txt.tpl
# and upload them to /Volumes/<catalog>/<schema>/py_libs/app/py_libs/
# so the deployed app can pip-install with --no-index --find-links pointing at that path.
#
# Usage: ./scripts/stage_wheels.sh <catalog> <schema>
# Re-run whenever requirements.txt.tpl gains or loses a package.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <catalog> <schema>" >&2
  exit 1
fi

CATALOG="$1"
SCHEMA="$2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$REPO_ROOT/requirements.txt.tpl"

if [[ ! -f "$TPL" ]]; then
  echo "Template not found: $TPL" >&2
  exit 1
fi

# Skip pip directives (lines starting with --), blanks, and comments.
PKGS=$(grep -vE '^\s*(--|#|$)' "$TPL" || true)
if [[ -z "$PKGS" ]]; then
  echo "No packages found in $TPL" >&2
  exit 1
fi

WHEEL_DIR="$(mktemp -d)"
trap 'rm -rf "$WHEEL_DIR"' EXIT

echo "Downloading wheels for: $(echo "$PKGS" | tr '\n' ' ')"
# shellcheck disable=SC2086
pip download $PKGS \
  --dest "$WHEEL_DIR" \
  --platform manylinux2014_x86_64 \
  --python-version 3.11 \
  --only-binary=:all:

VOLUME_PATH="dbfs:/Volumes/$CATALOG/$SCHEMA/py_libs/app/py_libs/"
echo "Uploading $(ls "$WHEEL_DIR" | wc -l | tr -d ' ') wheels to $VOLUME_PATH"
databricks fs cp -r --overwrite "$WHEEL_DIR/" "$VOLUME_PATH"

echo "Done."
