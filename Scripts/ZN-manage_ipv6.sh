#!/bin/sh
# ImmortalWrt / OpenWrt IPv6 管理腳本 v2 (PPPoE + DHCPv6-PD)
# 用法: manage_ipv6.sh [enable|disable [--hard]|check|detect|dns|rollback]

[ "$(id -u)" -eq 0 ] || { echo "錯誤：請使用 root 權限運行此腳本"; exit 1; }

ACTION="$1"
OPT="$2"
BAK_DIR="/etc/ipv6-manager-backup"
IPV4_TEST_HOSTS="223.5.5.5 114.114.114.114 1.1.1.1"
IPV6_TEST_HOSTS="2400:3200::1 2001:4860:4860::8888"
NEED_REDIAL=0

# ---------- 工具函式 ----------
jf()  { jsonfilter -e "$1" 2>/dev/null; }
ifs() { ifstatus "$1" 2>/dev/null; }

l3dev() { ifs "$1" | jf '@.l3_device'; }

WAN_IF="$(l3dev wan)";  [ -z "$WAN_IF" ] && WAN_IF="pppoe-wan"
LAN_IF="$(l3dev lan)";  [ -z "$LAN_IF" ] && LAN_IF="br-lan"

human_time() {
    [ -z "$1" ] && { echo "未知"; return; }
    echo "$(($1 / 3600)) 小時 $(($1 % 3600 / 60)) 分"
}

gen_ula() {
    # 以核心 UUID 當隨機來源（BusyBox 不一定有 od/hexdump），取 10 位十六進位 = 40 bit
    h="$(tr -d '-' < /proc/sys/kernel/random/uuid 2>/dev/null | cut -c1-10)"
    [ "${#h}" -eq 10 ] || return 1
    printf 'fd%s:%s:%s::/48' "$(echo "$h" | cut -c1-2)" "$(echo "$h" | cut -c3-6)" "$(echo "$h" | cut -c7-10)"
}

backup_config() {
    mkdir -p "$BAK_DIR"
    cp -f /etc/config/network "$BAK_DIR/network.bak"
    cp -f /etc/config/dhcp    "$BAK_DIR/dhcp.bak"
    echo "已備份設定至 $BAK_DIR"
}

check_deps() {
    command -v odhcp6c >/dev/null 2>&1 || \
        echo "[警告] 找不到 odhcp6c，請執行: apk add odhcp6c"
    [ -x /etc/init.d/odhcpd ] || \
        echo "[警告] 找不到 odhcpd，請執行: apk add odhcpd"
}

ipv4_ok() {
    for h in $IPV4_TEST_HOSTS; do
        ping -4 -c 1 -W 2 "$h" >/dev/null 2>&1 && return 0
    done
    return 1
}

ipv6_ok() {
    for h in $IPV6_TEST_HOSTS; do
        ping -6 -c 1 -W 3 "$h" >/dev/null 2>&1 && return 0
    done
    return 1
}

wait_ipv4() {
    i=0
    while [ "$i" -lt "$1" ]; do
        ipv4_ok && return 0
        sleep 3; i=$((i + 3))
    done
    return 1
}

wait_pd() {
    i=0
    while [ "$i" -lt "$1" ]; do
        [ -n "$(ifs wan6 | jf '@["ipv6-prefix"][0].address')" ] && return 0
        sleep 3; i=$((i + 3))
    done
    return 1
}

# 讀取目前 PD 與鏈路資訊到全域變數
read_state() {
    PD_ADDR="$(ifs wan6 | jf '@["ipv6-prefix"][0].address')"
    PD_MASK="$(ifs wan6 | jf '@["ipv6-prefix"][0].mask')"
    PD_PREF="$(ifs wan6 | jf '@["ipv6-prefix"][0].preferred')"
    PD_VALID="$(ifs wan6 | jf '@["ipv6-prefix"][0].valid')"
    WAN_UPTIME="$(ifs wan | jf '@.uptime')"
    WAN_MTU="$(ip link show dev "$WAN_IF" 2>/dev/null | sed -n 's/.*mtu \([0-9]*\).*/\1/p')"
    WAN_GLOBAL6="$(ip -6 addr show dev "$WAN_IF" scope global 2>/dev/null | grep inet6)"
    CFG_WAN6OPT="$(uci -q get network.wan.ipv6)"
    CFG_WAN6PROTO="$(uci -q get network.wan6.proto)"
    CFG_RA="$(uci -q get dhcp.lan.ra)"
    CFG_DHCPV6="$(uci -q get dhcp.lan.dhcpv6)"
}

