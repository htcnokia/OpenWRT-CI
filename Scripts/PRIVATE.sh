#!/bin/bash

echo "=========================================="
echo "    开始执行 [PRIVATE.sh] 源码清洗阶段    "
echo "=========================================="

# 1. 修复 netspeedtest 遗留的 Python3 致命依赖
NETSPEED_MAKE=$(find ./ -maxdepth 4 -type f -wholename "*/netspeedtest/luci-app-netspeedtest/Makefile" 2>/dev/null | head -n 1)
if [ -n "$NETSPEED_MAKE" ]; then
    echo "[成功] 找到 netspeedtest，开始清理过时 Python 依赖..."
    sed -i 's/+python3-pkg-resources//g' "$NETSPEED_MAKE"
    sed -i 's/+python3-email//g' "$NETSPEED_MAKE"
    sed -i 's/++/\+/g' "$NETSPEED_MAKE"
    sed -i 's/ \\/\\/g' "$NETSPEED_MAKE" 
fi

# 2. 修复 QModem 缺失的 5G 驱动依赖警告
QMODEM_MAKE=$(find ./ -maxdepth 4 -type f -wholename "*/QModem/application/qmodem/Makefile" 2>/dev/null | head -n 1)
if [ -n "$QMODEM_MAKE" ]; then
    echo "[成功] 找到 QModem 并清理未安装的 5G 驱动依赖..."
    sed -i 's/+kmod-mhi-wwan//g' "$QMODEM_MAKE"
    sed -i 's/+quectel-CM-5G//g' "$QMODEM_MAKE"
fi
echo "[清理] 正在清理 luci-app-timecontrol 源码..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[克隆] 正在克隆luci-app-timecontrol 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-timecontroll.git  package/luci-app-timecontrol
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

TIMECTRL_MAKE=$(find ./package/luci-app-timecontrol -maxdepth 2 -type f -name "Makefile" | head -n 1)

if [ -n "$TIMECTRL_MAKE" ]; then
    echo "[成功] 找到 Makefile: $TIMECTRL_MAKE ，开始剥离旧防火墙依赖..."
    sed -i 's/+iptables-mod-ipopt//g' "$TIMECTRL_MAKE"
    sed -i 's/+iptables//g' "$TIMECTRL_MAKE"
    sed -i 's/+ip6tables//g' "$TIMECTRL_MAKE"
    sed -i 's/+kmod-ipt-core//g' "$TIMECTRL_MAKE"
    sed -i 's/++/\+/g' "$TIMECTRL_MAKE"
    sed -i 's/::=/:=/g' "$TIMECTRL_MAKE" 2>/dev/null
    echo "[完成] timecontrol 依赖链剥离成功！"
fi

echo "[克隆] 正在克隆 luci-app-lucky 源码..."
git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/luci-app-lucky

#echo "[克隆] 正在克隆 luci-app-netspeedtest 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest.git package/netspeedtest

echo "[克隆] 正在克隆 OpenAppFilter 源码..."
git clone -b master --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter

#!/bin/bash
#
# ============================================================
#  OpenAppFilter 特征库自动更新片段（用于 private.sh）
#  已在 Ubuntu 下用 test_oaf_unzip.sh 验证解压逻辑可用，
#  这里原样迁移，只是把路径换回 OpenWrt 编译目录结构。
# ============================================================

set -u

OAF_DIR="package/OpenAppFilter"
API_URL="https://www.openappfilter.com/fros/get_feature_list"
TARGET_RULE_DIR="${OAF_DIR}/open-app-filter/files/etc/appfilter"
TARGET_ICON_DIR="${OAF_DIR}/luci-app-oaf/htdocs/luci-static/resources/app_icons"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
REFERER="https://www.openappfilter.com/"

log()  { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERROR] $*" >&2; }

echo "正在動態請求官方最新特徵庫列表..."

# ---------- 1. 精準相容提取 filename ----------
API_RESPONSE=$(curl -sLk -A "$UA" -e "$REFERER" "$API_URL")

LATEST_FILENAME=$(echo "$API_RESPONSE" | jq -r '.data[0].filename' 2>/dev/null)
if [ -z "$LATEST_FILENAME" ] || [ "$LATEST_FILENAME" = "null" ]; then
    LATEST_FILENAME=$(echo "$API_RESPONSE" | jq -r '.[0].filename' 2>/dev/null)
fi
if [ -z "$LATEST_FILENAME" ] || [ "$LATEST_FILENAME" = "null" ]; then
    LATEST_FILENAME=$(echo "$API_RESPONSE" | grep -oE '[a-zA-Z0-9_\.]+\.zip' | head -n 1)
fi
if [ -z "$LATEST_FILENAME" ]; then
    LATEST_FILENAME="feature3.0_cn_26.04.10.zip"
fi
echo "🚀 精準匹配到官網最新特徵庫包名: $LATEST_FILENAME"

# ---------- 2. 直連下載 ----------
DOWNLOAD_URL="https://www.openappfilter.com/fros/download_feature?filename=${LATEST_FILENAME}&f=1"
ZIP_FILE="/tmp/${LATEST_FILENAME}"

curl -Lk -A "$UA" -e "$REFERER" "$DOWNLOAD_URL" -o "$ZIP_FILE"

