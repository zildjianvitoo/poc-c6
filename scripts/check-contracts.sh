#!/bin/zsh
# Compiles the Domain contracts + scripts/contract-check on the Mac and runs the checks.
# Run before opening a PR that touches poc-c6/Domain.
set -euo pipefail

ROOT="${0:A:h:h}"
OUT="$(mktemp -d)/contract-check"

xcrun swiftc -D DEBUG \
  $(find "$ROOT/poc-c6/Domain" -name '*.swift') \
  "$ROOT/scripts/contract-check/main.swift" \
  -o "$OUT"

"$OUT"
