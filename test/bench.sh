#!/bin/bash
# al_eth performance benchmark — run on QNAP TS-431P
# Requires: iperf3 server running on remote host
# Usage: bash bench.sh <server_ip> [duration]

set -u
SERVER="${1:?Usage: bench.sh <iperf3_server_ip> [duration_secs]}"
DURATION="${2:-30}"
IFACE="enp0s1"

echo "========================================"
echo " al_eth performance benchmark"
echo " $(date)"
echo " Server:   $SERVER"
echo " Duration: ${DURATION}s per test"
echo "========================================"
echo

if ! command -v iperf3 &>/dev/null; then
    echo "ERROR: iperf3 not installed (apt install iperf3)"
    exit 1
fi

# Snapshot before
IRQ_BEFORE=$(grep "rx-comp" /proc/interrupts 2>/dev/null)
CPU_IFACE=$(grep "$IFACE" /proc/net/dev | awk '{print $2,$3,$10,$11}')

echo "--- 1. Single stream TX (NAS -> Server) ---"
iperf3 -c "$SERVER" -t "$DURATION" -P 1 2>&1 | tail -4
echo

echo "--- 2. Single stream RX (Server -> NAS) ---"
iperf3 -c "$SERVER" -t "$DURATION" -P 1 -R 2>&1 | tail -4
echo

echo "--- 3. Dual stream TX ---"
iperf3 -c "$SERVER" -t "$DURATION" -P 2 2>&1 | tail -4
echo

echo "--- 4. Dual stream RX ---"
iperf3 -c "$SERVER" -t "$DURATION" -P 2 -R 2>&1 | tail -4
echo

# Snapshot after
IRQ_AFTER=$(grep "rx-comp" /proc/interrupts 2>/dev/null)

echo "--- IRQ distribution ---"
echo "Before:"
echo "$IRQ_BEFORE" | while read l; do echo "  $l"; done
echo "After:"
echo "$IRQ_AFTER" | while read l; do echo "  $l"; done
echo

echo "--- Counters ---"
grep "$IFACE" /proc/net/dev
echo

echo "--- CPU during test ---"
echo "(check htop manually for CPU bottleneck)"
echo

echo "Done."
