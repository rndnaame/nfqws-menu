#!/bin/sh
# Discord: все пакеты в nfqws2 — для nfqws2-keenetic (Keenetic / Netcraze, Entware).
#
# Все UDP пакеты голоса Discord идут в nfqws2 весь звонок (по умолчанию - только первые пакеты соединения),
# и исключаются из аппаратного/программного ускорения прошивки (-j PPE).
#
#   sh nfqws2_fullsession.sh            меню
#   sh nfqws2_fullsession.sh status     диагностика
#   sh nfqws2_fullsession.sh apply      включить (порты: PORTS=... в окружении)
#   sh nfqws2_fullsession.sh xkeen      исключить порты Discord из XKeen
#   sh nfqws2_fullsession.sh remove     выключить и удалить
#   sh nfqws2_fullsession.sh rules      поставить правила (хук и init-скрипт)
#   sh nfqws2_fullsession.sh unrules    снять правила

NFQ_INIT=${NFQ_INIT:-/opt/etc/init.d/S51nfqws2}
NFQ_CONF=${NFQ_CONF:-/opt/etc/nfqws2/nfqws2.conf}
FS_DIR=${FS_DIR:-/opt/etc/nfqws2-fullsession}
FS_CONF=$FS_DIR/fullsession.conf
FS_SELF=$FS_DIR/nfqws2-fullsession.sh
FS_INIT=${FS_INIT:-/opt/etc/init.d/S52nfqws2-fullsession}
FS_HOOK=${FS_HOOK:-/opt/etc/ndm/netfilter.d/101-nfqws2-fullsession.sh}
FS_LOG=${FS_LOG:-/tmp/nfqws2-fullsession.log}
CH_POST=nfqws_full_post
CH_FWD=nfqws_full_fwd
MARK_PROCESSED=0x40000000/0x40000000
DEF_PORTS=19294:19344,50000:50100
XKEEN_EXCL=${XKEEN_EXCL:-/opt/etc/xkeen/port_exclude.lst}
OPKG_STATUS=${OPKG_STATUS:-/opt/lib/opkg/status}
PROC_NET=${PROC_NET:-/proc/net}

if [ -t 1 ]; then
  C_G=$(printf '\033[32m'); C_Y=$(printf '\033[33m'); C_R=$(printf '\033[31m'); C_C=$(printf '\033[36m'); C_0=$(printf '\033[0m')
else
  C_G=; C_Y=; C_R=; C_C=; C_0=
fi
info() { printf '%s\n' "${C_G}[+]${C_0} $*"; }
warn() { printf '%s\n' "${C_Y}[!]${C_0} $*"; }
err()  { printf '%s\n' "${C_R}[x]${C_0} $*"; }
# ask_yn "вопрос" y|n — 0 на «да»; без терминала — ответ по умолчанию
ask_yn() {
  local q="$1" def="${2:-n}" a hint="[y/N]"
  [ "$def" = y ] && hint="[Y/n]"
  if [ ! -t 0 ]; then [ "$def" = y ]; return; fi
  printf '%s' "${C_C}[?]${C_0} $q $hint: "
  read -r a || a=""
  [ -z "$a" ] && a="$def"
  case "$a" in y|Y|д|Д|yes|да) return 0 ;; *) return 1 ;; esac
}
backup() { local b="$1.bak.$(date +%Y%m%d%H%M%S)"; [ -f "$1" ] && cp "$1" "$b" && info "Бэкап: $b"; }

# --- nfqws2 ------------------------------------------------------------------
nfq_installed() { [ -x "$NFQ_INIT" ] && [ -f "$NFQ_CONF" ]; }
nfq_version() { awk '/^Package: nfqws2-keenetic$/{f=1} f&&/^Version:/{print $2; exit} /^$/{f=0}' "$OPKG_STATUS" 2>/dev/null; }
nfq_running() { pidof nfqws2 >/dev/null 2>&1; }

# значения переменных nfqws2.conf (+ .run, как в S51nfqws2), по одной на строку
nfq_get() {
  local tmp="/tmp/nfqws2-fs-conf.$$"
  { tr -d '\r' < "$NFQ_CONF"; [ -f "$NFQ_CONF.run" ] && tr -d '\r' < "$NFQ_CONF.run"; } > "$tmp" 2>/dev/null
  ( . "$tmp" >/dev/null 2>&1; for v in "$@"; do eval "printf '%s\n' \"\${$v}\""; done )
  rm -f "$tmp"
}

