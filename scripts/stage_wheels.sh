#!/usr/bin/env bash
# Download linux/x86_64 wheels for every package in app/requirements.txt and upload
# them to the ROOT of /Volumes/<catalog>/<schema>/py_libs/ so the deployed app can
# pip-install from there. The volume root is what `valueFrom: py_lib_volume` in
# app.yaml resolves to, which is then exposed as PIP_FIND_LINKS — so wheels MUST
# live at the volume root (not in a sub-directory) for the native-install pattern
# to work.
#
# Usage: ./scripts/stage_wheels.sh <catalog> <schema>
# Re-run whenever app/requirements.txt changes.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <catalog> <schema>" >&2
  exit 1
fi

CATALOG="$1"
SCHEMA="$2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="$REPO_ROOT/app/requirements.txt"

if [[ ! -f "$REQ_FILE" ]]; then
  echo "requirements.txt not found: $REQ_FILE" >&2
  exit 1
fi

# Skip pip directives, blanks, and comments — we only want package specifiers.
PKGS=$(grep -vE '^\s*(--|#|$)' "$REQ_FILE" || true)
if [[ -z "$PKGS" ]]; then
  echo "No packages found in $REQ_FILE" >&2
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

VOLUME_PATH="dbfs:/Volumes/$CATALOG/$SCHEMA/py_libs/"
PROFILE="${DATABRICKS_CONFIG_PROFILE:-fevm-classic-stable-2te8jp}"
echo "Uploading $(ls "$WHEEL_DIR" | wc -l | tr -d ' ') wheels to $VOLUME_PATH (profile=$PROFILE)"
databricks --profile "$PROFILE" fs cp -r --overwrite "$WHEEL_DIR/" "$VOLUME_PATH"

echo "Done."
