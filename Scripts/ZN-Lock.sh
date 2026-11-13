#!/usr/bin/env bash
# Scripts/ZN-Lock.sh —— "上次成功的上游版本"锁
#
# 锁文件内容（纯文本，每行一条）:
#   source <repo-url> <sha>        编译源码仓库的提交
#   feed   <name> <url> <sha>      feeds（packages/luci/...）的提交
#   pkg    <owner/repo@branch> <sha>   ZN-Packages.sh 拉取的第三方包提交
#
# 存放位置：本仓库的孤立分支 zn-lock，文件名 <WRT_CONFIG>.lock
# （不放 Release/Tag，避免被 Auto-Clean 清理掉）
#
# 用法:
#   ZN-Lock.sh gen <输出文件>        # 只生成锁文件（调试用）
#   ZN-Lock.sh save                 # 在 wrt/ 内执行：生成锁并推送到 zn-lock 分支
#   ZN-Lock.sh fetch <输出文件>      # 下载锁文件；不存在返回 1
#   ZN-Lock.sh source <锁文件>       # 打印 source 的 sha
#   ZN-Lock.sh feeds <锁文件>        # 在 wrt/ 内执行：把 feeds.conf.default 固定到锁里的提交

set -uo pipefail

LOCK_BRANCH="zn-lock"
CMD="${1:-}"

gen_lock() {                                   # gen_lock <输出文件>
    local out="$1" conf kind name url _rest base sha
    conf="feeds.conf"; [ -f "$conf" ] || conf="feeds.conf.default"
    {
        echo "# ZN lock $(date -u +%FT%TZ) config=${WRT_CONFIG:-?}"
        echo "source ${WRT_REPO:-?} ${WRT_HASH:-?}"
        while read -r kind name url _rest; do
            case "$kind" in src-git|src-git-full) ;; *) continue ;; esac
            base="${url%%[;^]*}"
            sha="$(git -C "feeds/$name" rev-parse HEAD 2>/dev/null)" || continue
            echo "feed $name $base $sha"
        done < <(grep -E '^src-git' "$conf")
        [ -f .zn-pkg.lock ] && cat .zn-pkg.lock
    } > "$out"
}

case "$CMD" in
gen)
    gen_lock "${2:?output file}" ;;
save)
    : "${GITHUB_TOKEN:?need GITHUB_TOKEN}" "${GITHUB_REPOSITORY:?}" "${WRT_CONFIG:?}" "${WRT_HASH:?}"
    LOCK_TMP="${RUNNER_TEMP:-/tmp}/zn-lock-$$.txt"
    gen_lock "$LOCK_TMP"
    echo "---- lock ----"; cat "$LOCK_TMP"; echo "--------------"
    # 源码、feeds 至少要各有一条，否则不保存（避免写入无效锁）
    grep -q '^source ' "$LOCK_TMP" && grep -q '^feed ' "$LOCK_TMP" || {
        echo "[ZN-Lock] 锁内容不完整，跳过保存"; exit 0; }
    W="${RUNNER_TEMP:-/tmp}/zn-lock-repo-$$"
    rm -rf "$W"; mkdir -p "$W"; cd "$W" || exit 1
    git init -q
    git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
    if git fetch -q --depth=1 origin "$LOCK_BRANCH" 2>/dev/null; then
        git checkout -q -B "$LOCK_BRANCH" FETCH_HEAD
    else
        git checkout -q --orphan "$LOCK_BRANCH"
    fi
    cp -f "$LOCK_TMP" "./${WRT_CONFIG}.lock"
    git add "./${WRT_CONFIG}.lock"
    if git diff --cached --quiet; then
        echo "[ZN-Lock] 锁无变化"; exit 0
    fi
    git -c user.name="github-actions" -c user.email="github-actions@users.noreply.github.com" \
        commit -q -m "lock ${WRT_CONFIG}: ${WRT_HASH:0:12}"
    git push -q origin "HEAD:${LOCK_BRANCH}" && echo "[ZN-Lock] 已保存到 ${LOCK_BRANCH}/${WRT_CONFIG}.lock" \
        || { echo "::warning title=ZN-Lock::锁推送失败（不影响固件）"; exit 0; }
    ;;
fetch)
    OUT="${2:?output file}"
    : "${GITHUB_REPOSITORY:?}" "${WRT_CONFIG:?}"
    if gh api "repos/${GITHUB_REPOSITORY}/contents/${WRT_CONFIG}.lock?ref=${LOCK_BRANCH}" \
            -H "Accept: application/vnd.github.raw" > "$OUT" 2>/dev/null && [ -s "$OUT" ] \
            && grep -q '^source ' "$OUT"; then
        echo "[ZN-Lock] 已取得锁文件:"; cat "$OUT"
    else
        rm -f "$OUT"
        echo "::error title=ZN-Lock::没有可用的 last-good 锁（还没有成功编译过，或 zn-lock 分支被删除）"
        exit 1
    fi
    ;;
source)
    awk '$1=="source"{print $3; exit}' "${2:?lock file}"
    ;;
feeds)
    LOCK="${2:?lock file}"
    CONF="feeds.conf"; [ -f "$CONF" ] || CONF="feeds.conf.default"
    declare -A L=()
    while read -r k n u s _; do
        [ "$k" = "feed" ] && L["$n"]="${u}^${s}"
    done < "$LOCK"
    : > "$CONF.new"
    while IFS= read -r line; do
        set -- $line
        if [[ "${1:-}" == src-git* && -n "${L[${2:-}]:-}" ]]; then
            # 固定提交需要完整克隆，所以统一用 src-git-full
            echo "src-git-full $2 ${L[$2]}" >> "$CONF.new"
        else
            echo "$line" >> "$CONF.new"
        fi
    done < "$CONF"
    mv -f "$CONF.new" "$CONF"
    echo "[ZN-Lock] feeds 已固定到锁里的提交:"; cat "$CONF"
    ;;
*)
    echo "usage: $0 {save|fetch <file>|source <file>|feeds <file>}"; exit 2 ;;
esac
