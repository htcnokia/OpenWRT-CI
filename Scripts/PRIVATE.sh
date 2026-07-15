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

# =========================================================
# Fros / OpenAppFilter 官網特徵庫無限遞歸剝洋蔥腳本 (精準修正版)
# =========================================================

OAF_DIR="package/OpenAppFilter"
API_URL="https://www.openappfilter.com/fros/get_feature_list"
TARGET_RULE_DIR="${OAF_DIR}/open-app-filter/files/etc/appfilter"
TARGET_ICON_DIR="${OAF_DIR}/luci-app-oaf/htdocs/luci-static/resources/app_icons"

echo "正在動態請求官方最新特徵庫列表..."

# 1. 精準相容提取 filename (無論最外層是物件還是陣列)
API_RESPONSE=$(curl -sLk "$API_URL")
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

# 2. 直連下載
DOWNLOAD_URL="https://www.openappfilter.com/fros/download_feature?filename=${LATEST_FILENAME}&f=1"
ZIP_FILE="/tmp/${LATEST_FILENAME}"
curl -Lk "$DOWNLOAD_URL" -o "$ZIP_FILE"

# 3. 建立扁平化工作目錄
WORK_DIR="/tmp/oaf_unzip_work"
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR"
cp "$ZIP_FILE" "$WORK_DIR/layer_0.zip"

cd "$WORK_DIR"
echo "開始遞歸扁平化解壓（直到挖出 feature.cfg）..."

# 只要當前目錄下還沒有出現 feature.cfg，就一直進行剝洋蔥解壓
while [ ! -f "feature.cfg" ]; do
    # 尋找當前目錄下「非 txt」、「非 cfg」、「非 png」的任何可能壓縮包文件
    CURRENT_FILE=$(find . -maxdepth 1 -type f ! -name "*.txt" ! -name "*.cfg" ! -name "*.png" | head -n 1)
    
    if [ -z "$CURRENT_FILE" ]; then
        echo "⚠️ 已經沒有可解壓的文件，遞歸結束。"
        break
    fi

    echo "正在強制剝離核心封包: $CURRENT_FILE"

    # 建立臨時解壓接應目錄
    mkdir -p tmp_extract

    # 嘗試用 unzip 解壓
    if unzip -q -o "$CURRENT_FILE" -d tmp_extract/ 2>/dev/null; then
        echo "成功解壓一層 ZIP/BIN 封包！"
        # 刪除已被拆解的舊壓縮包
        rm -f "$CURRENT_FILE"
        
        # 【關鍵：扁平化釋放】將 tmp_extract 內的所有「文件」移到當前根目錄，無視其嵌套的資料夾層次
        find tmp_extract -type f -exec mv {} . \; 2>/dev/null
        rm -rf tmp_extract
    else
        # 嘗試用 tar 解壓 (以防萬一是 tar 包)
        if tar -xzf "$CURRENT_FILE" -C tmp_extract/ 2>/dev/null; then
            echo "成功解壓一層 TAR 封包！"
            rm -f "$CURRENT_FILE"
            find tmp_extract -type f -exec mv {} . \; 2>/dev/null
            rm -rf tmp_extract
        else
            echo "💡 提示: $CURRENT_FILE 無法再被解壓（已觸底）。"
            rm -rf tmp_extract
            break
        fi
    fi
done

# 4. 統一執行源碼覆蓋
if [ -f "feature.cfg" ]; then
    echo "🎉 成功完美剝離出核心 feature.cfg！正在覆蓋原始碼..."
    mkdir -p "$TARGET_RULE_DIR"
    cp feature.cfg "$TARGET_RULE_DIR/feature.cfg"
    cp feature.cfg "$TARGET_RULE_DIR/feature_cn.cfg"
else
    echo "❌ 錯誤: 最終未能在包中找到 feature.cfg 文件！"
fi

# 5. 精準搜尋並覆蓋圖標 (不論釋放出來時 app_icons 在哪一層)
# 因為剛才用 find -exec mv {} . 之後，所有圖片（如 2132.png）都被直接釋放到當前目錄了
PNG_COUNT=$(find . -maxdepth 1 -name "*.png" | wc -l)
if [ "$PNG_COUNT" -gt 0 ]; then
    echo "🎉 成功提取到 $PNG_COUNT 個應用圖標！正在覆蓋至 Luci 靜態資源目錄..."
    mkdir -p "$TARGET_ICON_DIR"
    cp *.png "$TARGET_ICON_DIR/" 2>/dev/null
else
    echo "❌ 錯誤: 未在壓縮包中找到圖標檔案 (.png)！"
fi

# 6. 清理臨時工作目錄
rm -rf "$WORK_DIR" "$ZIP_FILE"
echo "🎉 [完美完成] 特徵庫及圖標已成功穿透多層嵌套，注入編譯流程！"

echo "=========================================="
echo "    [PRIVATE.sh] 源码清洗阶段执行完毕      "
echo "=========================================="
