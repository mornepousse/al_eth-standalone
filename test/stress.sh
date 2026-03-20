#!/bin/bash
# al_eth stability test — run on QNAP TS-431P
# Verifies network stays up over time
# Usage: bash stress.sh [gateway_ip] [duration_minutes]

set -u
GW="${1:-192.168.1.1}"
MINS="${2:-10}"
IFACE="enp0s1"
INTERVAL=30
TOTAL=$((MINS * 60 / INTERVAL))
FAILURES=0

echo "========================================"
echo " al_eth stability test"
echo " $(date)"
echo " Gateway:  $GW"
echo " Duration: ${MINS} minutes"
echo " Check every ${INTERVAL}s ($TOTAL checks)"
echo "========================================"
echo

# Initial state
echo "--- Initial state ---"
grep "$IFACE" /proc/net/dev
grep "al-eth" /proc/interrupts
echo

for i in $(seq 1 $TOTAL); do
    TS=$(date +%H:%M:%S)
    PING=$(ping -c1 -W2 "$GW" 2>&1)

    if echo "$PING" | grep -q "1 received"; then
        RTT=$(echo "$PING" | grep "rtt" | awk -F'/' '{print $5}')
        printf "[%s] %3d/%d  PASS  rtt=%sms" "$TS" "$i" "$TOTAL" "$RTT"
    else
        FAILURES=$((FAILURES+1))
        printf "[%s] %3d/%d  FAIL  (%d total failures)" "$TS" "$i" "$TOTAL" "$FAILURES"
    fi

    # Check for new dmesg errors
    NEW_ERR=$(dmesg 2>/dev/null | grep -iE "al_eth|enp0s1" | grep -iE "error|fail|bug" | tail -1)
    if [ -n "$NEW_ERR" ]; then
        printf "  DMESG: %s" "$NEW_ERR"
    fi

    printf "\n"
    sleep "$INTERVAL"
done

echo
echo "--- Final state ---"
grep "$IFACE" /proc/net/dev
grep "al-eth" /proc/interrupts
echo

echo "========================================"
if [ "$FAILURES" -eq 0 ]; then
    echo " STABLE: 0 failures in $TOTAL checks over ${MINS} minutes"
else
    echo " UNSTABLE: $FAILURES failures in $TOTAL checks"
fi
echo "========================================"

exit "$FAILURES"