ppe_available() {
  grep -qx PPE $PROC_NET/ip_tables_targets 2>/dev/null && return 0
  # цель может не значиться в списке до первого использования
  local r=1
  iptables -w -t mangle -N fs_ppe_probe 2>/dev/null
  iptables -w -t mangle -A fs_ppe_probe -j PPE 2>/dev/null && r=0
  iptables -w -t mangle -F fs_ppe_probe 2>/dev/null; iptables -w -t mangle -X fs_ppe_probe 2>/dev/null
  return $r
}

# --- настройки и журнал --------------------------------------------------------
fs_load() {
  PORTS="${PORTS:-}"
  [ -z "$PORTS" ] && [ -f "$FS_CONF" ] && PORTS=$(sed -n 's/^PORTS=//p' "$FS_CONF" | tr -d '"\r')
  PORTS="${PORTS:-$DEF_PORTS}"
}
fs_save() { mkdir -p "$FS_DIR"; printf 'PORTS=%s\n' "$PORTS" > "$FS_CONF"; }

log_event() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$FS_LOG" 2>/dev/null || return 0
  if [ "$(wc -l < "$FS_LOG")" -gt 500 ]; then tail -n 300 "$FS_LOG" > "$FS_LOG.tmp" && mv "$FS_LOG.tmp" "$FS_LOG"; fi
}
# потоки звонка Discord в conntrack: "всего в PPE ускорении"
discord_flows() {
  awk '$3 == "udp" { dp = ""; op = -1
       for (i = 1; i <= NF; i++) { if (dp == "" && $i ~ /^dport=/) dp = substr($i, 7) + 0; if (op < 0 && $i ~ /^packets=/) op = substr($i, 9) + 0 }
       if (!((dp >= 19294 && dp <= 19344) || (dp >= 50000 && dp <= 50100))) next
       if ($0 ~ /\[UNREPLIED\]/ || (op >= 0 && op < 100)) next
       n++; if ($0 ~ /\[FASTNAT\]/) f++ }
       END { print n + 0, f + 0 }' $PROC_NET/nf_conntrack 2>/dev/null
}

# --- правила -------------------------------------------------------------------
rules_remove() {
  while iptables -w -t mangle -C POSTROUTING -j $CH_POST 2>/dev/null; do iptables -w -t mangle -D POSTROUTING -j $CH_POST; done
  while iptables -w -t mangle -C FORWARD -j $CH_FWD 2>/dev/null; do iptables -w -t mangle -D FORWARD -j $CH_FWD; done
  iptables -w -t mangle -F $CH_POST 2>/dev/null; iptables -w -t mangle -X $CH_POST 2>/dev/null
  iptables -w -t mangle -F $CH_FWD 2>/dev/null; iptables -w -t mangle -X $CH_FWD 2>/dev/null
}

policy_ret() {
  [ -n "$2" ] || return 0
  if [ "${3:-0}" != "0" ]; then echo "-o $1 -m mark --mark $2 -j RETURN"; else echo "-o $1 -m mark ! --mark $2 -j RETURN"; fi
}
fwd_specs() {
  local iface
  for iface in $1; do
    policy_ret "$iface" "$2" "$3"
    echo "-o $iface -p udp -m multiport --dports $PORTS -j PPE"
  done
  for iface in $1; do echo "-i $iface -p udp -m multiport --sports $PORTS -j PPE"; done
}
post_specs() {
  local iface
  for iface in $1; do
    policy_ret "$iface" "$2" "$3"
    echo "-o $iface -m mark ! --mark $MARK_PROCESSED -p udp -m multiport --dports $PORTS -j NFQUEUE --queue-num $4 --queue-bypass"
  done
}

