#!/bin/sh
# 用法: sh zn-bench.sh <packet_steering: 0|1|2> [重複次數]
# 同時 ping 外網(223.5.5.5)與 PPPoE 對端網關；調參請以「網關」延遲為準（外網含運營商上游抖動）
MODE="${1:-0}"; RUNS="${2:-3}"
URL="https://mirrors.ustc.edu.cn/openwrt/releases/25.12.6/targets/ipq806x/generic/kernel-debug.tar.zst"
RPS="${RPS_FILE:-/sys/class/net/eth0/queues/rx-0/rps_cpus}"
INIT="${PS_INIT:-/etc/init.d/packet_steering}"
GW="$(ip -4 addr show pppoe-wan 2>/dev/null | sed -n 's/.*peer \([0-9.]*\).*/\1/p' | head -n1)"
uci set network.globals.packet_steering="$MODE"; uci commit network; "$INIT" reload
echo "== packet_steering=$MODE rps_cpus=$(cat "$RPS") 網關=${GW:-未取得} =="
n=1
while [ "$n" -le "$RUNS" ]; do
  rm -f /tmp/zb.*
  for i in 1 2 3; do curl -s -o /dev/null -m 25 -w "%{speed_download}\n" "$URL" > /tmp/zb.$i & done
  sleep 1
  ping -c 8 223.5.5.5 > /tmp/zb.ping 2>&1 &
  if [ -n "$GW" ]; then ping -c 8 "$GW" > /tmp/zb.gw 2>&1 & fi
  sleep 2
  grep '^cpu[0-9]' /proc/stat > /tmp/zb.c1; sleep 4; grep '^cpu[0-9]' /proc/stat > /tmp/zb.c2
  wait
  SP=$(cat /tmp/zb.1 /tmp/zb.2 /tmp/zb.3 2>/dev/null | awk '{s+=$1} END{printf "%.0f", s*8/1000000}')
  PG=$(grep 'round-trip' /tmp/zb.ping | sed 's/.*= //' | awk -F/ '{printf "avg %s max %s", $2, $3}')
  GP=$(grep 'round-trip' /tmp/zb.gw 2>/dev/null | sed 's/.*= //' | awk -F/ '{printf "avg %s max %s", $2, $3}')
  CP=$(awk 'NR==FNR{t=0;for(i=2;i<=11;i++)t+=$i;t1[$1]=t;i1[$1]=$5+$6;s1[$1]=$8;next}{t=0;for(i=2;i<=11;i++)t+=$i;dt=t-t1[$1];if(dt<=0)next;di=($5+$6)-i1[$1];ds=$8-s1[$1];printf "%s=%.0f/%.0f ",substr($1,4),100*(1-di/dt),100*ds/dt}' /tmp/zb.c1 /tmp/zb.c2)
  echo "第$n輪: 吞吐(各連接速度之和) ${SP} Mbit/s | 網關 ${GP:-無} | 外網 $PG | CPU(忙碌/軟中斷%) $CP"
  n=$((n+1)); sleep 5
done
