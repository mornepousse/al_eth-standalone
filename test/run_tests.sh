#!/bin/bash
# al_eth driver test suite — run on QNAP TS-431P hardware
# Usage: scp to NAS then: bash run_tests.sh [gateway_ip]

set -u
GW="${1:-192.168.1.1}"
IFACE="enp0s1"
PASS=0
FAIL=0
WARN=0

green()  { printf "\033[32m%s\033[0m\n" "$1"; }
red()    { printf "\033[31m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN+1)); }

echo "========================================"
echo " al_eth driver test suite"
echo " $(date)"
echo " Interface: $IFACE"
echo " Gateway:   $GW"
echo "========================================"
echo

# -----------------------------------------------
echo "--- 1. Module loaded ---"
if lsmod | grep -q al_eth; then
    pass "al_eth module loaded"
    modinfo al_eth 2>/dev/null | grep -E "^(version|srcversion|filename)" | while read l; do
        echo "       $l"
    done
else
    fail "al_eth module NOT loaded"
fi
echo

# -----------------------------------------------
echo "--- 2. Interface exists and UP ---"
if ip link show "$IFACE" &>/dev/null; then
    STATE=$(ip link show "$IFACE" | grep -o "state [A-Z]*" | awk '{print $2}')
    if [ "$STATE" = "UP" ]; then
        pass "$IFACE is UP"
    else
        fail "$IFACE state is $STATE (expected UP)"
    fi
    FLAGS=$(ip link show "$IFACE" | head -1)
    echo "       $FLAGS"
else
    fail "$IFACE does not exist"
fi
echo

# -----------------------------------------------
echo "--- 3. Link speed ---"
if command -v ethtool &>/dev/null; then
    SPEED=$(ethtool "$IFACE" 2>/dev/null | grep "Speed:" | awk '{print $2}')
    if [ -n "$SPEED" ]; then
        if [ "$SPEED" = "1000Mb/s" ]; then
            pass "Link speed: $SPEED"
        else
            warn "Link speed: $SPEED (expected 1000Mb/s)"
        fi
    else
        warn "Could not read link speed"
    fi
    DUPLEX=$(ethtool "$IFACE" 2>/dev/null | grep "Duplex:" | awk '{print $2}')
    if [ "$DUPLEX" = "Full" ]; then
        pass "Duplex: $DUPLEX"
    else
        warn "Duplex: $DUPLEX (expected Full)"
    fi
else
    warn "ethtool not installed, skipping link checks"
fi
echo

# -----------------------------------------------
echo "--- 4. IP configuration ---"
IPV4=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP 'inet \K[0-9./]+')
if [ -n "$IPV4" ]; then
    pass "IPv4 address: $IPV4"
else
    fail "No IPv4 address on $IFACE"
fi
echo

