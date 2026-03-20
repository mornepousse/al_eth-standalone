al\_eth out-of-tree driver
==========================

`al_eth` is the driver for Amazon Annapurna Labs' Alpine NIC. Alpine SoCs are
used in a few consumer products, including some QNAP NAS appliances. This
driver source code was extracted from a Linux kernel source drop from QNAP.

This fork maintains compatibility with modern kernels and includes performance
tuning for the Alpine AL-212 SoC (dual Cortex-A15).

Tested hardware
---------------

* **QNAP TS-431P** (Alpine AL-212, 1GbE, Qualcomm Atheros AR8035 PHY)
* Kernel **6.12.77 LTS** (Debian Bookworm rootfs)

Changes from upstream
---------------------

### Kernel compatibility (>= 6.3)

* MDIO C22 read/write callbacks (`mdiobus_read` / `mdiobus_write` require them
  since 6.3)
* NAPI API updates for kernel 6.x

### Kernel compatibility (>= 6.12)

* Migrated `get_settings` / `set_settings` to `get_link_ksettings` /
  `set_link_ksettings` (old API removed in 6.12)
* Added `kernel_ethtool_coalesce` and `netlink_ext_ack` parameters to coalesce
  callbacks (required since 6.12)

### Performance tuning

* RX buffer size increased from 1536 to 2048 (aligned to standard MTU)
* Interrupt coalescing set to 64us for both RX and TX (reduces CPU load)
* Adaptive interrupt moderation disabled (fixed values, more predictable)
* RX/TX queue count auto-sized to match CPU count (avoids idle queues)
* TX completion uses `napi_consume_skb` (more efficient in NAPI context)
* TX stats accumulation fixed (moved counters outside per-packet loop)

### Performance results (QNAP TS-431P)

* Single stream: **~262 Mbps** (CPU-bound at ~94% on one Cortex-A15 core)
* Dual stream: **~275 Mbps** (shared bus/DMA saturation)
* All hardware offloads enabled (TSO, GSO, GRO, checksum, scatter-gather)
* Hardware limit — the AL-212 SoC bus is the bottleneck, not the driver

Building
--------

```bash
make -C /path/to/linux M=$(pwd)/src modules \
    ARCH=arm \
    CROSS_COMPILE=arm-linux-gnueabihf-
```

Testing
-------

A hardware test suite is included in `test/`:

```bash
# Deploy and run on target NAS
cd test
bash deploy_tests.sh 192.168.1.120 --run

# Or run individually on the NAS
bash run_tests.sh              # 13 functional checks
bash bench.sh 192.168.1.113    # iperf3 throughput benchmark
bash stress.sh                 # 10min stability test
```

TODO
----

* No 10Gbps support, or at least it's untested.
* Serdes driver should be split out into either an upstream-able module (in the
  Linux QNAP fork) or another out-of-tree module.
* Move some of the board specific stuff into DT (for example, clock/delay info
  currently hardcoded in a few places).
* Clean up coding style.
