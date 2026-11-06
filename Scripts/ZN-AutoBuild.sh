#!/usr/bin/env bash
# Scripts/ZN-AutoBuild.sh
# 在 OpenWrt 源码根目录执行（workflow 里 cd ./wrt/ 之后调用）
#
# 自愈编译：make 失败时自动分析日志，修复后重试。
#   1. 补丁失败（Patch failed! Please fix xxx.patch）
#        -> 把该补丁移出 patches 目录（仅限 feeds/ 与 package/ 下，内核/工具链补丁绝不碰），清理该包后重试
#   2. 只看到 "package/xxx failed to build" 没有补丁信息
#        -> 单独用 V=s 重跑该包，抓出真正原因再判断是不是补丁问题
#   3. 下载 / 网络 / 校验类错误
#        -> 等待后 make download 重试
#   4. 本次恢复了工具链缓存（ZN_CACHE_RESTORED=true），但失败原因无法识别
#        -> 视为缓存可能过期：删除缓存与已编译产物、完整重编一次，并删掉云端那份有问题的缓存，
#           让流程保存重新编出来的健康版本。缓存因此永远不会让一次本来能成功的编译失败
#   5. 以上都不是（可能是 -j 并发竞争）
#        -> 退回 make -j1 V=s 兜底，保持原有行为
# 所有自动处理都会写入 Job Summary，并通过 WRT_AUTOFIX 写进 Release 说明。

set -uo pipefail

MAX_ROUNDS="${ZN_AUTOFIX_ROUNDS:-8}"
ROOT="$(pwd -P)"
LOG_DIR="${RUNNER_TEMP:-/tmp}/zn-autobuild"
DISABLED_DIR="$ROOT/.ci-disabled-patches"
mkdir -p "$LOG_DIR" "$DISABLED_DIR"

FIXES=()
declare -A DIAGNOSED=()
DOWNLOAD_RETRIES=0
CACHE_PURGED=0

log()  { echo "[ZN-AutoBuild] $*"; }
warn() { echo "::warning title=ZN-AutoBuild::$*"; }

run_make() {                       # run_make <logfile> <make args...>
    local logfile="$1"; shift
    make "$@" 2>&1 | tee "$logfile"
    return "${PIPESTATUS[0]}"
}