chain_sync() {
  local n_want n_have same=1 tmp="${1}_new"
  n_want=$(printf '%s\n' "$3" | grep -c .)
  n_have=$(iptables -w -t mangle -S $1 2>/dev/null | grep -c '^-A')
  if [ "$n_want" = "$n_have" ]; then
    printf '%s\n' "$3" | while read -r spec; do iptables -w -t mangle -C $1 $spec 2>/dev/null || exit 1; done || same=0
  else
    same=0
  fi
  if [ $same -eq 1 ]; then
    iptables -w -t mangle -C $2 -j $1 2>/dev/null && return 1
    iptables -w -t mangle -I $2 -j $1
  elif [ "$n_have" -gt 0 ] && iptables -w -t mangle -C $2 -j $1 2>/dev/null; then
    iptables -w -t mangle -N $tmp 2>/dev/null; iptables -w -t mangle -F $tmp
    printf '%s\n' "$3" | while read -r spec; do iptables -w -t mangle -A $tmp $spec; done
    iptables -w -t mangle -I $2 -j $tmp
    while iptables -w -t mangle -C $2 -j $1 2>/dev/null; do iptables -w -t mangle -D $2 -j $1; done
    iptables -w -t mangle -F $1; iptables -w -t mangle -X $1
    iptables -w -t mangle -E $tmp $1
  else
    iptables -w -t mangle -N $1 2>/dev/null; iptables -w -t mangle -F $1
    printf '%s\n' "$3" | while read -r spec; do iptables -w -t mangle -A $1 $spec; done
    iptables -w -t mangle -C $2 -j $1 2>/dev/null || iptables -w -t mangle -I $2 -j $1
  fi
  return 0
}
fwd_remove() {
  while iptables -w -t mangle -C FORWARD -j $CH_FWD 2>/dev/null; do iptables -w -t mangle -D FORWARD -j $CH_FWD; done
  iptables -w -t mangle -F $CH_FWD 2>/dev/null; iptables -w -t mangle -X $CH_FWD 2>/dev/null
}
rules_apply() {
  fs_load
  local ifaces q pmark pexcl changed=""
  { read -r ifaces; read -r q; read -r pmark; read -r pexcl; } <<EOF
$(nfq_get ISP_INTERFACE NFQUEUE_NUM POLICY_MARK POLICY_EXCLUDE)
EOF
  ifaces="${ifaces:-eth3}"; q="${q:-300}"
  # FORWARD первым: без -j PPE поток звонка за несколько пакетов уходит в ускорение
  if ppe_available; then
    chain_sync $CH_FWD FORWARD "$(fwd_specs "$ifaces" "$pmark" "$pexcl")" && changed="$changed FORWARD"
  else
    fwd_remove
  fi
  chain_sync $CH_POST POSTROUTING "$(post_specs "$ifaces" "$pmark" "$pexcl" "$q")" && changed="$changed POSTROUTING"
  if [ -n "$changed" ]; then
    log_event "${FS_EVENT:-manual}: восстановлено:$changed; потоки звонка / в ускорении: $(discord_flows | tr ' ' '/')"
  else
    log_event "${FS_EVENT:-manual}: правила на месте"
  fi
  RULES_CHANGED=$changed
}

persist_install() {
  mkdir -p "$FS_DIR" /opt/etc/ndm/netfilter.d
  if [ "$(readlink -f "$0" 2>/dev/null)" != "$FS_SELF" ]; then cp "$0" "$FS_SELF"; fi
  chmod +x "$FS_SELF"
  cat > "$FS_HOOK" <<EOF
#!/bin/sh
# nfqws2-fullsession: правила после перезаписи таблицы mangle прошивкой
[ "\$type" = "iptables" ] && [ "\$table" = "mangle" ] || exit 0
[ -x $FS_SELF ] && [ -f $FS_CONF ] && FS_EVENT=hook $FS_SELF rules >/dev/null 2>&1
exit 0
EOF
  chmod +x "$FS_HOOK"
  cat > "$FS_INIT" <<EOF
#!/bin/sh
# nfqws2-fullsession: правила после загрузки (после S51nfqws2)
case "\$1" in
  start|restart) FS_EVENT=boot $FS_SELF rules ;;
  stop) $FS_SELF unrules ;;
  status) $FS_SELF status ;;
  *) echo "Usage: \$0 {start|stop|restart|status}" ;;
esac
EOF
  chmod +x "$FS_INIT"
}
persist_remove() { rm -f "$FS_HOOK" "$FS_INIT"; }

# --- XKeen -------------------------------------------------------------------------
xkeen_present() { [ -x /opt/sbin/xkeen ] || [ -f "$XKEEN_EXCL" ]; }
xkeen_ok() { grep -q '19294:19344' "$XKEEN_EXCL" 2>/dev/null && grep -q '50000:50100' "$XKEEN_EXCL" 2>/dev/null; }
xkeen_fix() {
  xkeen_present || { info "XKeen не найден"; return 0; }
  xkeen_ok && { info "XKeen: порты Discord уже исключены"; return 0; }
  backup "$XKEEN_EXCL"
  mkdir -p "$(dirname "$XKEEN_EXCL")"; touch "$XKEEN_EXCL"
  grep -q '19294:19344' "$XKEEN_EXCL" || echo '19294:19344' >> "$XKEEN_EXCL"
  grep -q '50000:50100' "$XKEEN_EXCL" || echo '50000:50100' >> "$XKEEN_EXCL"
  info "Порты Discord добавлены в $XKEEN_EXCL"
  if [ -x /opt/sbin/xkeen ] && pidof xray >/dev/null 2>&1 && ask_yn "Перезапустить XKeen, чтобы применить?" y; then
    /opt/sbin/xkeen -restart >/dev/null 2>&1 && info "XKeen перезапускается"
  fi
}

