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
# Fros / OpenAppFilter 2026 最新特征库全自动抓取与源码级覆盖
# =========================================================

# 1. 定义你的 OpenAppFilter 源码在编译机中的核心路径 (请根据实际CI修改)
OAF_DIR="package/OpenAppFilter"

# 2. 特征包下载链接与目标文件名
DOWNLOAD_URL="https://www.openappfilter.com/fros/download_feature?filename=feature3.0_cn_26.04.10.zip&f=1"
ZIP_FILE="/tmp/feature3.0_cn_26.04.10.zip"

echo "正在从官方直链下载最新的特征库压缩包..."
# 使用 curl 下载（-L 自动跟踪重定向，-k 忽略可能存在的证书问题，-o 指定保存路径）
curl -Lk "$DOWNLOAD_URL" -o "$ZIP_FILE"

# 3. 建立临时解压目录并进行第一层解压 (解压出外层的 zip 得到 bin 文件)
mkdir -p /tmp/oaf_step1
echo "正在解压外层 ZIP 包..."
unzip -o "$ZIP_FILE" -d /tmp/oaf_step1/

# 4. 核心：将.bin 的压缩包进行二次解压 (解压出 feature.cfg 和 app_icons)
mkdir -p /tmp/oaf_extracted
echo "正在二次解压核心特征 .bin 封包..."
# 顺藤摸瓜找到解压出来的 bin 文件，通常会和 filename 参数名字一致但后缀变成 bin 或者是 free.bin
# 这里使用通配符 *.bin 确保 100% 能匹配上解压出来的 bin 包
unzip -o /tmp/oaf_step1/*.bin -d /tmp/oaf_extracted/

# ----------------- 开始源码目录级级联覆盖 (Overwrite) -----------------

# 5. 图标级联覆盖 (Directory Overwrite)
if [ -d "/tmp/oaf_extracted/app_icons" ]; then
    echo "正在对图标目录进行级联覆盖 (Directory Overwrite)..."
    TARGET_ICON_DIR="${OAF_DIR}/luci-app-oaf/htdocs/luci-static/resources/app_icons"
    mkdir -p "$TARGET_ICON_DIR"
    cp -r /tmp/oaf_extracted/app_icons/* "$TARGET_ICON_DIR/"
else
    echo "错误: 未在解压包中找到 app_icons 目录！"
fi

# 6. 特征库文件级覆盖 (File Overwrite)
if [ -f "/tmp/oaf_extracted/feature.cfg" ]; then
    echo "正在对特征库文本进行文件级覆盖 (File Overwrite)..."
    TARGET_RULE_DIR="${OAF_DIR}/open-app-filter/files/etc/appfilter"
    mkdir -p "$TARGET_RULE_DIR"
    
    # 覆盖默认主特征库
    cp /tmp/oaf_extracted/feature.cfg "$TARGET_RULE_DIR/feature.cfg"
    # 同时覆盖中文特征库，确保固件在中文界面下完美同步
    cp /tmp/oaf_extracted/feature.cfg "$TARGET_RULE_DIR/feature_cn.cfg"
else
    echo "错误: 未在解压包中找到核心 feature.cfg 文件！"
fi

# 7. 清理编译机的临时垃圾文件，保持 CI 环境整洁
rm -rf "$ZIP_FILE" /tmp/oaf_step1 /tmp/oaf_extracted
echo "🎉 OpenAppFilter 26.04.10 最新特征库与图标源码层级联替换完美完成！"

echo "=========================================="
echo "    [PRIVATE.sh] 源码清洗阶段执行完毕      "
echo "=========================================="