# -----------------------------------------------
echo "--- 5. Ping gateway ---"
if ping -c3 -W2 "$GW" &>/dev/null; then
    RTT=$(ping -c3 -W2 "$GW" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    pass "Ping $GW OK (avg ${RTT}ms)"
else
    fail "Cannot ping gateway $GW"
fi
echo

# -----------------------------------------------
echo "--- 6. ARP resolution ---"
ARP_COUNT=$(arp -n 2>/dev/null | grep "$IFACE" | grep -v incomplete | wc -l)
ARP_FAIL=$(arp -n 2>/dev/null | grep "$IFACE" | grep incomplete | wc -l)
if [ "$ARP_COUNT" -gt 0 ]; then
    pass "ARP: $ARP_COUNT entries resolved"
else
    warn "ARP: no entries resolved"
fi
if [ "$ARP_FAIL" -gt 0 ]; then
    warn "ARP: $ARP_FAIL incomplete entries"
fi
echo

# -----------------------------------------------
echo "--- 7. Interrupts (MSI-X per queue) ---"
IRQ_LINES=$(grep al-eth /proc/interrupts 2>/dev/null)
if [ -n "$IRQ_LINES" ]; then
    QUEUES=$(echo "$IRQ_LINES" | grep -c "rx-comp")
    pass "MSI-X active, $QUEUES RX queues"
    echo "$IRQ_LINES" | while read l; do
        echo "       $l"
    done
else
    fail "No al-eth interrupts found"
fi
echo

# -----------------------------------------------
echo "--- 8. TX/RX counters ---"
read_counters() {
    grep "$IFACE" /proc/net/dev | awk '{print $2,$3,$4,$5,$10,$11,$12,$13}'
}
C1=$(read_counters)
RX_BYTES1=$(echo $C1 | awk '{print $1}')
TX_BYTES1=$(echo $C1 | awk '{print $5}')
RX_ERR1=$(echo $C1 | awk '{print $3}')
TX_ERR1=$(echo $C1 | awk '{print $7}')
RX_DROP1=$(echo $C1 | awk '{print $4}')
TX_DROP1=$(echo $C1 | awk '{print $8}')

if [ "$RX_BYTES1" -gt 0 ] && [ "$TX_BYTES1" -gt 0 ]; then
    pass "Counters active (RX: ${RX_BYTES1}B, TX: ${TX_BYTES1}B)"
else
    warn "Low counters (RX: ${RX_BYTES1}B, TX: ${TX_BYTES1}B)"
fi
if [ "$RX_ERR1" -gt 0 ]; then
    fail "RX errors: $RX_ERR1"
else
    pass "RX errors: 0"
fi
if [ "$TX_ERR1" -gt 0 ]; then
    fail "TX errors: $TX_ERR1"
else
    pass "TX errors: 0"
fi
if [ "$RX_DROP1" -gt 0 ]; then
    warn "RX drops: $RX_DROP1"
else
    pass "RX drops: 0"
fi
if [ "$TX_DROP1" -gt 0 ]; then
    warn "TX drops: $TX_DROP1"
else
    pass "TX drops: 0"
fi
echo

# -----------------------------------------------
echo "--- 9. Ethtool driver stats ---"
if command -v ethtool &>/dev/null; then
    ERRS=$(ethtool -S "$IFACE" 2>/dev/null | grep -iE "err|drop|fail|discard" | grep -v ": 0$")
    if [ -z "$ERRS" ]; then
        pass "No errors in ethtool stats"
    else
        warn "Ethtool stats with non-zero errors:"
        echo "$ERRS" | while read l; do
            echo "       $l"
        done
    fi
else
    warn "ethtool not installed"
fi
echo

# -----------------------------------------------
echo "--- 10. Coalescing settings ---"
if command -v ethtool &>/dev/null; then
    COAL=$(ethtool -c "$IFACE" 2>/dev/null)
    RX_USECS=$(echo "$COAL" | grep "^rx-usecs:" | awk '{print $2}')
    TX_USECS=$(echo "$COAL" | grep "^tx-usecs:" | awk '{print $2}')
    ADAPTIVE=$(echo "$COAL" | grep "Adaptive RX" | awk '{print $3}')
    if [ "$RX_USECS" = "64" ]; then
        pass "RX coalescing: ${RX_USECS}us"
    else
        warn "RX coalescing: ${RX_USECS}us (expected 64)"
    fi
    if [ "$TX_USECS" = "64" ]; then
        pass "TX coalescing: ${TX_USECS}us"
    else
        warn "TX coalescing: ${TX_USECS}us (expected 64)"
    fi
    if [ "$ADAPTIVE" = "off" ]; then
        pass "Adaptive moderation: off"
    else
        warn "Adaptive moderation: $ADAPTIVE (expected off)"
    fi
else
    warn "ethtool not installed"
fi
echo

# -----------------------------------------------
echo "--- 11. Offloads ---"
if command -v ethtool &>/dev/null; then
    FEATS=$(ethtool -k "$IFACE" 2>/dev/null)
    for F in tx-checksumming rx-checksumming scatter-gather tcp-segmentation-offload generic-receive-offload; do
        VAL=$(echo "$FEATS" | grep "^${F}:" | awk '{print $2}')
        if [ "$VAL" = "on" ]; then
            pass "Offload $F: on"
        else
            warn "Offload $F: $VAL"
        fi
    done
else
    warn "ethtool not installed"
fi
echo

# -----------------------------------------------
echo "--- 12. Sustained traffic (10s ping flood) ---"
BEFORE_RX=$(grep "$IFACE" /proc/net/dev | awk '{print $2}')
BEFORE_TX=$(grep "$IFACE" /proc/net/dev | awk '{print $10}')
PING_OUT=$(ping -f -c 1000 -W1 "$GW" 2>&1 | tail -2)
AFTER_RX=$(grep "$IFACE" /proc/net/dev | awk '{print $2}')
AFTER_TX=$(grep "$IFACE" /proc/net/dev | awk '{print $10}')
LOSS=$(echo "$PING_OUT" | grep -oP '\d+% packet loss' | grep -oP '\d+')
if [ -n "$LOSS" ] && [ "$LOSS" -lt 2 ]; then
    pass "Ping flood: ${LOSS}% loss"
else
    fail "Ping flood: ${LOSS:-unknown}% loss"
fi
DELTA_RX=$(( AFTER_RX - BEFORE_RX ))
DELTA_TX=$(( AFTER_TX - BEFORE_TX ))
echo "       Traffic: RX +${DELTA_RX}B, TX +${DELTA_TX}B"
echo "       $PING_OUT"
echo

# -----------------------------------------------
echo "--- 13. dmesg errors ---"
ETH_ERRS=$(dmesg 2>/dev/null | grep -iE "al_eth|enp0s1" | grep -iE "error|fail|warn|bug|oops" | tail -5)
if [ -z "$ETH_ERRS" ]; then
    pass "No driver errors in dmesg"
else
    fail "Driver errors in dmesg:"
    echo "$ETH_ERRS" | while read l; do
        echo "       $l"
    done
fi
echo

# -----------------------------------------------
echo "========================================"
echo " Results: $(green "$PASS PASS"), $(red "$FAIL FAIL"), $(yellow "$WARN WARN")"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
