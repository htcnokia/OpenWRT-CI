#!/bin/bash
set -eu
TARGET_FILENAME="ibm-plex-mono-cyrillic-400-normal-BSMlKf0J.woff2"
ABS_RM="/etc/homeproxy/dashboard/assets/$TARGET_FILENAME"

SEARCH_ROOTS=()
[ -n "${GITHUB_WORKSPACE:-}" ] && SEARCH_ROOTS+=("$GITHUB_WORKSPACE")
SEARCH_ROOTS+=(".")
SEARCH_ROOTS+=("..")

patched_any=0

for ROOT in "${SEARCH_ROOTS[@]}"; do
  [ -d "$ROOT" ] || continue
  echo '查找文件：dashboard/assets'
  # 1) 删除工作区中任何 dashboard/assets 下的同名文件
  find "$ROOT" -type f -path "*/dashboard/assets/$TARGET_FILENAME" -print -exec rm -f {} \; 2>/dev/null || true

  # 2) 在所有匹配的 update_resources.sh 中注入 rm 行
  find "$ROOT" -type f -path "*/luci-app-homeproxy/root/etc/homeproxy/scripts/update_resources.sh" -print0 2>/dev/null | while IFS= read -r -d '' script_path; do
    echo "[patch] 检查: $script_path"
    if grep -qF "$ABS_RM" "$script_path" 2>/dev/null || grep -qF "$TARGET_FILENAME" "$script_path" 2>/dev/null; then
      echo "[patch] 已经存在, 跳过: $script_path"
      continue
    fi

    awk -v rmline="    rm -rf $ABS_RM" '
      { print }
      !done && /mark_updated/ && /dashboard/ {
        print rmline
        done=1
      }
    ' "$script_path" > "${script_path}.tmp" || { echo "[patch] awk failed for $script_path"; rm -f "${script_path}.tmp"; continue; }

    if grep -qF "$ABS_RM" "${script_path}.tmp"; then
      chmod --reference="$script_path" "${script_path}.tmp" 2>/dev/null || true
      mv "${script_path}.tmp" "$script_path"
      echo "[patch] 注入应用于 $script_path"
      patched_any=1
    else
      rm -f "${script_path}.tmp"
      echo "[patch] 注入点未发现： $script_path; skipped."
    fi

    pkg_asset="${script_path%/root/etc/homeproxy/scripts/update_resources.sh}/root/etc/homeproxy/dashboard/assets/$TARGET_FILENAME"
    if [ -f "$pkg_asset" ]; then
      rm -f "$pkg_asset" && echo "[patch] 移除资源文件: $pkg_asset" || echo "[patch] 移除资源文件失败: $pkg_asset"
    fi
  done
done

# 4. 汇总输出
if [ "$patched_any" -eq 0 ]; then
  echo "[patch] 提示：未修改任何文件（可能已是最新状态或未找到目标文件）。"
else
  echo "[patch] 完成：成功对目标文件进行了补丁注入与资源清理！"
fi

echo "=================================================="
echo " [Private] 所有配置完成！                         "
echo "=================================================="
