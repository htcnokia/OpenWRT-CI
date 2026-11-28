#!/bin/bash
# ZN-PPE：引入插件
set -e
# ============================================================
# 自愈辅助：重试 / 软失败 / 锁定回退
#   - 第三方仓库偶发网络错误：自动重试 3 次
#   - 非必需的第三方包彻底失败：跳过并记录，不拖垮整个编译
#   - 必需组件（HomeProxy / sing-box）失败：直接终止，避免出无代理固件
#   - ZN_LOCK_FILE 存在时：按锁里的提交回退到"上次成功"的第三方版本
# ============================================================
PKG_LOCK_OUT="$PWD/.zn-pkg.lock"
SOFT_FAIL_FILE="$PWD/.zn-soft-fail"
: > "$PKG_LOCK_OUT"
: > "$SOFT_FAIL_FILE"

RETRY() {
    local n=1
    until "$@"; do
        [ "$n" -ge 3 ] && return 1
        echo "[ZN-Packages] 第 $n 次失败，$((n * 5)) 秒后重试: $*"
        sleep $((n * 5))
        n=$((n + 1))
    done
}

SOFT_FAIL() {
    echo "::warning title=ZN-Packages::第三方包 $1 获取失败，已跳过（其余照常编译）"
    echo "$1" >> "$SOFT_FAIL_FILE"
}

HARD_FAIL() {
    echo "::error title=ZN-Packages::必需组件 $1 获取失败，终止编译"
    exit 1
}

# 读取锁里 "owner/repo@branch" 对应的提交；没有锁则输出空
LOCK_SHA() {
    [ -n "${ZN_LOCK_FILE:-}" ] && [ -f "$ZN_LOCK_FILE" ] || return 0
    awk -v k="$1" '$1=="pkg" && $2==k {print $3; exit}' "$ZN_LOCK_FILE"
}

# ============================================================
# 通用文件下载函数
# 用法：DOWNLOAD_FILE "源URL" "目标文件"
# ============================================================
DOWNLOAD_FILE() {
    local URL="$1"
    local DEST="$2"

    echo "[Download] $URL"
    echo "[Download] -> $DEST"

    mkdir -p "$(dirname "$DEST")"

    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$DEST" "$URL"; then
        echo "[ERROR] Download failed: $URL"
        return 1
    fi

    if [ ! -s "$DEST" ]; then
        echo "[ERROR] Downloaded file is empty: $DEST"
        return 1
    fi
}

# ============================================================
# 安装和更新软件包（单仓库 / 大杂烩仓库模糊提取）
# 用法：UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选" "额外删除名称列表，可选"
# ============================================================
UPDATE_PACKAGE() {
    local PKG_NAME="$1"
    local PKG_REPO="$2"
    local PKG_BRANCH="$3"
    local PKG_SPECIAL="${4:-}"
    local EXTRA_NAMES="${5:-}"
    local REPO_NAME="${PKG_REPO#*/}"
    local REPO_PATH="./.package-repos/$REPO_NAME"

    local PKG_LIST=("$PKG_NAME")
    if [ -n "$EXTRA_NAMES" ]; then
        local EXTRA_LIST=()
        read -r -a EXTRA_LIST <<< "$EXTRA_NAMES"
        PKG_LIST+=("${EXTRA_LIST[@]}")
    fi

    echo
    echo "[ZN-Packages] Updating $PKG_NAME from $PKG_REPO@$PKG_BRANCH"

    # 克隆仓库到 package 目录之外的临时位置，避免污染编译树
    rm -rf "$REPO_PATH"
    mkdir -p "$(dirname "$REPO_PATH")"

    if ! RETRY git clone --depth=1 --single-branch \
        --branch "$PKG_BRANCH" \
        "https://github.com/$PKG_REPO.git" \
        "$REPO_PATH"; then
        echo "[ERROR] Failed to clone: $PKG_REPO"
        rm -rf "$REPO_PATH"
        return 1
    fi

    # 锁定回退：固定到上次成功编译时的提交
    local PIN
    PIN="$(LOCK_SHA "$PKG_REPO@$PKG_BRANCH")"
    if [ -n "$PIN" ] && [ "$(git -C "$REPO_PATH" rev-parse HEAD)" != "$PIN" ]; then
        if git -C "$REPO_PATH" fetch --depth=1 origin "$PIN" \
            && git -C "$REPO_PATH" checkout -q "$PIN"; then
            echo "[ZN-Packages] $PKG_REPO 已固定到锁定提交 ${PIN:0:12}"
        else
            echo "[ZN-Packages] 警告：无法取得锁定提交 $PIN，使用分支最新"
        fi
    fi
    echo "pkg $PKG_REPO@$PKG_BRANCH $(git -C "$REPO_PATH" rev-parse HEAD)" >> "$PKG_LOCK_OUT"

    # 克隆成功之后才删除 feeds 里的同名旧包，避免失败时两头落空
    for NAME in "${PKG_LIST[@]}"; do
        echo "[ZN-Packages] Searching directory: $NAME"
        local FOUND=0
        while IFS= read -r -d '' DIR; do
            rm -rf "$DIR"
            echo "[ZN-Packages] Deleted directory: $DIR"
            FOUND=1
        done < <(
            find ./feeds/luci ./feeds/packages ./package \
                -maxdepth 4 -type d \
                -iname "*${NAME}*" -print0 2>/dev/null
        )
        [ "$FOUND" -eq 1 ] || echo "[ZN-Packages] Not found directory: $NAME"
    done


    if [ "$PKG_SPECIAL" = "pkg" ]; then
        # 从大杂烩仓库中单独提取匹配的包目录
        local IMPORTED=0
        while IFS= read -r -d '' DIR; do
            cp -a "$DIR" ./package/
            echo "[ZN-Packages] Imported: $DIR"
            IMPORTED=1
        done < <(
            find "$REPO_PATH" -type d \
                -iname "*${PKG_NAME}*" -print0
        )

        if [ "$IMPORTED" -eq 0 ]; then
            echo "[ERROR] Package directory not found: $PKG_NAME"
            rm -rf "$REPO_PATH"
            return 1
        fi

        rm -rf "$REPO_PATH"
    else
        cp -a "$REPO_PATH" "./package/$REPO_NAME"
        rm -rf "$REPO_PATH"
    fi

    echo "[ZN-Packages] $PKG_NAME imported."
}

