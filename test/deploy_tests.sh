#!/bin/bash
# Deploy test suite to NAS and optionally run
# Usage: bash deploy_tests.sh [nas_ip] [--run]

set -eu
NAS="${1:-192.168.1.120}"
RUN="${2:-}"

echo "Deploying test suite to root@${NAS}:/root/al_eth_tests/"
scp -o ConnectTimeout=5 \
    run_tests.sh bench.sh stress.sh \
    "root@${NAS}:/root/al_eth_tests/" 2>/dev/null || {
        # Create dir first
        ssh -o ConnectTimeout=5 "root@${NAS}" "mkdir -p /root/al_eth_tests"
        scp run_tests.sh bench.sh stress.sh "root@${NAS}:/root/al_eth_tests/"
    }

echo "Done. On the NAS run:"
echo "  cd /root/al_eth_tests"
echo "  bash run_tests.sh              # functional tests"
echo "  bash bench.sh 192.168.1.113    # iperf3 benchmark"
echo "  bash stress.sh                 # 10min stability"

if [ "$RUN" = "--run" ]; then
    echo
    echo "Running functional tests..."
    ssh -o ConnectTimeout=5 "root@${NAS}" "bash /root/al_eth_tests/run_tests.sh"
fi