# 套用設定：只 reload 有變動的介面；PPPoE 區段未改時不會重撥
safe_apply() {
    echo "正在套用設定..."
    /etc/init.d/network reload
    sleep 3
    /etc/init.d/odhcpd restart
    /etc/init.d/dnsmasq restart
    echo "等待 IPv4 連線（最長 60 秒）..."
    if ! wait_ipv4 60; then
        echo "[錯誤] IPv4 連線未恢復，自動還原備份！"
        do_rollback
        exit 1
    fi
    echo "[OK] IPv4 連線正常"
}

do_rollback() {
    if [ -f "$BAK_DIR/network.bak" ] && [ -f "$BAK_DIR/dhcp.bak" ]; then
        cp -f "$BAK_DIR/network.bak" /etc/config/network
        cp -f "$BAK_DIR/dhcp.bak"    /etc/config/dhcp
        /etc/init.d/network reload
        sleep 3
        /etc/init.d/odhcpd restart
        /etc/init.d/dnsmasq restart
        echo "已還原至備份設定。"
    else
        echo "找不到備份檔 ($BAK_DIR)。"
        return 1
    fi
}

warn_redial() {
    echo "[注意] 此操作會修改 PPPoE 設定，將重新撥號一次（5 秒後開始，Ctrl-C 可取消）"
    sleep 5
}

# ---------- 運營商/鏈路參數偵測 ----------
do_detect() {
    read_state
    echo "--- ISP / 鏈路參數偵測 ---"
    echo "   PPPoE 裝置      : $WAN_IF (MTU ${WAN_MTU:-未知})"
    echo "   PPPoE 在線時長  : $(human_time "$WAN_UPTIME")"
    echo "   keepalive 設定  : $(uci -q get network.wan.keepalive || echo 未設定)"
    if [ -n "$PD_ADDR" ]; then
        echo "   委派前綴 (PD)   : $PD_ADDR/$PD_MASK"
        echo "   前綴租期        : preferred=${PD_PREF:-?}s valid=${PD_VALID:-?}s"
        if [ "$PD_MASK" -gt 64 ] 2>/dev/null; then
            echo "   [警告] 委派前綴長於 /64，LAN 無法分得完整 /64，SLAAC 會失效。"
        else
            echo "   建議 ip6assign  : 64（/$PD_MASK 可切出 $((1 << (64 - PD_MASK))) 個 /64 子網）"
        fi
        if [ -n "$PD_VALID" ] && [ "$PD_VALID" -lt 1800 ] 2>/dev/null; then
            echo "   [提示] 租期偏短，若頻繁更新前綴請留意 odhcp6c 日誌。"
        fi
    else
        echo "   委派前綴 (PD)   : 未取得"
        echo "   [提示] 若 wan6 已啟用仍無 PD，需向運營商確認是否開通 IPv6 前綴委派。"
        echo "          不建議用 NDP relay 硬撐，PPP 鏈路上容易引發 ND 風暴。"
    fi
}

