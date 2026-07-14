#!/bin/bash

# =========================================================
# 0. 強行修復 gecoosac 插件作者遺漏的文件執行權限問題,作者已删库
# =========================================================
echo "[清理] 正在清理 gecoosac 源码..."
#rm -rf package/gecoosac
#rm -rf gecoosac
#rm -rf package/feeds/luci/luci-app-gecoosac
#rm -rf package/feeds/packages/luci-app-gecoosac
echo "[克隆] 正在克隆luci-app-gecoosac源码..."
git clone -b main --depth=1 https://github.com/laipeng668/luci-app-gecoosac.git  package/luci-app-gecoosac
GECOOSAC_PKG_DIR="package/luci-app-gecoosac"
if [ -d "$GECOOSAC_PKG_DIR" ]; then
    echo "🔧 正在精確修正 gecoosac 核心文件執行權限..."

    # 使用 find 在源碼目錄下精確尋找這 5 個特定的文件名，並賦予可執行權限
    find "$GECOOSAC_PKG_DIR" -type f \( \
        -name "gecoosac" -o \
        -name "gecoosac-log-cleanup" -o \
        -name "gecoosac-log-runner" -o \
        -name "gecoosac-random-port" -o \
        -name "gecoosac-read-log" \
    \) -exec chmod +x {} +

    echo "🎉 5 個核心文件權限精確修正完成！"
else
    echo "⚠️ 未找到 gecoosac 原始碼目錄，請檢查路徑是否正確。"
fi

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

echo "[克隆] 正在克隆 luci-app-netspeedtest 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest.git package/netspeedtest

echo "[克隆] 正在克隆 OpenAppFilter 源码..."
git clone -b master --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter

# =========================================================
# 簡單暴力的「剝洋蔥」循環解壓腳本：直到找到 feature.cfg 爲止
# =========================================================

OAF_DIR="package/OpenAppFilter"
API_URL="https://www.openappfilter.com/fros/get_feature_list"
TARGET_RULE_DIR="${OAF_DIR}/open-app-filter/files/etc/appfilter"
TARGET_ICON_DIR="${OAF_DIR}/luci-app-oaf/htdocs/luci-static/resources/app_icons"

# 1. 自動獲取最新文件名並下載
LATEST_FILENAME=$(curl -sLk "$API_URL" | jq -r '.[0].filename')
[ -z "$LATEST_FILENAME" ] || [ "$LATEST_FILENAME" = "null" ] && LATEST_FILENAME=$(curl -sLk "$API_URL" | grep -oE '[a-zA-Z0-9_\.]+\.zip' | head -n 1)
[ -z "$LATEST_FILENAME" ] && LATEST_FILENAME="feature3.0_cn_26.04.10.zip"

DOWNLOAD_URL="https://www.openappfilter.com/fros/download_feature?filename=${LATEST_FILENAME}&f=1"
ZIP_FILE="/tmp/${LATEST_FILENAME}"
echo "正在下載最新特徵包: $LATEST_FILENAME"
curl -Lk "$DOWNLOAD_URL" -o "$ZIP_FILE"

# 2. 建立一個乾淨的工作目錄
WORK_DIR="/tmp/oaf_unzip_work"
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR"
cp "$ZIP_FILE" "$WORK_DIR/layer_0.zip"

# 3. 核心：不斷尋找並解壓壓縮包，直到挖出 feature.cfg
echo "開始循環解壓（自動跳過 txt，無視副檔名變更）..."
cd "$WORK_DIR"

# 只要當前目錄下還沒出現 feature.cfg，就一直循環
while [ ! -f "feature.cfg" ]; do
    # 尋找目前目錄下所有「不是 txt」且「不是已解壓目錄」的文件
    CURRENT_FILE=$(find . -maxdepth 1 -type f ! -name "*.txt" ! -name "feature.cfg" | head -n 1)
    
    # 如果找不到任何可以繼續解壓的文件了，強行跳出循環防止死鎖
    if [ -z "$CURRENT_FILE" ]; then
        echo "⚠️ 已經沒有可解壓的文件，但仍未找到 feature.cfg！"
        break
    fi

    echo "正在處理文件: $CURRENT_FILE"

    # 暴力解壓嘗試：不管你有沒有副檔名，先強行當作 zip 解壓到臨時目錄
    mkdir -p next_layer
    if unzip -q -o "$CURRENT_FILE" -d next_layer/ 2>/dev/null; then
        echo "成功解壓了一層包！"
        # 刪除已被拆解的舊文件，把新解壓出來的內容移到當前目錄
        rm -f "$CURRENT_FILE"
        mv next_layer/* . 2>/dev/null
        rm -rf next_layer
    else
        # 如果 unzip 失敗，嘗試是不是 tar 壓縮包
        if tar -xzf "$CURRENT_FILE" -C next_layer/ 2>/dev/null; then
            echo "成功使用 tar 解壓了一層包！"
            rm -f "$CURRENT_FILE"
            mv next_layer/* . 2>/dev/null
        else
            echo "💡 提示: $CURRENT_FILE 無法被進一步解壓（可能它就是最終的 bin 實體）。"
            # 如果它完全無法解壓，為了防止陷入死循環，我們強行把它當作核心 bin 備用並退出
            mkdir -p "$TARGET_RULE_DIR"
            cp "$CURRENT_FILE" "$TARGET_RULE_DIR/feature.bin"
            cp "$CURRENT_FILE" "$TARGET_RULE_DIR/appfilter.bin"
            break
        fi
        rm -rf next_layer
    fi
done

# 4. 循環結束，將最終挖出來的成果覆蓋到原始碼目錄
if [ -f "feature.cfg" ]; then
    echo "🎉 成功挖出 feature.cfg！正在覆蓋原始碼..."
    mkdir -p "$TARGET_RULE_DIR"
    cp feature.cfg "$TARGET_RULE_DIR/feature.cfg"
    cp feature.cfg "$TARGET_RULE_DIR/feature_cn.cfg"
fi

# 尋找深層目錄下可能被解壓出來的 app_icons 圖標資料夾
FINAL_ICON_DIR=$(find . -type d -name "app_icons" | head -n 1)
if [ -n "$FINAL_ICON_DIR" ]; then
    echo "🎉 成功找到 app_icons 圖標目錄！正在級聯覆蓋..."
    mkdir -p "$TARGET_ICON_DIR"
    cp -r "$FINAL_ICON_DIR"/* "$TARGET_ICON_DIR/"
fi

# 5. 清理垃圾
rm -rf "$WORK_DIR" "$ZIP_FILE"
echo "🎉 全自動無限解壓與覆蓋流程完美結束！"

echo "=========================================="
echo "    [PRIVATE.sh] 源码清洗阶段执行完毕      "
echo "=========================================="
