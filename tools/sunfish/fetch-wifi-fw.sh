#!/bin/bash
# Fetch WCN3990 firmware + sunfish board-2 for sweetwifi stages ≥3.
# Does NOT commit blobs; writes under OUT (default: ./wifi-fw/).
#
#   tools/sunfish/fetch-wifi-fw.sh [OUT_DIR]
#
# Sources (community / linux-firmware; verify licenses before redistributing):
#   - ath10k/WCN3990/hw1.0/firmware-5.bin  (linux-firmware)
#   - board-2.bin with google_sunfish variant (sm7150-mainline ath10k firmware)
set -euo pipefail
OUT=${1:-wifi-fw}
mkdir -p "$OUT/ath10k/WCN3990/hw1.0"
cd "$OUT"

FW5_URL=${FW5_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/WCN3990/hw1.0/firmware-5.bin}
BOARD_URL=${BOARD_URL:-https://github.com/sm7150-mainline/firmware-qcom-sm7150-ath10k/raw/master/board-2.bin}

echo "Fetching firmware-5.bin ..."
curl -fsSL -o ath10k/WCN3990/hw1.0/firmware-5.bin "$FW5_URL"
echo "Fetching board-2.bin (expect google_sunfish variant) ..."
curl -fsSL -o ath10k/WCN3990/hw1.0/board-2.bin "$BOARD_URL"

ls -lah ath10k/WCN3990/hw1.0/
# board-2.bin is an ATH10K board container; a real check needs ath10k-bdencoder.
# At least require non-trivial size (sunfish board-2 is hundreds of KiB).
sz=$(wc -c < ath10k/WCN3990/hw1.0/board-2.bin)
if [[ "$sz" -lt 100000 ]]; then
  echo "warning: board-2.bin looks too small ($sz bytes); check BOARD_URL" >&2
fi
echo "Done. Copy these onto the iOS root (e.g. /private/var/sweet/wifi/) or pass as payload blobs."
echo "Do not commit this directory."