# ---------- 診斷 ----------
do_check() {
    read_state
    echo "=========================================="
    echo "【ImmortalWrt IPv6 狀態診斷報告】"
    echo "時間: $(date '+%F %T')"
    echo "=========================================="

    echo "1. WAN 介面 ($WAN_IF) IPv6 位址:"
    if [ -n "$WAN_GLOBAL6" ]; then
        echo "   [OK] 已取得全域 IPv6 位址："
        echo "$WAN_GLOBAL6" | sed 's/^/     /'
    else
        echo "   [提示] 無全域 IPv6 位址。"
    fi
    echo ""

    do_detect
    echo ""

    echo "2. IPv6 預設路由:"
    GW6="$(ip -6 route show default 2>/dev/null)"
    if [ -n "$GW6" ]; then
        echo "   [OK]"; echo "$GW6" | sed 's/^/     /'
    else
        echo "   [提示] 未檢測到預設 IPv6 路由。"
    fi
    echo ""

    echo "3. 設定值:"
    echo "   - network.wan.ipv6   : ${CFG_WAN6OPT:-未設定(auto)}"
    echo "   - network.wan6.proto : ${CFG_WAN6PROTO:-未設定}"
    echo "   - lan.ip6assign      : $(uci -q get network.lan.ip6assign || echo 未設定)"
    echo "   - ULA 前綴           : $(uci -q get network.globals.ula_prefix || echo 未設定)"
    echo "   - dhcp.lan.ra        : ${CFG_RA:-未設定}"
    echo "   - dhcp.lan.dhcpv6    : ${CFG_DHCPV6:-未設定}"
    echo "   - filter_aaaa        : $(uci -q get dhcp.@dnsmasq[0].filter_aaaa || echo 未設定)"
    LAN_GLOBAL="$(ip -6 addr show dev "$LAN_IF" scope global 2>/dev/null | grep inet6)"
    if [ -n "$LAN_GLOBAL" ]; then
        echo "   [OK] $LAN_IF 位址："; echo "$LAN_GLOBAL" | sed 's/^/     /'
    else
        echo "   [提示] $LAN_IF 無全域/ULA 位址。"
    fi
    echo ""

    echo "4. 服務與連線:"
    for s in odhcpd dnsmasq; do
        if pidof "$s" >/dev/null 2>&1; then echo "   [OK] $s 運行中"
        else echo "   [提示] $s 未運行"; fi
    done
    check_deps
    ipv4_ok && echo "   [OK] IPv4 連線正常" || echo "   [警告] IPv4 連線異常"
    ipv6_ok && echo "   [OK] IPv6 連線正常" || echo "   [提示] IPv6 無法連線"
    echo ""

    echo "5. 設定與實際狀態一致性診斷:"
    PROBLEM=0
    if [ "$CFG_WAN6OPT" = "0" ] && [ -n "$WAN_GLOBAL6" ]; then
        echo "   [不一致] wan.ipv6=0，但 WAN 仍有 IPv6：PPPoE 撥號時 IPv6 是開著的，設定改後沒有重撥。"
        PROBLEM=1
    fi
    if [ "$CFG_WAN6OPT" = "0" ] && [ -n "$CFG_WAN6PROTO" ]; then
        echo "   [不一致] wan.ipv6=0 但 wan6 仍存在。"
        PROBLEM=1
    fi
    if [ -n "$PD_ADDR" ] && [ "$CFG_RA" != "server" ]; then
        echo "   [半殘] 路由器已取得 PD，但 LAN 未廣播 RA：內網裝置不會有 IPv6。"
        if [ "$CFG_WAN6OPT" = "0" ]; then
            echo "          → 執行 '$0 enable' 補齊（因 wan.ipv6=0，需重撥一次）。"
        else
            echo "          → 執行 '$0 enable' 補齊（不會重撥）。"
        fi
        PROBLEM=1
    fi
    if [ "$CFG_RA" = "server" ] && [ -z "$PD_ADDR" ]; then
        echo "   [異常] LAN 已廣播 RA，但沒有 PD 前綴：請查看 odhcp6c 日誌或洽 ISP。"
        PROBLEM=1
    fi
    ULA_CFG="$(uci -q get network.globals.ula_prefix)"
    if [ -n "$ULA_CFG" ]; then
        ULA_HEAD="$(echo "$ULA_CFG" | cut -d: -f1-3 | sed 's/:0\{1,3\}\([0-9a-f]\)/:\1/g')"
        if ! ip -6 addr show dev "$LAN_IF" 2>/dev/null | grep -qi "inet6 $ULA_HEAD:"; then
            echo "   [提示] 已設定 ULA ($ULA_CFG)，但 $LAN_IF 上沒有對應位址（不影響上網）。"
            LAN_CLASS="$(uci -q get network.lan.ip6class)"
            if [ -n "$LAN_CLASS" ] && ! echo "$LAN_CLASS" | grep -qw 'local'; then
                echo "          原因: network.lan.ip6class='$LAN_CLASS' 未包含 local，ULA 被排除。"
                echo "          修正: uci add_list network.lan.ip6class='local'; uci commit network"
            fi
            echo "          之後執行: ifdown lan; ifup lan（SSH 會短暫斷線，PPPoE 不受影響）"
            PROBLEM=1
        fi
    fi
    [ "$PROBLEM" -eq 0 ] && echo "   [OK] 未發現設定與狀態不一致。"
    echo ""

    echo "6. 近期 PPPoE 斷線線索（用來判斷重撥是否與 IPv6 有關）:"
    LOGS="$(logread 2>/dev/null | grep -E 'pppd|pppoe-wan|odhcp6c' | \
        grep -Ei 'terminat|echo|timeout|IPV6CP|LCP|hangup|link is down|Connection' | tail -n 8)"
    if [ -n "$LOGS" ]; then
        echo "$LOGS" | sed 's/^/     /'
        echo "   判讀參考:"
        echo "     含 IPV6CP 的失敗/逾時      → ISP 端 IPv6CP 協商異常，考慮 disable --hard"
        echo "     'No response to ... echo'  → 鏈路被 BNG 靜默丟包，嘗試調整 keepalive"
        echo "     'terminated by peer'       → ISP 端主動斷線（與本機 IPv6 設定無關的機率較高）"
        echo "     'Terminating on signal 15' → 本機 netifd 主動終止 pppd（ifdown/network reload/restart），不是 ISP"
        N_SIG="$(logread 2>/dev/null | grep -c 'pppd.*Terminating on signal')"
        N_ECHO="$(logread 2>/dev/null | grep -Eic 'pppd.*(echo-request|Peer not responding)')"
        N_PEER="$(logread 2>/dev/null | grep -Eic 'pppd.*(terminated by peer|Modem hangup)')"
        echo "   統計: 本機終止=${N_SIG} 次 / echo 逾時=${N_ECHO} 次 / 對端斷線=${N_PEER} 次"
        if [ "$N_SIG" -gt 0 ] && [ "$N_ECHO" -eq 0 ] && [ "$N_PEER" -eq 0 ]; then
            echo "   → 日誌中的斷線全部由本機觸發，與 ISP 或 IPv6 協商無關。"
            echo "     找觸發者: logread | grep -B8 'Terminating on signal'"
            echo "     也檢查: crontab -l ; ls /etc/hotplug.d/iface /etc/init.d | grep -Ei 'mwan|ddns|watch'"
        fi
    else
        echo "   [OK] 日誌中沒有明顯的斷線記錄（logread 僅保存近期內容）。"
    fi
    do_dns_check
    echo "=========================================="
}