# ---- 耗时分析 ------------------------------------------------
# OpenWrt 每个编译阶段都会打印  time: <阶段>#用户态#内核态#实际耗时(秒)
# 汇总成"各区域累计耗时 + 最慢 15 项"写进 Job Summary，不用下载日志、不用敲命令就能看出时间花在哪。
report_times() {
    local all="$LOG_DIR/all-times.txt"
    cat "$LOG_DIR"/round-*.log "$LOG_DIR"/fallback.log 2>/dev/null | grep -E '^time: ' > "$all" || true
    [ -s "$all" ] || return 0
    {
        echo
        echo "### 编译耗时分析"
        echo "按区域累计（单位：秒；并行任务会累加，数字用于比较占比，不等于总墙钟时间）："
        echo
        echo "| 区域 | 累计耗时(秒) |"
        echo "|---|---|"
        awk -F'#' '{n=$1; sub(/^time: /,"",n); split(n,p,"/"); a=p[1]; if (a=="target" && p[2]=="linux") a="target/linux"; t[a]+=$4}
                   END {for (k in t) printf "%s\t%.0f\n", k, t[k]}' "$all" \
            | sort -t$'\t' -k2 -rn | awk -F'\t' '{printf "| %s | %s |\n", $1, $2}'
        echo
        echo "最慢的 15 项："
        echo
        echo "| 耗时(秒) | 项目 |"
        echo "|---|---|"
        awk -F'#' '{n=$1; sub(/^time: /,"",n); printf "%.0f\t%s\n", $4, n}' "$all" \
            | sort -rn | head -n 15 | awk -F'\t' '{printf "| %s | `%s` |\n", $1, $2}'
    } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# ---- 报告 ----------------------------------------------------
finish() {                         # finish <success|failed>
    local state="$1" line="none"
    if [ "${#FIXES[@]}" -gt 0 ]; then
        line="$(printf '%s; ' "${FIXES[@]}")"
    fi
    {
        echo "### ZN-AutoBuild: ${state}"
        if [ "${#FIXES[@]}" -gt 0 ]; then
            echo "本次编译触发了自动修复："
            printf -- '- %s\n' "${FIXES[@]}"
            echo
            echo "> 上游修好后无需任何操作，下次会自动恢复正常；被移走的补丁备份在 \`.ci-disabled-patches/\`。"
        else
            echo "无需自动修复。"
        fi
    } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
    [ -n "${GITHUB_ENV:-}" ] && echo "WRT_AUTOFIX=${line}" >> "$GITHUB_ENV"
    report_times
    return 0
}

# ---- 修复 1：补丁失败 -----------------------------------------
# 返回 0 = 做了修复
fix_patch_failures() {
    local logfile="$1" acted=1 p rel dest
    while IFS= read -r p; do
        [ -f "$p" ] || continue
        case "$p" in
            "$ROOT"/feeds/*|"$ROOT"/package/*) ;;
            *)
                log "补丁不在 feeds/ 或 package/ 下，不自动处理: $p"
                continue ;;
        esac
        rel="${p#"$ROOT"/}"
        dest="$DISABLED_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        mv -f "$p" "$dest"
        FIXES+=("补丁与源码不匹配，已禁用: $rel")
        warn "补丁失败，已禁用: $rel"
        acted=0
    done < <(grep -oP 'Please fix \K\S+?(?=!)' "$logfile" | sort -u)
    return "$acted"
}

failed_pkgs() {                    # 从日志里抽出失败的包路径
    grep -oP 'ERROR: \Kpackage/\S+(?= failed to build)' "$1" | sort -u
}

clean_pkg() {
    make "$1/clean" >/dev/null 2>&1 || true
}

# ---- 主循环 ---------------------------------------------------
round=1
while [ "$round" -le "$MAX_ROUNDS" ]; do
    LOG="$LOG_DIR/round-$round.log"
    log "===== 第 $round 轮编译 ====="
    if run_make "$LOG" -j"$(nproc)"; then
        [ "${#FIXES[@]}" -gt 0 ] && log "编译成功（经自动修复）"
        finish success
        exit 0
    fi

    log "第 $round 轮失败，开始分析日志..."
    ACTED=1
    mapfile -t PKGS < <(failed_pkgs "$LOG")

    # (1) 日志里直接有补丁失败
    if fix_patch_failures "$LOG"; then
        ACTED=0
        for P in "${PKGS[@]}"; do clean_pkg "$P"; done
    fi

    # (2) 没有补丁信息：逐个失败包用 V=s 单独复现再判断
    if [ "$ACTED" -ne 0 ]; then
        for P in "${PKGS[@]}"; do
            [ -n "${DIAGNOSED[$P]:-}" ] && continue
            DIAGNOSED[$P]=1
            log "单独复现 $P (V=s)..."
            PLOG="$LOG_DIR/diag-${P//\//_}.log"
            run_make "$PLOG" "$P/compile" -j1 V=s >/dev/null || true
            if fix_patch_failures "$PLOG"; then
                ACTED=0
                clean_pkg "$P"
            fi
        done
    fi

    # (3) 下载 / 网络 / 校验类
    if [ "$ACTED" -ne 0 ] && [ "$DOWNLOAD_RETRIES" -lt 2 ] && \
       grep -qE 'Download failed|Hash of the downloaded file does not match|Hash check failed|Could not resolve host|Connection (timed out|reset)|curl: \([0-9]+\)|The requested URL returned error' "$LOG"; then
        DOWNLOAD_RETRIES=$((DOWNLOAD_RETRIES + 1))
        log "检测到下载类错误，等待后重试下载 ($DOWNLOAD_RETRIES/2)..."
        sleep 15
        make download -j1 V=s >"$LOG_DIR/download-retry-$DOWNLOAD_RETRIES.log" 2>&1 || true
        FIXES+=("下载/校验错误，已重试下载 ($DOWNLOAD_RETRIES)")
        ACTED=0
    fi

    # (4) 用了缓存且失败原因无法识别：缓存可能过期，清掉缓存完整重编一次
    if [ "$ACTED" -ne 0 ] && [ "${ZN_CACHE_RESTORED:-false}" = "true" ] && [ "$CACHE_PURGED" -eq 0 ]; then
        log "失败原因无法识别且本次使用了缓存，清除缓存与已编译产物后完整重编..."
        rm -rf staging_dir build_dir tmp .ccache
        if [ -n "${ZN_TC_KEY:-}" ] && command -v gh >/dev/null 2>&1; then
            gh cache delete "$ZN_TC_KEY" --repo "${GITHUB_REPOSITORY:-}" >/dev/null 2>&1 \
                && log "已删除云端工具链缓存 $ZN_TC_KEY" || true
        fi
        [ -n "${GITHUB_ENV:-}" ] && echo "ZN_CACHE_PURGED=true" >> "$GITHUB_ENV"
        CACHE_PURGED=1
        FIXES+=("失败疑似缓存过期，已清除缓存并完整重编")
        warn "失败疑似缓存过期，已清除缓存并完整重编"
        ACTED=0
    fi

    # (5) 没有任何可自动处理的：-j1 V=s 兜底（原有行为）
    if [ "$ACTED" -ne 0 ]; then
        log "未命中任何自动修复规则，退回 make -j1 V=s 兜底..."
        if run_make "$LOG_DIR/fallback.log" -j1 V=s; then
            FIXES+=("并发编译失败，-j1 重试成功")
            finish success
            exit 0
        fi
        log "兜底仍失败，错误摘要："
        grep -nE 'ERROR:|Error [0-9]+|\*\*\*|Patch failed' "$LOG_DIR/fallback.log" | tail -n 40 || true
        finish failed
        exit 1
    fi

    round=$((round + 1))
done

log "已达到最大重试轮数 ($MAX_ROUNDS)，仍未成功"
finish failed
exit 1