if [ ! -s "$ZIP_FILE" ]; then
    err "下載失敗，文件為空或不存在: $ZIP_FILE"
    exit 1
fi

# 校驗是否為合法 zip（避免下載到反爬錯誤頁卻繼續往下跑）
if ! unzip -l "$ZIP_FILE" >/dev/null 2>/tmp/oaf_zip_check_err.log; then
    err "下載到的檔案不是合法/完整的 zip！"
    cat /tmp/oaf_zip_check_err.log
    err "檔案開頭內容預覽："
    head -c 300 "$ZIP_FILE"; echo
    exit 1
fi

# ---------- 3. 建立扁平化工作目錄 ----------
WORK_DIR="/tmp/oaf_unzip_work"
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR"
cp "$ZIP_FILE" "$WORK_DIR/layer_0.zip"
cd "$WORK_DIR"

echo "開始遞歸扁平化解壓（直到挖出 feature.cfg）..."

LAYER=0
while [ ! -f "feature.cfg" ]; do
    CURRENT_FILE=$(find . -maxdepth 1 -type f ! -name "*.txt" ! -name "*.cfg" ! -name "*.png" | head -n 1)

    if [ -z "$CURRENT_FILE" ]; then
        echo "⚠️ 已經沒有可解壓的文件，遞歸結束。"
        break
    fi

    LAYER=$((LAYER + 1))
    echo "正在強制剝離核心封包（第 ${LAYER} 層）: $CURRENT_FILE"

    mkdir -p tmp_extract
    EXTRACTED=0

    # --- 嘗試 unzip（先 UTF-8，失敗再試 CP936 應對中文檔名）---
    if unzip -q -o "$CURRENT_FILE" -d tmp_extract/ 2>tmp_unzip_err.log; then
        EXTRACTED=1
    elif [ -n "$(find tmp_extract -type f 2>/dev/null)" ]; then
        # unzip 退出碼非0，但實際已解出文件（常見於非致命 warning），視為成功
        warn "unzip 有警告但已解出文件，警告內容："
        cat tmp_unzip_err.log
        EXTRACTED=1
    else
        rm -rf tmp_extract && mkdir -p tmp_extract
        if unzip -q -o -O CP936 "$CURRENT_FILE" -d tmp_extract/ 2>>tmp_unzip_err.log; then
            EXTRACTED=1
        elif [ -n "$(find tmp_extract -type f 2>/dev/null)" ]; then
            EXTRACTED=1
        fi
    fi

    # --- 若 unzip 兩種方式都失敗，嘗試 tar ---
    if [ "$EXTRACTED" -eq 0 ]; then
        rm -rf tmp_extract && mkdir -p tmp_extract
        if tar -xzf "$CURRENT_FILE" -C tmp_extract/ 2>tmp_tar_err.log; then
            EXTRACTED=1
        elif [ -n "$(find tmp_extract -type f 2>/dev/null)" ]; then
            EXTRACTED=1
        else
            err "該文件既不能被 unzip 也不能被 tar 解壓，真實報錯如下："
            cat tmp_unzip_err.log 2>/dev/null
            cat tmp_tar_err.log 2>/dev/null
        fi
    fi

    if [ "$EXTRACTED" -eq 1 ]; then
        echo "成功解壓第 ${LAYER} 層封包！"
        rm -f "$CURRENT_FILE"
        # 【關鍵：扁平化釋放】將 tmp_extract 內的所有「文件」移到當前根目錄，無視其嵌套的資料夾層次
        find tmp_extract -type f -exec mv {} . \;
        rm -rf tmp_extract tmp_unzip_err.log tmp_tar_err.log
    else
        echo "💡 提示: $CURRENT_FILE 無法再被解壓（已觸底）。"
        rm -rf tmp_extract
        break
    fi
done

# ---------- 4. 統一執行源碼覆蓋：feature.cfg ----------
if [ -f "feature.cfg" ]; then
    echo "🎉 成功完美剝離出核心 feature.cfg！正在覆蓋原始碼..."
    mkdir -p "$TARGET_RULE_DIR"
    cp feature.cfg "$TARGET_RULE_DIR/feature.cfg"
    cp feature.cfg "$TARGET_RULE_DIR/feature_cn.cfg"
else
    err "❌ 錯誤: 最終未能在包中找到 feature.cfg 文件！"
fi

# ---------- 5. 統一執行源碼覆蓋：app_icons (*.png) ----------
PNG_COUNT=$(find . -maxdepth 1 -name "*.png" | wc -l)
if [ "$PNG_COUNT" -gt 0 ]; then
    echo "🎉 找到 ${PNG_COUNT} 個圖標檔案！正在覆蓋圖標目錄..."
    mkdir -p "$TARGET_ICON_DIR"
    find . -maxdepth 1 -name "*.png" -exec cp -f {} "$TARGET_ICON_DIR/" \;
    echo "圖標已同步至: $TARGET_ICON_DIR"
else
    err "❌ 錯誤: 未在壓縮包中找到圖標檔案 (.png)！"
fi

# ---------- 6. 清理 ----------
rm -rf "$WORK_DIR" "$ZIP_FILE" /tmp/oaf_zip_check_err.log
echo "OAF 特徵庫更新流程結束。"

echo "=========================================="
echo "    [PRIVATE.sh] 源码清洗阶段执行完毕      "
echo "=========================================="
