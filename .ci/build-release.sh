#!/usr/bin/env bash
set -euo pipefail

KEY_PATH="${KEY_PATH:-/key/developer_key.der}"
MANIFEST="${MANIFEST:-manifest.xml}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"

if [[ ! -f "${KEY_PATH}" ]]; then
    echo "Developer key not found at ${KEY_PATH}" >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

mapfile -t devices < <(grep -o 'iq:product id="[^"]*"' "${MANIFEST}" | cut -d'"' -f2)

printf '%s\n' "${devices[@]}" > "${OUTPUT_DIR}/devices.txt"

for device in "${devices[@]}"; do
    echo "Building ${device}..."
    monkeyc -f monkey.jungle -y "${KEY_PATH}" \
        -d "${device}" -o "${OUTPUT_DIR}/SensorBattery_${device}.prg" -r -O3pz -w
done

echo "Built ${#devices[@]} release binaries in ${OUTPUT_DIR}/"
