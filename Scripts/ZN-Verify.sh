#!/usr/bin/env bash
# Scripts/ZN-Verify.sh
# 在 make defconfig + ZN-FINAL-CONFIG.sh 之后执行（OpenWrt 根目录）。
#
# 上游改名 / 删除 / 依赖变化时，make defconfig 会【悄悄】丢掉你选中的插件，
# 编译照样成功，只是固件里少了东西。这个脚本把这种"静默回退"变成可见的告警：
#   1. 对比 Config/*.txt 里要求的 CONFIG_PACKAGE_xxx=y 与最终 .config
#   2. 缺失的包：给出 feeds/package 里名字相近的候选（疑似改名）
#   3. ZN_REQUIRED_PKGS 里的必需包缺失 -> 直接失败（不发布没有代理的固件）
#   4. 校验 ZN-Settings.sh 的定制（IP / 主机名）是否真的生效，防止上游改了文件路径后 sed 静默落空
#
# 环境变量:
#   ZN_REQUIRED_PKGS  必需包，默认 "luci-app-homeproxy sing-box"
#   ZN_VERIFY_IGNORE  忽略的包（正则），默认覆盖 FINAL-CONFIG 里有意关闭的 Wi-Fi / USB，以及 sqm-scripts-nss

set -uo pipefail

REQUIRED="${ZN_REQUIRED_PKGS:-luci-app-homeproxy sing-box}"
# sqm-scripts-nss 在 feeds 里并不存在：NSS 版 SQM 脚本由 ZN-Settings.sh 手动下载 nss-zk.qos 提供，这行配置本就是空操作
IGNORE="${ZN_VERIFY_IGNORE:-^(kmod-ath|kmod-usb|ath11k|wpad|usbutils|usb-modeswitch|usbmuxd|automount|sqm-scripts-nss)}"
WS="${GITHUB_WORKSPACE:-.}"
CFG_DIR="$WS/Config"

[ -f .config ] || { echo "[ZN-Verify] 没有 .config，跳过"; exit 0; }

WARN=()
FAIL=()
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# ---- 1. 插件是否被静默丢弃 ----------------------------------
REQ_FILES=("$CFG_DIR/${WRT_CONFIG:-}.txt")
if [[ "${WRT_CONFIG,,}" != *"test"* ]]; then REQ_FILES+=("$CFG_DIR/ZN-GENERAL.txt"); fi
[ -f "$CFG_DIR/PRIVATE.txt" ] && REQ_FILES+=("$CFG_DIR/PRIVATE.txt")

mapfile -t REQUESTED < <(cat "${REQ_FILES[@]}" 2>/dev/null \
    | grep -oP '^CONFIG_PACKAGE_\K[^=]+(?==y)' | sort -u)

MISSING=()
for P in "${REQUESTED[@]}"; do
    [[ "$P" =~ $IGNORE ]] && continue
    # 之后被显式写成 =n 的视为有意关闭
    grep -qE "^CONFIG_PACKAGE_${P}=n" .config && continue
    grep -qE "^CONFIG_PACKAGE_${P}=(y|m)$" .config || MISSING+=("$P")
done

for P in "${MISSING[@]}"; do
    CORE="${P#luci-app-}"; CORE="${CORE#luci-theme-}"; CORE="${CORE#luci-i18n-}"
    CAND=$(find ./feeds ./package -maxdepth 4 -type d -iname "*${CORE%%-*}*" 2>/dev/null \
        | sed 's#.*/##' | sort -u | head -n 3 | tr '\n' ' ')
    MSG="插件 \`$P\` 被 defconfig 丢弃（上游改名/删除/依赖变化？）"
    [ -n "$CAND" ] && MSG="$MSG；相近候选: $CAND"
    echo "::warning title=ZN-Verify::$MSG"
    WARN+=("$MSG")
done

for P in $REQUIRED; do
    if ! grep -qE "^CONFIG_PACKAGE_${P}=(y|m)$" .config; then
        echo "::error title=ZN-Verify::必需组件 $P 不在最终配置中，终止编译"
        FAIL+=("必需组件 $P 缺失")
    fi
done

# ---- 2. 第三方包软失败记录 ------------------------------------
if [ -s .zn-soft-fail ]; then
    while read -r N; do WARN+=("第三方包 \`$N\` 获取失败已跳过"); done < .zn-soft-fail
fi

# ---- 3. 定制是否生效 ------------------------------------------
CFG_GEN="./package/base-files/files/bin/config_generate"
if [ -f "$CFG_GEN" ]; then
    [ -n "${WRT_IP:-}" ]   && ! grep -qF "$WRT_IP" "$CFG_GEN" \
        && WARN+=("默认 IP $WRT_IP 未写入 config_generate（上游改了文件结构？）")
    [ -n "${WRT_NAME:-}" ] && ! grep -qF "hostname='$WRT_NAME'" "$CFG_GEN" \
        && WARN+=("默认主机名 $WRT_NAME 未写入 config_generate")
else
    WARN+=("找不到 config_generate，IP/主机名定制无法验证")
fi

if [ -n "${WRT_THEME:-}" ] && ! grep -qE "^CONFIG_PACKAGE_luci-theme-${WRT_THEME}=(y|m)$" .config; then
    WARN+=("默认主题 luci-theme-$WRT_THEME 不在最终配置中")
fi

# ---- 汇报 -------------------------------------------------------
{
    echo "### ZN-Verify"
    if [ "${#WARN[@]}" -eq 0 ] && [ "${#FAIL[@]}" -eq 0 ]; then
        echo "配置检查全部通过。"
    else
        for M in "${FAIL[@]}"; do echo "- ❌ $M"; done
        for M in "${WARN[@]}"; do echo "- ⚠️ $M"; done
    fi
} >> "$SUMMARY"

if [ "${#WARN[@]}" -gt 0 ] && [ -n "${GITHUB_ENV:-}" ]; then
    echo "WRT_VERIFY=${#WARN[@]} 项告警（详见 Job Summary）" >> "$GITHUB_ENV"
fi

echo "[ZN-Verify] 告警 ${#WARN[@]} 项，致命 ${#FAIL[@]} 项"
[ "${#FAIL[@]}" -eq 0 ] || exit 1
exit 0