# ============================================================
# 从多软件包集合仓库精确提取指定包目录（递归支持子目录）
# 用法：IMPORT_PACKAGE_FROM_REPO "包目录名" "仓库地址" "分支，默认 main"
# ============================================================
IMPORT_PACKAGE_FROM_REPO() {
    local PKG_DIR="$1"
    local PKG_REPO="$2"
    local PKG_BRANCH="${3:-main}"
    local TMP_DIR="./.package-repos/${PKG_REPO##*/}"

    echo
    echo "[ZN-Packages] Importing $PKG_DIR from $PKG_REPO@$PKG_BRANCH"

    rm -rf "$TMP_DIR"
    mkdir -p "$(dirname "$TMP_DIR")"

    if ! RETRY git clone --depth=1 --filter=blob:none --no-checkout \
        --single-branch --branch "$PKG_BRANCH" \
        "https://github.com/$PKG_REPO.git" \
        "$TMP_DIR"; then
        echo "[ERROR] Failed to clone: $PKG_REPO"
        rm -rf "$TMP_DIR"
        return 1
    fi

    # 锁定回退：固定到上次成功编译时的提交
    local PIN CHECKOUT_REF="$PKG_BRANCH"
    PIN="$(LOCK_SHA "$PKG_REPO@$PKG_BRANCH")"
    if [ -n "$PIN" ]; then
        if git -C "$TMP_DIR" fetch --depth=1 origin "$PIN"; then
            CHECKOUT_REF="$PIN"
            echo "[ZN-Packages] $PKG_REPO 已固定到锁定提交 ${PIN:0:12}"
        else
            echo "[ZN-Packages] 警告：无法取得锁定提交 $PIN，使用分支最新"
        fi
    fi

    if ! git -C "$TMP_DIR" sparse-checkout init --cone; then
        echo "[ERROR] Failed to initialize sparse checkout"
        rm -rf "$TMP_DIR"
        return 1
    fi

    if ! git -C "$TMP_DIR" sparse-checkout set "$PKG_DIR"; then
        echo "[ERROR] Package path not found: $PKG_DIR"
        rm -rf "$TMP_DIR"
        return 1
    fi

    # 关键补丁：sparse-checkout 只写配置，需要 checkout 才会真正取回文件
    if ! git -C "$TMP_DIR" checkout -q "$CHECKOUT_REF"; then
        echo "[ERROR] Checkout failed: $PKG_BRANCH"
        rm -rf "$TMP_DIR"
        return 1
    fi

    if [ ! -f "$TMP_DIR/$PKG_DIR/Makefile" ]; then
        echo "[ERROR] Makefile not found: $TMP_DIR/$PKG_DIR/Makefile"
        rm -rf "$TMP_DIR"
        return 1
    fi

    echo "pkg $PKG_REPO@$PKG_BRANCH $(git -C "$TMP_DIR" rev-parse HEAD)" >> "$PKG_LOCK_OUT"

    # 成功取回之后才删除 feeds 里的同名旧包
    while IFS= read -r -d '' DIR; do
        rm -rf "$DIR"
        echo "[ZN-Packages] Deleted directory: $DIR"
    done < <(
        find ./feeds/luci ./feeds/packages ./package \
            -maxdepth 4 -type d \
            -iname "*${PKG_DIR}*" -print0 2>/dev/null
    )

    cp -a "$TMP_DIR/$PKG_DIR" "./package/"
    rm -rf "$TMP_DIR"

    echo "[ZN-Packages] $PKG_DIR imported successfully."
}

# ============================================================
# 软件包调用列表
# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选，从大杂烩中单独提取包名插件"
# ============================================================
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "footstrap" "VizzleTF/luci-theme-footstrap" "main"

UPDATE_PACKAGE "openwrt-bandix" "timsaya/openwrt-bandix" "main" "" "openwrt-bandix" || SOFT_FAIL "openwrt-bandix"
UPDATE_PACKAGE "luci-app-bandix" "timsaya/luci-app-bandix" "main" "" "luci-app-bandix" || SOFT_FAIL "luci-app-bandix"
UPDATE_PACKAGE "luci-app-cpu-perf" "gSpotx2f/luci-app-cpu-perf" "master" || HARD_FAIL "luci-app-cpu-perf"
UPDATE_PACKAGE "luci-app-homeproxy" "htcnokia/luci-app-homeproxy-pro" "add-featyre" || HARD_FAIL "luci-app-homeproxy"
UPDATE_PACKAGE "luci-app-timecontrol" "gaobin89/luci-app-timecontrol" "js" "" "timecontrol" || SOFT_FAIL "luci-app-timecontrol"
UPDATE_PACKAGE "luci-app-gecoosac" "laipeng668/luci-app-gecoosac" "main" "" "gecoosac" || SOFT_FAIL "luci-app-gecoosac"


#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/ZN-PPE-PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/ZN-PPE-PRIVATE.sh"
fi