# ---------- DNS 對齊檢查（唯讀，不修改任何設定） ----------
run_ns() {
    if command -v timeout >/dev/null 2>&1; then timeout 5 nslookup "$@"; else nslookup "$@"; fi
}

do_dns_check() {
    echo ""
    echo "7. DNS 對齊檢查（僅診斷，不修改設定）:"
    LAN_IP4="$(ifs lan | jf '@["ipv4-address"][0].address')"
    DHCP_OPT="$(uci -q get dhcp.lan.dhcp_option)"
    RA_DNS="$(uci -q get dhcp.lan.dns)"
    NORESOLV="$(uci -q get dhcp.@dnsmasq[0].noresolv)"
    SERVERS="$(uci -q get dhcp.@dnsmasq[0].server)"
    W_PEER="$(uci -q get network.wan.peerdns)";   W_DNS="$(uci -q get network.wan.dns)"
    W6_PEER="$(uci -q get network.wan6.peerdns)"; W6_DNS="$(uci -q get network.wan6.dns)"

    echo "   客戶端 IPv4 DNS (DHCP option 6) : ${DHCP_OPT:-未指定（預設=路由器 ${LAN_IP4:-?}）}"
    echo "   客戶端 IPv6 DNS (RA/RDNSS)      : ${RA_DNS:-未指定（預設=路由器自身）}"
    echo "   dnsmasq 上游設定                : noresolv=${NORESOLV:-0} server=${SERVERS:-無}"
    echo "   wan  peerdns / dns              : ${W_PEER:-預設(1)} / ${W_DNS:-無}"
    echo "   wan6 peerdns / dns              : ${W6_PEER:-預設(1)} / ${W6_DNS:-無}"
    if [ -s /tmp/resolv.conf.d/resolv.conf.auto ]; then
        echo "   實際自動取得的上游 (resolv.conf.auto):"
        grep nameserver /tmp/resolv.conf.d/resolv.conf.auto | sed 's/^/     /'
    fi
    L53="$(netstat -lnp 2>/dev/null | grep -E ':53[[:space:]]' | head -n 10)"
    [ -n "$L53" ] && { echo "   53 埠監聽者:"; echo "$L53" | sed 's/^/     /'; }
    for p in AdGuardHome smartdns mosdns clash mihomo; do
        pidof "$p" >/dev/null 2>&1 && echo "   [提示] 偵測到 DNS 相關程式運行中: $p（請確認其 IPv6 / AAAA 處理與劫持規則）"
    done
    REDIR="$(uci show firewall 2>/dev/null | grep -E "(src_dport|dest_port)='?53'?")"
    [ -n "$REDIR" ] && echo "   [提示] 防火牆有 53 埠重定向規則，請確認其 family 涵蓋 IPv6，否則客戶端走 IPv6 查詢會繞過。"

    DNS_WARN=0
    if pidof sing-box >/dev/null 2>&1; then
        HP_OPTS="$(uci show homeproxy 2>/dev/null | grep -E '\.(ipv6_support|proxy_mode|dns_strategy)=')"
        echo "   [提示] sing-box 運行中（HomeProxy 類外掛），相關設定:"
        if [ -n "$HP_OPTS" ]; then
            echo "$HP_OPTS" | sed 's/^/     /'
            if echo "$HP_OPTS" | grep -Eq "\.ipv6_support='?0'?" && [ "$(uci -q get dhcp.@dnsmasq[0].filter_aaaa)" != "1" ]; then
                echo "   [風險] HomeProxy 未啟用 IPv6 支援，但 DNS 仍回傳 AAAA：指定走代理的網域可能經 IPv6 直連而繞過代理。"
                DNS_WARN=1
            fi
        else
            echo "     （找不到 ipv6_support 等選項，此 fork 可能使用不同名稱，請在 LuCI 手動確認其 IPv6 設定）"
        fi
    fi
    if [ "$W_PEER" = "0" ] && [ "$W6_PEER" != "0" ]; then
        echo "   [不一致] wan 使用自訂 DNS，但 wan6 仍接收 ISP 的 IPv6 DNS，兩套上游會混用。"
        echo "            建議: uci set network.wan6.peerdns='0'（並自行指定 IPv6 上游）; uci commit network"
        DNS_WARN=1
    fi
    if echo "$DHCP_OPT" | grep -Eq '(^|[[:space:]])(6|option:dns-server),' && [ -z "$RA_DNS" ]; then
        echo "   [不一致] IPv4 客戶端被指定了其他 DNS，但 IPv6 的 RDNSS 仍指向路由器，同一裝置 v4/v6 走不同解析器。"
        DNS_WARN=1
    fi

    # 功能測試：經由路由器自身的 IPv6 位址查詢 AAAA
    T6="$(ip -6 addr show dev "$LAN_IF" scope global 2>/dev/null | sed -n 's/.*inet6 \([0-9a-f:]*\)\/.*/\1/p')"
    T6_ULA="$(echo "$T6" | grep -i '^fd' | head -n1)"
    [ -z "$T6_ULA" ] && T6_ULA="$(echo "$T6" | head -n1)"
    if command -v nslookup >/dev/null 2>&1; then
        if run_ns -type=A www.baidu.com 127.0.0.1 2>/dev/null | grep -i 'address' | grep -v '127.0.0.1' | grep -q '[0-9]'; then
            echo "   [OK] 本機 DNS（IPv4 路徑）可解析"
        else
            echo "   [警告] 本機 DNS（127.0.0.1）解析失敗"; DNS_WARN=1
        fi
        if [ -n "$T6_ULA" ]; then
            if run_ns -type=AAAA ipv6.baidu.com "$T6_ULA" 2>/dev/null | grep -i 'address' | grep -v "$T6_ULA" | grep -q ':'; then
                echo "   [OK] 透過 IPv6 位址 ($T6_ULA) 查詢 AAAA 成功（客戶端走 IPv6 查 DNS 的路徑可用）"
            else
                echo "   [警告] 透過 IPv6 位址查詢 AAAA 失敗：客戶端用 IPv6 查 DNS 時可能逾時"; DNS_WARN=1
            fi
        fi
    fi
    # 差異測試：上游有 AAAA 而本機沒有 → AAAA 在本機被過濾
    if command -v nslookup >/dev/null 2>&1; then
        UP_AAAA="$(run_ns -type=AAAA ipv6.baidu.com 223.5.5.5 2>/dev/null | grep -i 'address' | grep -v '223.5.5.5' | grep -c ':')"
        LO_AAAA="$(run_ns -type=AAAA ipv6.baidu.com 127.0.0.1 2>/dev/null | grep -i 'address' | grep -v '127.0.0.1' | grep -c ':')"
        if [ "$UP_AAAA" -gt 0 ] && [ "$LO_AAAA" -eq 0 ]; then
            echo "   [警告] 上游 DNS 有 AAAA，但本機 DNS 回傳為空：AAAA 在本機被過濾（dnsmasq 或代理外掛的 DNS 策略）。"
            echo "          使用路由器 DNS 的客戶端實際上只會走 IPv4。"
            DNS_WARN=1
        fi
    fi
    [ "$DNS_WARN" -eq 0 ] && echo "   [OK] 未發現 DNS 不一致。"
}

