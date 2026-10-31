#!/bin/zsh
# Builds a synthetic raw recording, runs the real comping code (poc-c6/Data/Composition)
# on the Mac and checks duration, cut accuracy, vocal sync, crossfades and partial export.
# Run before opening a PR that touches poc-c6/Data/Composition.
set -euo pipefail

ROOT="${0:A:h:h}"
WORK="$(mktemp -d)"

xcrun swiftc -D DEBUG \
  $(find "$ROOT/poc-c6/Domain" -name '*.swift') \
  $(find "$ROOT/poc-c6/Data/Composition" -name '*.swift') \
  "$ROOT/scripts/comping-check/main.swift" \
  -o "$WORK/comping-check"

"$WORK/comping-check" "$WORK"
