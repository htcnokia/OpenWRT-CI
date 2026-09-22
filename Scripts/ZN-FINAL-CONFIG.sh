#!/bin/bash
# ZN-M2 final config
# Must run after make defconfig

set -Eeuo pipefail

if [ "${WRT_CONFIG:-}" != "ZN-M2-WIRED" ]; then
    exit 0
fi

echo "=== ZN-M2-WIRED: applying final config ==="

# Wi-Fi
sed -i '/^CONFIG_PACKAGE_kmod-ath=/d' .config
sed -i '/^CONFIG_PACKAGE_kmod-ath11k=/d' .config
sed -i '/^CONFIG_PACKAGE_kmod-ath11k-ahb=/d' .config
sed -i '/^CONFIG_PACKAGE_kmod-ath11k-pci=/d' .config
sed -i '/^CONFIG_PACKAGE_ath11k-firmware-ipq6018=/d' .config
sed -i '/^CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt=/d' .config
sed -i '/^CONFIG_PACKAGE_ath11k-firmware-qcn9074=/d' .config
sed -i '/^CONFIG_PACKAGE_ath11k-firmware-qcn9074-ddwrt=/d' .config
sed -i '/^CONFIG_PACKAGE_wpad-/d' .config

cat >> .config <<'EOF'
CONFIG_PACKAGE_kmod-ath=n
CONFIG_PACKAGE_kmod-ath11k=n
CONFIG_PACKAGE_kmod-ath11k-ahb=n
CONFIG_PACKAGE_kmod-ath11k-pci=n
CONFIG_PACKAGE_ath11k-firmware-ipq6018=n
CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt=n
CONFIG_PACKAGE_ath11k-firmware-qcn9074=n
CONFIG_PACKAGE_ath11k-firmware-qcn9074-ddwrt=n
CONFIG_PACKAGE_wpad-openssl=n
EOF

# USB
sed -i '/^CONFIG_PACKAGE_kmod-usb-/d' .config
sed -i '/^CONFIG_PACKAGE_usbutils=/d' .config
sed -i '/^CONFIG_PACKAGE_usb-modeswitch=/d' .config
sed -i '/^CONFIG_PACKAGE_usbmuxd=/d' .config
sed -i '/^CONFIG_PACKAGE_automount=/d' .config

cat >> .config <<'EOF'
CONFIG_PACKAGE_kmod-usb-core=n
CONFIG_PACKAGE_kmod-usb2=n
CONFIG_PACKAGE_kmod-usb3=n
CONFIG_PACKAGE_kmod-usb-dwc3=n
CONFIG_PACKAGE_kmod-usb-dwc3-qcom=n
CONFIG_PACKAGE_kmod-usb-roles=n
CONFIG_PACKAGE_kmod-usb-serial=n
CONFIG_PACKAGE_kmod-usb-serial-qualcomm=n
CONFIG_PACKAGE_kmod-usb-serial-wwan=n
CONFIG_PACKAGE_kmod-usb-storage=n
CONFIG_PACKAGE_kmod-usb-storage-extras=n
CONFIG_PACKAGE_kmod-usb-storage-uas=n
CONFIG_PACKAGE_kmod-usb-xhci-hcd=n
CONFIG_PACKAGE_usbutils=n
CONFIG_PACKAGE_usb-modeswitch=n
CONFIG_PACKAGE_usbmuxd=n
CONFIG_PACKAGE_automount=n
EOF

# Single-device build
sed -i '/^CONFIG_TARGET_MULTI_PROFILE=/d' .config
sed -i '/^CONFIG_TARGET_PER_DEVICE_ROOTFS=/d' .config

cat >> .config <<'EOF'
CONFIG_TARGET_MULTI_PROFILE=n
CONFIG_TARGET_PER_DEVICE_ROOTFS=n
EOF

echo "=== ZN-M2-WIRED final config applied ==="

echo "--- Wi-Fi ---"
grep -E '^CONFIG_(PACKAGE_(kmod-ath|kmod-ath11k|ath11k-firmware|wpad))=' .config || true

echo "--- USB ---"
grep -E '^CONFIG_PACKAGE_(kmod-usb|usbutils|usb-modeswitch|usbmuxd|automount)' .config || true

echo "--- Target ---"
grep -E '^CONFIG_TARGET_(MULTI_PROFILE|PER_DEVICE_ROOTFS)=' .config || true