# ---------- 主流程 ----------
case "$ACTION" in
    enable)
        echo "正在啟用 IPv6..."
        check_deps
        read_state
        backup_config

        # 僅在 wan.ipv6 被明確設為 0 時才動 PPPoE 區段（會重撥一次）
        if [ "$CFG_WAN6OPT" = "0" ]; then
            warn_redial
            uci set network.wan.ipv6='1'
        fi

        uci set network.wan6='interface'
        uci set network.wan6.device='@wan'
        uci set network.wan6.proto='dhcpv6'
        uci set network.wan6.reqaddress='try'
        uci set network.wan6.reqprefix='auto'
        uci -q delete network.wan6.auto

        uci set network.lan.ip6assign='64'
        # 若 lan 限制了 ip6class 卻沒包含 local，ULA 會被排除；補上 local
        LAN_CLASS="$(uci -q get network.lan.ip6class)"
        if [ -n "$LAN_CLASS" ] && ! echo "$LAN_CLASS" | grep -qw 'local'; then
            uci add_list network.lan.ip6class='local'
            echo "已在 network.lan.ip6class 補上 local（允許 ULA 分配）"
        fi

        uci set dhcp.lan.ra='server'
        uci set dhcp.lan.dhcpv6='server'
        uci set dhcp.lan.ra_slaac='1'
        uci set dhcp.lan.ra_management='1'
        uci -q delete dhcp.lan.ndp
        uci set dhcp.@dnsmasq[0].filter_aaaa='0'

        if [ -z "$(uci -q get network.globals.ula_prefix)" ]; then
            ULA="$(gen_ula)"
            if [ -n "$ULA" ]; then
                uci set network.globals='globals'
                uci set network.globals.ula_prefix="$ULA"
                echo "已產生 ULA 前綴: $ULA"
            else
                echo "[警告] 無法產生 ULA 前綴，已略過（不影響 IPv6 功能）。"
            fi
        fi

        uci commit network
        uci commit dhcp
        safe_apply

        echo "等待運營商委派前綴（最長 45 秒）..."
        if wait_pd 45; then
            echo "[OK] 已取得 PD 前綴"
        else
            echo "[警告] 45 秒內未取得 PD 前綴，請向 ISP 確認是否開通。"
        fi
        do_detect
        echo "完成。建議稍後執行: $0 check"
        ;;

    disable)
        echo "正在停用 IPv6..."
        read_state
        backup_config

        uci -q delete network.wan6
        uci -q delete network.lan.ip6assign
        uci -q delete network.globals.ula_prefix

        uci set dhcp.lan.ra='disabled'
        uci set dhcp.lan.dhcpv6='disabled'
        uci set dhcp.lan.ndp='disabled'
        uci -q delete dhcp.lan.ra_slaac
        uci -q delete dhcp.lan.ra_management
        uci set dhcp.@dnsmasq[0].filter_aaaa='1'

        if [ "$OPT" = "--hard" ]; then
            warn_redial
            uci set network.wan.ipv6='0'
            echo "硬停用：同時關閉 PPPoE 的 IPv6CP。"
        else
            echo "軟停用：不動 PPPoE 設定（不重撥）。路由器自身 WAN 可能仍保留 IPv6CP 位址；"
            echo "         如需完全關閉請使用: $0 disable --hard"
        fi

        uci commit network
        uci commit dhcp
        safe_apply
        echo "已停用 LAN 端 IPv6。"
        ;;

    check|status)
        do_check
        ;;

    detect)
        do_detect
        ;;

    dns)
        do_dns_check
        ;;

    rollback)
        do_rollback
        ;;

    *)
        echo "用法: $0 [enable|disable [--hard]|check|detect|rollback]"
        echo "  enable          - 啟用 PD + LAN RA/DHCPv6（wan.ipv6 未被關閉時不會重撥）"
        echo "  disable         - 軟停用：關閉 wan6 與 LAN 廣播，不動 PPPoE（不重撥）"
        echo "  disable --hard  - 另外關閉 PPPoE 的 IPv6CP（會重撥一次）"
        echo "  check           - 完整診斷（含設定一致性與斷線日誌線索）"
        echo "  detect          - 僅顯示運營商/鏈路參數"
        echo "  dns             - 僅執行 DNS 對齊檢查（唯讀）"
        echo "  rollback        - 還原最近一次備份"
        exit 1
        ;;
esac
