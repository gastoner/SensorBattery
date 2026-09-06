#!/usr/bin/env bash
set -euo pipefail

DEVICE="${DEVICE:-fenix847mm}"

openssl genrsa 4096 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -outform DER -out /tmp/ci_key.der
mkdir -p bin

monkeyc -f monkey.jungle -o "bin/ci-${DEVICE}.prg" \
    -d "${DEVICE}" -y /tmp/ci_key.der -O3pz -w

echo "Built bin/ci-${DEVICE}.prg"
