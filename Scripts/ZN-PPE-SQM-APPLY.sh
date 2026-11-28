#!/bin/sh
# SPDX-License-Identifier: MIT
#
# ZN-PPE-SQM-APPLY.sh
#
# ZN-M2-WIRED:
# Reapply Qualcomm PPE hardware QoS classifiers
# after SQM rebuilds WAN ingress.
#
# This script must never make SQM/Cake fail.

TAG="ZN-PPE-SQM"
SQM_DIR="/usr/lib/sqm"
PPE_INIT="/etc/init.d/qca-ppe-qos"

log() {
    logger -t "$TAG" "$*"
}

# 1. Check selected SQM script
if [ ! -s "$SQM_DIR/ZN-Layer-Cake.qos" ]; then
    log "ERROR: ZN-Layer-Cake.qos not found"
    exit 0
fi

# 2. Check PPE driver
if [ ! -d /sys/bus/platform/drivers/qca-ppe ] &&
   [ ! -d /sys/bus/platform/drivers/qcom_ppe ]; then
    exit 0
fi

# 3. Check PPE QoS service
[ -x "$PPE_INIT" ] || exit 0

"$PPE_INIT" enabled >/dev/null 2>&1 || exit 0

# 4. Reapply PPE classifiers
if "$PPE_INIT" reload; then
    log "PPE QoS successfully reapplied after SQM ingress setup"
    exit 0
fi

log "WARNING: PPE QoS reload failed; SQM/Cake remains running"

# PPE failure must not stop SQM/Cake.
exit 0