# --- статус ------------------------------------------------------------------------
status() {
  fs_load
  if ! nfq_installed; then err "nfqws2-keenetic не установлен (нет $NFQ_INIT)"; return 1; fi
  info "nfqws2-keenetic $(nfq_version) — $(nfq_running && echo "запущен (pid $(pidof nfqws2))" || echo "НЕ запущен")"
  local n_queue n_fwd q n f
  [ -f "$FS_CONF" ] && info "Фикс: включён, порты $PORTS" || info "Фикс: выключен"
  n_queue=$(iptables-save -t mangle 2>/dev/null | grep -E -- "-A $CH_POST .*-p udp" | grep NFQUEUE | grep -vc connbytes)
  n_fwd=$(iptables-save -t mangle 2>/dev/null | grep -cE -- "-A $CH_FWD .*-j PPE")
  info "Правила: очередь на всю сессию — $n_queue, исключение из ускорения (PPE) — $n_fwd"
  ppe_available && info "Цель -j PPE прошивки: есть" || warn "Цель -j PPE прошивки: нет (поток может уйти в ускорение)"
  if xkeen_present; then xkeen_ok && info "XKeen: порты Discord исключены" || warn "XKeen: порты Discord НЕ исключены — голос пойдёт через Xray (пункт 4)"; fi
  q=$(nfq_get NFQUEUE_NUM); q="${q:-300}"
  awk -v q="$q" '$1==q{print "    очередь " q ": обработано " $8 ", потерь ядра " $6 ", потерь nfqws2 " $7}' $PROC_NET/netfilter/nfnetlink_queue 2>/dev/null
  read -r n f <<EOF
$(discord_flows)
EOF
  if [ "${n:-0}" -gt 0 ]; then
    echo "    потоки звонка Discord: $n, в ускорении [FASTNAT]: $f"
    [ "${f:-0}" -gt 0 ] && warn "Поток звонка ускоряется прошивкой — фикс к нему не применяется. Переподключитесь к голосовому каналу."
  fi
  if [ -s "$FS_LOG" ]; then
    echo "    журнал $FS_LOG: восстановлений после перезаписи таблицы — $(grep -c 'hook: восстановлено' "$FS_LOG")"
    tail -n 3 "$FS_LOG" | sed 's/^/      /'
  fi
}

# --- действия ------------------------------------------------------------------------
do_apply() {
  nfq_installed || { err "nfqws2-keenetic не установлен (nfqws-menu, пункт 1)"; return 1; }
  fs_load
  fs_save
  persist_install
  rules_apply
  info "Правила установлены: цепочки $CH_POST / $CH_FWD, хук прошивки, init-скрипт."
  [ -n "$RULES_CHANGED" ] && info "Переподключитесь к голосовому каналу Discord."
  if xkeen_present && ! xkeen_ok; then warn "XKeen перехватывает порты Discord — пункт 4 (или: $0 xkeen)"; fi
}
do_remove() {
  rules_remove; persist_remove
  rm -rf "$FS_DIR"
  info "Фикс выключен"
}

menu() {
  while :; do
    echo
    echo "${C_C}Discord: все пакеты в nfqws2${C_0}"
    if ! nfq_installed; then err "nfqws2-keenetic не установлен (nfqws-menu, пункт 1)"; return 1; fi
    echo "  1) Статус / диагностика"
    echo "  2) Включить фикс"
    echo "  3) Выключить фикс и удалить"
    xkeen_present && echo "  4) XKeen: исключить порты Discord"
    echo "  0) Выход"
    printf 'Ваш выбор [0]: '; read -r c || return 0
    case "$c" in
      1) status ;;
      2) do_apply ;;
      3) ask_yn "Выключить фикс?" n && do_remove ;;
      4) xkeen_fix ;;
      0|"") return 0 ;;
      *) warn "Нет такого пункта" ;;
    esac
  done
}

case "${1:-}" in
  status) status ;;
  apply) do_apply ;;
  xkeen) xkeen_fix ;;
  remove) do_remove ;;
  rules) [ -f "$FS_CONF" ] && rules_apply ;;
  unrules) rules_remove ;;
  "") menu ;;
  *) echo "Usage: $0 [status|apply|xkeen|remove|rules|unrules]"; exit 1 ;;
esac
