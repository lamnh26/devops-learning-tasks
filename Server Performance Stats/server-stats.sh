#!/usr/bin/env bash

set -u

# ---- helpers ----------------------------------------------------------------
 
hr()      { printf '%s\n' "------------------------------------------------------------"; }
header()  { hr; printf '  %s\n' "$1"; hr; }
bar() {
    # bar <used_pct> -> renders a 20-char [####----] gauge
    local pct=${1%.*} filled i out=""
    (( pct > 100 )) && pct=100
    (( pct < 0 )) && pct=0
    filled=$(( pct * 20 / 100 ))
    for ((i=0; i<20; i++)); do
        (( i < filled )) && out+="#" || out+="-"
    done
    printf '[%s]' "$out"
}
 
# ---- CPU usage --------------------------------------------------------------
# Sample /proc/stat twice ~1s apart and compute busy time delta.
 
cpu_usage() {
    read -r _ u n s idle io irq soft steal _ < /proc/stat
    local idle1=$((idle + io))
    local total1=$((u + n + s + idle + io + irq + soft + steal))
    sleep 1
    read -r _ u n s idle io irq soft steal _ < /proc/stat
    local idle2=$((idle + io))
    local total2=$((u + n + s + idle + io + irq + soft + steal))
 
    local dtotal=$((total2 - total1))
    local didle=$((idle2 - idle1))
    if (( dtotal <= 0 )); then echo "0.0"; return; fi
    awk -v dt="$dtotal" -v di="$didle" 'BEGIN{ printf "%.1f", (dt-di)*100/dt }'
}
 
# ---- MAIN -------------------------------------------------------------------
 
header "SERVER STATS  -  $(hostname)  -  $(date '+%Y-%m-%d %H:%M:%S %Z')"
 
# System overview
if [[ -r /etc/os-release ]]; then . /etc/os-release; fi
printf '  OS         : %s\n' "${PRETTY_NAME:-$(uname -s)}"
printf '  Kernel     : %s\n' "$(uname -r)"
printf '  Uptime     : %s\n' "$(uptime -p 2>/dev/null | sed 's/^up //' || echo n/a)"
printf '  Load avg   : %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
printf '  CPU cores  : %s\n' "$(nproc 2>/dev/null || echo '?')"
printf '  Logged in  : %s user(s)\n' "$(who 2>/dev/null | wc -l)"
 
# CPU
header "CPU USAGE"
cpu=$(cpu_usage)
printf '  Used : %5s%%   %s\n' "$cpu" "$(bar "$cpu")"
printf '  Idle : %5.1f%%\n' "$(awk -v c="$cpu" 'BEGIN{print 100-c}')"
 
# Memory
header "MEMORY USAGE"
read -r total used free _ <<<"$(free -b | awk '/^Mem:/{print $2, $3, $4}')"
mem_pct=$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.1f", (t>0)?u*100/t:0}')
h() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }
printf '  Total: %10s\n' "$(h "$total")"
printf '  Used : %10s  (%s%%)  %s\n' "$(h "$used")" "$mem_pct" "$(bar "$mem_pct")"
printf '  Free : %10s  (%s%%)\n' "$(h "$free")" "$(awk -v f="$free" -v t="$total" 'BEGIN{printf "%.1f",(t>0)?f*100/t:0}')"
 
# Disk (aggregate of all real filesystems)
header "DISK USAGE  (all mounted filesystems)"
df -h --total -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
  | awk 'NR==1{next} $1=="total"{
        printf "  Total: %8s\n  Used : %8s  (%s)  ", $2,$3,$5;
        gsub(/%/,"",$5); u=$5; f="["; for(i=0;i<20;i++) f=f (i<int(u*20/100)?"#":"-"); f=f"]"; print f;
        printf "  Free : %8s\n", $4
    }'
 
# Top processes by CPU
header "TOP 5 PROCESSES BY CPU"
printf '  %-8s %-6s %-6s %s\n' "PID" "%CPU" "%MEM" "COMMAND"
ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | awk 'NR>1 && NR<=6{
    printf "  %-8s %-6s %-6s %s\n", $1,$2,$3,$4}'
 
# Top processes by memory
header "TOP 5 PROCESSES BY MEMORY"
printf '  %-8s %-6s %-6s %s\n' "PID" "%MEM" "%CPU" "COMMAND"
ps -eo pid,pmem,pcpu,comm --sort=-pmem 2>/dev/null | awk 'NR>1 && NR<=6{
    printf "  %-8s %-6s %-6s %s\n", $1,$2,$3,$4}'
 
hr