#!/usr/bin/env bash
set -euo pipefail

actual="${1:-}"
snapshot="${2:-}"

if [[ -z "$actual" || -z "$snapshot" ]]; then
  echo "usage: compare-snapshots.sh <actual> <snapshot>"
  exit 2
fi

if [[ ! -f "$actual" ]]; then
  echo "actual snapshot not found: $actual"
  exit 1
fi

if [[ ! -f "$snapshot" ]]; then
  if [[ "${COG_UPDATE_SNAPSHOTS:-}" == "1" ]]; then
    mkdir -p "$(dirname "$snapshot")"
    cp "$actual" "$snapshot"
    echo "snapshot created: $snapshot"
    exit 0
  fi
  echo "snapshot missing: $snapshot (set COG_UPDATE_SNAPSHOTS=1 to create)"
  exit 1
fi

if ! diff -u "$snapshot" "$actual"; then
  echo "snapshot mismatch: $snapshot"
  if [[ "${COG_UPDATE_SNAPSHOTS:-}" == "1" ]]; then
    cp "$actual" "$snapshot"
    echo "snapshot updated: $snapshot"
    exit 0
  fi
  exit 1
fi
