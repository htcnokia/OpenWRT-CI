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

echo "[克隆] 正在克隆 luci-app-netspeedtest 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest.git package/netspeedtest

echo "[克隆] 正在克隆 OpenAppFilter 源码..."
git clone -b master --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter

# =========================================================
# Fros / OpenAppFilter 官网特征库动态追新与源码层级联覆盖
# =========================================================

# 1. 配置基础路径 (请根据实际CI修改)
OAF_DIR="package/OpenAppFilter"
API_URL="https://www.openappfilter.com/fros/get_feature_list"

echo "正在动态请求官方最新特征库列表..."

# 2. 核心：请求 API 并精准提取第一行的 filename
# 如果 API 返回的 JSON 结构中文件名在 data 数组的第一个元素里：
# 格式通常为: {"data": [{"filename": "feature3.0_cn_26.04.10.zip", ...}, ...]}
LATEST_FILENAME=$(curl -sLk "$API_URL" | jq -r '.data[0].filename')

# 💡 如果上面这行命令提取出来是空，说明 JSON 的层级有微调。
# 此时你可以尝试下面这种通过模糊匹配提取第一个 .zip 字符的保底写法：
if [ -z "$LATEST_FILENAME" ] || [ "$LATEST_FILENAME" = "null" ]; then
    LATEST_FILENAME=$(curl -sLk "$API_URL" | grep -oE '[a-zA-Z0-9_\.]+\.zip' | head -n 1)
fi

# 3. 安全检查：如果网络故障无法获取，采用保底版本号防止编译中断
if [ -z "$LATEST_FILENAME" ]; then
    echo "警告: 动态获取失败，可能官方接口变动，启用保底版本号下载..."
    LATEST_FILENAME="feature3.0_cn_26.04.10.zip"
fi

echo "🚀 精准匹配到官网最新特征库包名为: $LATEST_FILENAME"

# 4. 动态组装完美直链进行下载
DOWNLOAD_URL="https://www.openappfilter.com/fros/download_feature?filename=${LATEST_FILENAME}&f=1"
ZIP_FILE="/tmp/${LATEST_FILENAME}"

echo "开始无浏览器环境直连下载: $DOWNLOAD_URL"
curl -Lk "$DOWNLOAD_URL" -o "$ZIP_FILE"

# 5. 建立临时解压目录并进行双层解压
mkdir -p /tmp/oaf_step1 /tmp/oaf_extracted
echo "正在进行双层解压（ZIP -> BIN -> 源码文件）..."

unzip -o "$ZIP_FILE" -d /tmp/oaf_step1/
unzip -o /tmp/oaf_step1/*.bin -d /tmp/oaf_extracted/

# 6. 自动对特征库及其中文副包进行文件级覆盖 (File Overwrite)
if [ -f "/tmp/oaf_extracted/feature.cfg" ]; then
    echo "正在对核心特征库进行源码层文件覆盖..."
    TARGET_RULE_DIR="${OAF_DIR}/open-app-filter/files/etc/appfilter"
    mkdir -p "$TARGET_RULE_DIR"
    cp /tmp/oaf_extracted/feature.cfg "$TARGET_RULE_DIR/feature.cfg"
    cp /tmp/oaf_extracted/feature.cfg "$TARGET_RULE_DIR/feature_cn.cfg"
else
    echo "❌ 错误: 解压后未找到核心 feature.cfg 文件！"
fi

# 7. 自动对应用图标进行目录级级联覆盖 (Directory Overwrite)
if [ -d "/tmp/oaf_extracted/app_icons" ]; then
    echo "正在对应用图标目录进行级联覆盖..."
    TARGET_ICON_DIR="${OAF_DIR}/luci-app-oaf/htdocs/luci-static/resources/app_icons"
    mkdir -p "$TARGET_ICON_DIR"
    cp -r /tmp/oaf_extracted/app_icons/* "$TARGET_ICON_DIR/"
else
    echo "❌ 错误: 未在压缩包中找到 app_icons 图标目录！"
fi

# 8. 清理现场，保持 CI 编译机环境整洁
rm -rf "$ZIP_FILE" /tmp/oaf_step1 /tmp/oaf_extracted
echo "🎉 [完美完成] Fros 最新特征库已经全自动注入到 OpenWrt 编译流程中！"

echo "=========================================="
echo "    [PRIVATE.sh] 源码清洗阶段执行完毕      "
echo "=========================================="
