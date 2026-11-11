#!/bin/sh
# Тесты installer_antiscan.sh в изолированном окружении.
# opkg, RCI (curl), ip, iptables, ipset, crontab и S99ascn заменены заглушками;
# настоящие OPKG, firewall и конфигурация хоста не используются.
#
#   sh tests/antiscan-installer.sh
#   dash tests/antiscan-installer.sh
#
# Проверки передаются строкой в check (eval), ответы пользователя — printf-строкой.
# shellcheck disable=SC1007,SC1090,SC2016,SC2034,SC2059
set -u

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
INSTALLER="$repo_dir/installer_antiscan.sh"
root=$(mktemp -d)
if [ -n "${KEEP_TEST_ROOT:-}" ]; then
  echo "root=$root"
else
  trap 'rm -rf "$root"' EXIT HUP INT TERM
fi

PRIMARY="https://dimon27254.github.io/antiscan/all"
MIRROR="https://bin.antiscan.ru/packages/all"

failures=0
passes=0
fail() { printf 'FAIL: %s: %s\n' "$case_name" "$1" >&2; failures=$((failures + 1)); }
ok()   { passes=$((passes + 1)); }
check() { if eval "$1"; then ok; else fail "$2"; fi; }

# ---------------------------------------------------------------------------
# Заглушки
# ---------------------------------------------------------------------------
write_stubs() {
  B="$T/bin"
  mkdir -p "$B"

  cat > "$B/opkg" <<'EOF'
#!/bin/sh
S="$STUB_STATE"
echo "opkg $*" >> "$STUB_LOG/opkg.log"
feeds() { cat "$OPKG_MAIN_CONF" "$OPKG_CONF_DIR"/*.conf 2>/dev/null; }
LISTS=$(awk '$1 == "lists_dir" { print $NF; exit }' "$OPKG_MAIN_CONF")
# Как opkg: индекс источника — файл lists_dir/<имя src>; при ошибке загрузки
# прежний файл остаётся (Entware: /opt/var/opkg-lists на накопителе).
index_ver() {
  feeds | awk '$1 ~ /^src/ { print $2 }' | while read -r n; do
    [ -s "$LISTS/$n" ] && { cat "$LISTS/$n"; break; }
  done
}
cmd=$1; shift
case "$cmd" in
  update)
    rc=0; mkdir -p "$LISTS"
    feeds | awk '$1 ~ /^src/ { print $2, $3 }' > "$S/srcs"
    while read -r n u; do
      case "$u" in
        "$STUB_PRIMARY") net="$S/net_primary" ;;
        "$STUB_MIRROR") net="$S/net_mirror" ;;
        *) net="$S/net_other" ;;
      esac
      if [ -f "$net" ] || { [ "$net" = "$S/net_other" ] && [ ! -f "$S/other_fail" ]; }; then
        cp "$S/feed_version" "$LISTS/$n"
      else
        echo "*** Failed to download the package list from $u" >&2; rc=1
      fi
    done < "$S/srcs"
    [ -f "$S/other_fail" ] && rc=1
    exit $rc ;;
  list)
    v=$(index_ver)
    [ "$1" = antiscan ] && [ -n "$v" ] && echo "antiscan - $v - Antiscan utility"
    exit 0 ;;
  list-upgradable)
    v=$(index_ver)
    if [ -f "$S/inst_antiscan" ] && [ -n "$v" ] && [ "$(cat "$S/inst_antiscan")" != "$v" ]; then
      echo "antiscan - $(cat "$S/inst_antiscan") - $v"
    fi
    exit 0 ;;
  status)
    if [ -f "$S/inst_$1" ]; then
      printf 'Package: %s\nVersion: %s\nStatus: install user installed\n\n' "$1" "$(cat "$S/inst_$1")"
    elif [ -f "$S/broken_$1" ]; then
      printf 'Package: %s\nVersion: 1\nStatus: install ok half-configured\n\n' "$1"
    fi
    exit 0 ;;
  install|upgrade)
    for p in "$@"; do
      case "$p" in -*) continue ;; esac
      if [ "$p" = antiscan ]; then
        [ -f "$S/install_fail" ] && { echo "Collected errors: antiscan" >&2; exit 255; }
        v=$(index_ver)
        [ -n "$v" ] || { echo "Unknown package antiscan" >&2; exit 255; }
        [ -f "$S/net_primary" ] || [ -f "$S/net_mirror" ] || { echo "Failed to download antiscan" >&2; exit 255; }
        echo "$v" > "$S/inst_antiscan"
        mkdir -p "$ASCN_DIR/scripts" "$(dirname "$ASCN_HOOK")" "$(dirname "$ASCN_INIT")"
        cp "$STUB_TPL/S99ascn" "$ASCN_INIT"; chmod +x "$ASCN_INIT"
        cp "$STUB_TPL/hook" "$ASCN_HOOK"
        [ -f "$ASCN_DIR/ascn.conf" ] || cp "$STUB_TPL/ascn.conf" "$ASCN_DIR/ascn.conf"
        [ -f "$ASCN_DIR/ascn_crontab.conf" ] || echo '*/1 * * * * /opt/etc/init.d/S99ascn read_candidates &' > "$ASCN_DIR/ascn_crontab.conf"
        [ -f "$S/postinst_start" ] && "$ASCN_INIT" start >/dev/null
        exit "$(cat "$S/install_rc" 2>/dev/null || echo 0)"
      fi
      [ -f "$S/fail_$p" ] && { echo "cannot install $p" >&2; exit 255; }
      echo 1.0 > "$S/inst_$p"
    done
    exit 0 ;;
  remove)
    [ -f "$S/remove_fail" ] && { echo "remove failed" >&2; exit 1; }
    [ "$1" = antiscan ] || exit 0
    "$ASCN_INIT" stop >/dev/null 2>&1
    rm -f "$ASCN_INIT" "$ASCN_HOOK" "$S/inst_antiscan" "$S/broken_antiscan"
    rm -rf "$ASCN_DIR/scripts"
    exit 0 ;;
esac
exit 0
EOF

  cat > "$B/curl" <<'EOF'
#!/bin/sh
S="$STUB_STATE"
echo "curl $*" >> "$STUB_LOG/curl.log"
url=""; wcode=0
for a in "$@"; do
  case "$a" in http*) url=$a ;; '%{http_code}') wcode=1 ;; esac
done
case "$url" in
  */rci/whoami)
    [ "$wcode" = 1 ] && cat "$S/rci_whoami" 2>/dev/null || printf '000'
    exit 0 ;;
  */rci/show/version) [ -f "$S/rci_version" ] && { cat "$S/rci_version"; exit 0; }; exit 22 ;;
  */rci/show/interface) [ -f "$S/rci_iface" ] && { cat "$S/rci_iface"; exit 0; }; exit 22 ;;
  */rci/show/interface/system-name*)
    n=${url##*name=}; [ -f "$S/sysname_$n" ] && { cat "$S/sysname_$n"; exit 0; }; exit 22 ;;
esac
exit 6
EOF

  cat > "$B/ip" <<'EOF'
#!/bin/sh
case "$*" in
  "-4 route show default") cat "$STUB_STATE/route_default" 2>/dev/null ;;
  "-4 route show table all") cat "$STUB_STATE/route_all" 2>/dev/null ;;
esac
exit 0
EOF

  # Firewall: фиксируем каждый вызов. Состояние правил Antiscan ведёт заглушка
  # S99ascn (state/chain, state/rules: «ЦЕПОЧКА ИНТЕРФЕЙС ПОРТЫ ЦЕЛЬ»).
  cat > "$B/iptables" <<'EOF'
#!/bin/sh
echo "iptables $*" >> "$STUB_LOG/fw.log"
S="$STUB_STATE"
case "$*" in
  "-w -t filter -L ANTISCAN -n") [ -f "$S/chain" ] || [ -f "$S/chain_left" ]; exit $? ;;
  "-w -t filter -L ANTISCAN_HONEYPOT -n") [ -f "$S/chain_hp" ]; exit $? ;;
  "-w -t filter -S ANTISCAN") [ -f "$S/chain" ] || exit 1; echo "-N ANTISCAN"; cat "$S/chain"; exit 0 ;;
  "-w -t filter -S ANTISCAN_HONEYPOT") [ -f "$S/chain_hp" ] || exit 1; echo "-N ANTISCAN_HONEYPOT"; cat "$S/chain_hp"; exit 0 ;;
  "-w -t filter -C "*)
    # -w -t filter -C CHAIN -i IF -p tcp -m multiport --dports P -j TARGET
    set -f; set -- $*
    grep -qx "$5 $7 ${13} ${15}" "$S/rules" 2>/dev/null; exit $? ;;
esac
exit 1
EOF
  cat > "$B/ipset" <<'EOF'
#!/bin/sh
echo "ipset $*" >> "$STUB_LOG/fw.log"
exit 0
EOF
  for c in ip6tables iptables-restore iptables-save; do
    printf '#!/bin/sh\necho "%s $*" >> "$STUB_LOG/fw.log"\nexit 0\n' "$c" > "$B/$c"
  done
  cat > "$B/crontab" <<'EOF'
#!/bin/sh
[ "$1" = "-l" ] && cat "$STUB_STATE/crontab" 2>/dev/null
exit 0
EOF
  printf '#!/bin/sh\nexit 0\n' > "$B/lsmod"
  printf '#!/bin/sh\nexit 0\n' > "$B/netstat"
  printf '#!/bin/sh\necho 0\n' > "$B/id"
  printf '#!/bin/sh\nexit 0\n' > "$B/clear"
  # mv: отказ только для отложенного индекса opkg (state/mv_fail)
  cat > "$B/mv" <<'MVEOF'
#!/bin/sh
if [ -f "$STUB_STATE/mv_fail" ]; then
  for a in "$@"; do case "$a" in *ascn-prev*) echo "mv: cannot rename" >&2; exit 1 ;; esac; done
fi
exec /bin/mv "$@"
MVEOF
  chmod +x "$B"/*

  # Шаблоны файлов пакета
  mkdir -p "$T/tpl"
  # Модель S99ascn 1.10.6: read_config (проверка) → reload_config: lock,
  # remove_rules, write_temp_config, add_rules (ошибки add_rules не влияют на код),
  # снятие lock. start/stop/reload/update_rules отказывают при наличии lock.
  cat > "$T/tpl/S99ascn" <<'EOF'
#!/bin/sh
S="$STUB_STATE"
echo "ascn $*" >> "$STUB_LOG/ascn.log"
cget() { awk -v k="$1" 'index($0, k "=\"") == 1 { v = substr($0, length(k) + 3); sub(/"$/, "", v); r = v } END { print r }' "$2"; }
eff() { if [ -f "$ASCN_TEMP_CONF" ]; then cget "$1" "$ASCN_TEMP_CONF"; else cget "$1" "$ASCN_CONF"; fi; }
write_temp() { grep -E '^(ISP_INTERFACES|PORTS|PORTS_FORWARDED|ENABLE_HONEYPOT|HONEYPOT_PORTS|ENABLE_IPS_BAN|CUSTOM_LISTS_BLOCK_MODE)=' "$ASCN_CONF" > "$ASCN_TEMP_CONF"; }
ips_on() { v=$(eff ENABLE_IPS_BAN); [ "${v:-1}" = 1 ]; }
# Содержимое как у add_rules upstream (вывод iptables -S). Ошибки _iptables -A
# upstream не проверяет: fill_no_drop / fill_partial — частично созданная цепочка.
fill_chain() {
  {
    [ "$(eff ENABLE_HONEYPOT)" = 1 ] && echo "-A ANTISCAN -m set --match-set ascn_honeypot src -j DROP"
    if ips_on; then
      if [ ! -f "$S/fill_no_drop" ]; then
        echo "-A ANTISCAN -m set --match-set ascn_subnets src -j DROP"
        echo "-A ANTISCAN -m set --match-set ascn_ips src -j DROP"
      fi
      [ -f "$S/fill_no_candidates" ] || echo "-A ANTISCAN -j SET --add-set ascn_candidates src"
      if [ ! -f "$S/fill_partial" ]; then
        echo "-A ANTISCAN -m connlimit --connlimit-above 20 --connlimit-mask 32 --connlimit-saddr -j SET --add-set ascn_ips src"
        echo "-A ANTISCAN -m conntrack --ctstate NEW -m recent --update --seconds 30 --hitcount 15 --name scanners --mask 255.255.255.255 --rsource -j SET --add-set ascn_ips src"
        echo "-A ANTISCAN -m conntrack --ctstate NEW -m recent --set --name scanners --mask 255.255.255.255 --rsource"
      fi
    fi
    echo "-A ANTISCAN -j RETURN"
  } > "$S/chain"
}
fill_hp() {
  : > "$S/chain_hp"
  [ -f "$S/hp_fill_empty" ] && return
  echo "-A ANTISCAN_HONEYPOT -m set --match-set ascn_honeypot src -j DROP" >> "$S/chain_hp"
  ips_on && echo "-A ANTISCAN_HONEYPOT -m set --match-set ascn_ips src -j DROP" >> "$S/chain_hp"
  echo "-A ANTISCAN_HONEYPOT -j SET --add-set ascn_honeypot src" >> "$S/chain_hp"
}
# Как upstream: цепочка заполняется только при создании, переходы — всегда
add_rules() {
  p=$(eff PORTS); f=$(eff PORTS_FORWARDED); hp=$(eff HONEYPOT_PORTS)
  [ -f "$S/chain" ] || fill_chain
  if [ "$(eff ENABLE_HONEYPOT)" = 1 ] && [ ! -f "$S/chain_hp" ]; then fill_hp; fi
  for i in $(eff ISP_INTERFACES); do
    [ -n "$p" ] && echo "INPUT $i $p ANTISCAN" >> "$S/rules"
    [ -n "$f" ] && echo "FORWARD $i $f ANTISCAN" >> "$S/rules"
    [ "$(eff ENABLE_HONEYPOT)" = 1 ] && echo "INPUT $i $hp ANTISCAN_HONEYPOT" >> "$S/rules"
  done
  sort -u "$S/rules" -o "$S/rules" 2>/dev/null || true
}
del_jump() { [ -f "$S/rules" ] || return 0; grep -vxF "$1" "$S/rules" > "$S/rules.n"; mv "$S/rules.n" "$S/rules"; }
# Как upstream: переходы удаляются только для текущей конфигурации, затем -F и -X;
# -X не проходит, пока на цепочку ссылается переход (цепочка остаётся пустой).
remove_rules() {
  p=$(eff PORTS); f=$(eff PORTS_FORWARDED); hp=$(eff HONEYPOT_PORTS)
  if [ -f "$S/chain" ]; then
    for i in $(eff ISP_INTERFACES); do
      [ -n "$p" ] && del_jump "INPUT $i $p ANTISCAN"
      [ -n "$f" ] && del_jump "FORWARD $i $f ANTISCAN"
    done
    : > "$S/chain"
    [ -f "$S/interrupt_after_flush" ] && { rm -f "$S/interrupt_after_flush"; exit 143; }  # однократно
    grep -q ' ANTISCAN$' "$S/rules" 2>/dev/null || rm -f "$S/chain"
  fi
  if [ "$(eff ENABLE_HONEYPOT)" = 1 ] && [ -f "$S/chain_hp" ]; then
    for i in $(eff ISP_INTERFACES); do del_jump "INPUT $i $hp ANTISCAN_HONEYPOT"; done
    : > "$S/chain_hp"
    grep -q ' ANTISCAN_HONEYPOT$' "$S/rules" 2>/dev/null || rm -f "$S/chain_hp"
  fi
}
locked() { [ -f "$ASCN_LOCK_FILE" ] && { echo "Идёт обновление конфигурации" >&2; exit 2; }; }
case "$1" in
  start) [ -f "$ASCN_RUN_FILE" ] && exit 1; locked; write_temp; add_rules; touch "$ASCN_RUN_FILE"; echo "Antiscan запущен" ;;
  stop) [ -f "$ASCN_RUN_FILE" ] || { echo "Antiscan не запущен" >&2; exit 0; }; locked
        remove_rules; rm -f "$ASCN_TEMP_CONF" "$ASCN_RUN_FILE"; echo "Antiscan остановлен" ;;
  restart) "$0" stop 1; "$0" start ;;
  reload)
    [ -f "$S/reload_invalid" ] && { echo "Список портов содержит недопустимые символы" >&2; exit 3; }
    [ -f "$ASCN_RUN_FILE" ] || exit 1
    locked
    touch "$ASCN_LOCK_FILE"; remove_rules; rm -f "$ASCN_TEMP_CONF"; write_temp
    [ -f "$S/reload_interrupted" ] && exit 143
    [ -f "$S/reload_norules" ] || add_rules
    rm -f "$ASCN_LOCK_FILE"; echo "reloaded" ;;
  update_rules) [ -f "$ASCN_RUN_FILE" ] || exit 1; locked; [ -f "$S/update_rules_fail" ] || add_rules ;;
  status) echo "Статус: stub" ;;
  list) echo "list $2" ;;
  edit) echo '# edited' >> "$ASCN_DIR/ascn.conf" ;;
esac
exit 0
EOF
  printf '#!/bin/sh\n[ "$table" != "filter" ] && exit\n' > "$T/tpl/hook"
  cat > "$T/tpl/ascn.conf" <<'EOF'
ISP_INTERFACES="eth3"
PORTS="22,80,443"
PORTS_FORWARDED="22,80,443"

ENABLE_HONEYPOT="0"
HONEYPOT_PORTS=""
ENABLE_IPS_BAN="1"
RECENT_CONNECTIONS_BANTIME="864000"
SAVE_IPSETS="0"
GEOBLOCK_MODE="0"
EOF
}

# Новое окружение для каждого сценария
setup() {
  case_name=$1
  T="$root/$1"
  mkdir -p "$T/state" "$T/log" "$T/opt/etc/opkg" "$T/sysnet/eth3" "$T/opt/bin"
  : > "$T/log/fw.log"; : > "$T/log/opkg.log"; : > "$T/log/ascn.log"; : > "$T/log/curl.log"
  write_stubs
  echo "1.10.6" > "$T/state/feed_version"
  touch "$T/state/net_primary" "$T/state/postinst_start"
  echo 1.0 > "$T/state/inst_wget-ssl"
  echo 1.0 > "$T/state/inst_ca-bundle"
  printf '{"release": "4.3.6.3-0", "title": "4.3.6.3", "components": "opkg,opkg-kmod-netfilter,ipv6"}\n' > "$T/state/rci_version"
  printf '200' > "$T/state/rci_whoami"
  echo "default via 10.0.0.1 dev eth3 proto static" > "$T/state/route_default"
  cp "$T/state/route_default" "$T/state/route_all"
  printf 'dest root /\nlists_dir ext %s\n' "$T/opt/var/opkg-lists" > "$T/opt/etc/opkg.conf"
  export PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  export STUB_STATE="$T/state" STUB_LOG="$T/log" STUB_TPL="$T/tpl"
  export STUB_PRIMARY="$PRIMARY" STUB_MIRROR="$MIRROR"
  export ASCN_DIR="$T/opt/etc/antiscan" ASCN_CONF="$T/opt/etc/antiscan/ascn.conf"
  export ASCN_INIT="$T/opt/etc/init.d/S99ascn" ASCN_HOOK="$T/opt/etc/ndm/netfilter.d/099-ascn.sh"
  export ASCN_LOCK_FILE="$T/tmp/ascn.lock" ASCN_TEMP_CONF="$T/tmp/ascn.conf.tmp" ASCN_LOCK_WAIT=0
  export ASCN_RUN_FILE="$T/tmp/ascn.run" OPKG_CONF_DIR="$T/opt/etc/opkg" OPKG_MAIN_CONF="$T/opt/etc/opkg.conf"
  export OPT_BIN="$T/opt/bin" SYS_NET_DIR="$T/sysnet" KMOD_DIR="$T/modules" ASCN_BACKUP_BASE="$T/opt/etc"
  mkdir -p "$T/proc/self" "$T/proc/1"; printf '/sbin/init\0' > "$T/proc/1/cmdline"
  export PROC_DIR="$T/proc"
  export RCI_BASE="http://127.0.0.1:79/rci" ASCN_NO_TTY=1 ASCN_INSTALLER_LIB=1 TMPDIR="$T/tmp"
  unset SSH_CLIENT SSH_CONNECTION 2>/dev/null || true
  mkdir -p "$T/tmp"
}

# Уже установленный пакет (файлы как после opkg install)
preinstall() {
  echo "${1:-1.10.6}" > "$T/state/inst_antiscan"
  mkdir -p "$ASCN_DIR/scripts" "$(dirname "$ASCN_HOOK")" "$(dirname "$ASCN_INIT")"
  cp "$T/tpl/S99ascn" "$ASCN_INIT"; chmod +x "$ASCN_INIT"
  cp "$T/tpl/hook" "$ASCN_HOOK"
  cp "$T/tpl/ascn.conf" "$ASCN_CONF"
  echo '*/1 * * * * /opt/etc/init.d/S99ascn read_candidates &' > "$ASCN_DIR/ascn_crontab.conf"
  printf 'src/gz antiscan %s\n' "$PRIMARY" > "$OPKG_CONF_DIR/antiscan.conf"
}

# $1 — ответы (printf-строка), далее — функция установщика
run() {
  printf "$1" > "$T/in"
  shift
  ( . "$INSTALLER"; "$@" ) < "$T/in" > "$T/out" 2>&1
  rc=$?
  return 0
}

out_has() { grep -q -- "$1" "$T/out"; }
opkg_has() { grep -q -- "$1" "$T/log/opkg.log"; }
opkg_count() { grep -c -- "$1" "$T/log/opkg.log"; }
conf() { awk -v k="$1" 'index($0, k "=\"") == 1 { v = substr($0, length(k) + 3); sub(/"$/, "", v); r = v } END { print r }' "$ASCN_CONF"; }

# Firewall: установщик сам может только читать (iptables -L / -C) — без ipset
FW_RO='^iptables -w -t filter (-L ANTISCAN(_HONEYPOT)? -n|-S ANTISCAN(_HONEYPOT)?|-C (INPUT|FORWARD) -i [^ ]+ -p tcp -m multiport --dports [0-9,:]+ -j ANTISCAN(_HONEYPOT)?)$'
check_firewall_readonly() {
  if grep -Ev "$FW_RO" "$T/log/fw.log" | grep -q .; then
    fail "посторонние firewall-команды: $(grep -Ev "$FW_RO" "$T/log/fw.log" | head -n 3 | tr '\n' ';')"
  else
    ok
  fi
}

# Antiscan запущен штатно (правила в модели iptables есть)
start_ascn() { "$ASCN_INIT" start >/dev/null 2>&1; }
rules_for() { grep -qx "$1" "$T/state/rules" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Сценарии
# ---------------------------------------------------------------------------

setup first_install
run 'y\nn\n' do_install
check '[ "$rc" -eq 0 ]' "do_install rc=$rc"
check '[ "$(cat "$T/state/inst_antiscan")" = 1.10.6 ]' "пакет не установлен"
check '[ "$(cat "$OPKG_CONF_DIR/antiscan.conf")" = "src/gz antiscan $PRIMARY" ]' "feed не записан"
check '[ "$(opkg_count "opkg install antiscan")" -eq 1 ]' "install вызван не 1 раз"
check '! opkg_has "force-reinstall"' "использован --force-reinstall"
check '! opkg_has "install wget-ssl"' "переустановлены уже установленные зависимости"
check '[ -f "$ASCN_RUN_FILE" ]' "Antiscan не запущен после post-install"
check '[ "$(conf ISP_INTERFACES)" = eth3 ]' "конфиг изменён без подтверждения"
check '! ls "$ASCN_DIR"/ascn.conf.bak.* >/dev/null 2>&1' "бэкап без изменений"
check_firewall_readonly

setup first_install_configure
mkdir -p "$T/sysnet/ppp0"
echo "default dev ppp0 table 100" >> "$T/state/route_all"
# установить → настроить: пункты 1 2, PORTS 22,8443, PORTS_FORWARDED пусто, сохранить
run 'y\ny\n1 2\n22,8443\n-\ny\n' do_install
check '[ "$rc" -eq 0 ]' "rc=$rc"
check '[ "$(conf ISP_INTERFACES)" = "eth3 ppp0" ]' "ISP_INTERFACES=$(conf ISP_INTERFACES)"
check '[ "$(conf PORTS)" = "22,8443" ]' "PORTS=$(conf PORTS)"
check '[ "$(conf PORTS_FORWARDED)" = "" ]' "PORTS_FORWARDED не очищен"
check '[ "$(conf RECENT_CONNECTIONS_BANTIME)" = 864000 ] && [ "$(conf GEOBLOCK_MODE)" = 0 ]' "остальные параметры потеряны"
check 'ls "$ASCN_DIR"/ascn.conf.bak.* >/dev/null 2>&1' "нет бэкапа ascn.conf"
check 'grep -q "^ascn reload" "$T/log/ascn.log"' "не вызван antiscan reload"
check_firewall_readonly

setup already_installed
preinstall
printf 'ISP_INTERFACES="ppp0"\nPORTS="22"\nPORTS_FORWARDED=""\n' > "$ASCN_CONF"
cp "$ASCN_CONF" "$T/conf.orig"
run '' do_install
check '[ "$rc" -eq 0 ]' "rc=$rc"
check 'out_has "уже установлен"' "нет сообщения об установленном пакете"
check '! opkg_has "opkg install" && ! opkg_has "opkg update"' "лишние вызовы opkg"
check 'cmp -s "$ASCN_CONF" "$T/conf.orig"' "рабочий конфиг изменён"

setup rerun
run 'y\nn\n' do_install
run '' do_install
check '[ "$(opkg_count "opkg install antiscan")" -eq 1 ]' "повторный запуск переустановил пакет"
check 'out_has "уже установлен"' "второй запуск не распознал установку"
printf '9\n' > "$T/in"
( ASCN_INSTALLER_LIB=0; . "$INSTALLER" ) < "$T/in" > "$T/out" 2>&1
menu_rc=$?
check '[ "$menu_rc" -eq 0 ] && out_has "Установлен: antiscan 1.10.6"' "главное меню / выход по 9"

setup update
preinstall 1.10.5
printf 'ISP_INTERFACES="ppp0"\nPORTS="22"\nPORTS_FORWARDED="443"\nSAVE_IPSETS="0"\n' > "$ASCN_CONF"
touch "$ASCN_RUN_FILE"
run 'y\n' do_update
check '[ "$rc" -eq 0 ]' "rc=$rc"
check 'opkg_has "opkg upgrade antiscan"' "не вызван opkg upgrade"
check '[ "$(cat "$T/state/inst_antiscan")" = 1.10.6 ]' "версия не обновлена"
check '[ "$(conf ISP_INTERFACES)" = ppp0 ] && [ "$(conf PORTS_FORWARDED)" = 443 ]' "настройки потеряны"
check 'ls "$ASCN_DIR"/ascn.conf.bak.* >/dev/null 2>&1' "нет бэкапа перед обновлением"
check_firewall_readonly

setup update_current
preinstall 1.10.6
run '' do_update
check '[ "$rc" -eq 0 ] && out_has "актуальная версия"' "не распознана актуальная версия"
check '! opkg_has "opkg upgrade"' "upgrade без необходимости"

setup no_netfilter
printf '{"release": "4.3.6.3-0", "title": "4.3.6.3", "components": "opkg,ipv6"}\n' > "$T/state/rci_version"
run 'y\n' do_install
check '[ "$rc" -ne 0 ]' "установка без Netfilter-модулей"
check 'out_has "Модули ядра подсистемы Netfilter"' "нет инструкции по установке компонента"
check '! opkg_has "opkg update" && ! opkg_has "opkg install"' "opkg вызван без модулей ядра"
check '[ ! -e "$OPKG_CONF_DIR/antiscan.conf" ]' "feed создан при отказе"

setup rci_unknown_modules_found
rm -f "$T/state/rci_version"
mkdir -p "$KMOD_DIR/4.9"; touch "$KMOD_DIR/4.9/xt_recent.ko" "$KMOD_DIR/4.9/xt_multiport.ko"
run 'y\nn\n' do_install
check '[ "$rc" -eq 0 ] && out_has "модули в"' "fallback по модулям ядра не сработал"

setup rci_unknown_cancel
rm -f "$T/state/rci_version"
run 'n\n' do_install
check '[ "$rc" -eq 0 ] && ! opkg_has "opkg install antiscan"' "без подтверждения при неизвестном RCI"

setup network_down
rm -f "$T/state/net_primary"
run 'y\nn\n' do_install
check '[ "$rc" -ne 0 ]' "успех при недоступной сети"
check '! opkg_has "opkg install antiscan"' "install без индекса"
check '[ ! -e "$OPKG_CONF_DIR/antiscan.conf" ]' "созданный feed не откатан"

setup mirror_fallback
rm -f "$T/state/net_primary"; touch "$T/state/net_mirror"
run 'y\ny\nn\n' do_install
check '[ "$rc" -eq 0 ]' "rc=$rc"
check '[ "$(cat "$OPKG_CONF_DIR/antiscan.conf")" = "src/gz antiscan $MIRROR" ]' "зеркало не выбрано"
check '[ -f "$T/state/inst_antiscan" ]' "не установлено через зеркало"

setup opkg_install_error
touch "$T/state/install_fail"
run 'y\n' do_install
check '[ "$rc" -ne 0 ] && out_has "не установлен"' "ошибка opkg не распознана"

setup postinst_error
echo 1 > "$T/state/install_rc"
rm -f "$T/state/postinst_start"
run 'y\nn\n' do_install
check '[ "$rc" -eq 0 ] && out_has "ошибка post-install" && out_has "не запущен"' "post-install ошибка не описана"

setup deps_missing
rm -f "$T/state/inst_wget-ssl"
run 'y\ny\nn\n' do_install
check 'opkg_has "opkg install wget-ssl$"' "не поставлен только недостающий wget-ssl"
check '[ -f "$T/state/inst_antiscan" ]' "установка не продолжена"

setup user_feed_preserved
printf 'src/gz antiscan-custom %s\n' "$MIRROR" > "$OPKG_CONF_DIR/my.conf"
touch "$T/state/net_mirror"
cp "$OPKG_CONF_DIR/my.conf" "$T/my.orig"
run 'y\nn\n' do_install
check 'cmp -s "$OPKG_CONF_DIR/my.conf" "$T/my.orig" && [ ! -e "$OPKG_CONF_DIR/antiscan.conf" ]' "пользовательский feed перезаписан"

setup existing_config_kept
mkdir -p "$ASCN_DIR"
printf 'ISP_INTERFACES="eth2.2"\nPORTS="2222"\nPORTS_FORWARDED=""\n' > "$ASCN_CONF"
cp "$ASCN_CONF" "$T/conf.orig"
run 'y\n' do_install
check '[ "$rc" -eq 0 ] && cmp -s "$ASCN_CONF" "$T/conf.orig"' "существующий конфиг изменён"
check 'out_has "оставлен без изменений"' "нет сообщения о сохранённом конфиге"

setup user_cancel_install
run 'n\n' do_install
check '[ "$rc" -eq 0 ] && ! opkg_has "opkg update" && [ ! -e "$OPKG_CONF_DIR/antiscan.conf" ]' "отмена установки не сработала"

setup default_eth3_not_wan
echo "default dev ppp0" > "$T/state/route_default"; cp "$T/state/route_default" "$T/state/route_all"
mkdir -p "$T/sysnet/ppp0"
run 'y\ny\nn\n' do_install
check '[ ! -f "$ASCN_RUN_FILE" ] && grep -q "^ascn stop" "$T/log/ascn.log"' "не предложено остановить при eth3 не WAN"

setup bad_interface
preinstall
cp "$ASCN_CONF" "$T/conf.orig"
run 'eth3;rm -rf /\n$(reboot)\n`id`\nverylonginterface0\n1x\n0\n' do_configure
check 'cmp -s "$ASCN_CONF" "$T/conf.orig"' "конфиг изменён после неверного ввода"
check '[ "$(grep -c "Недопустимое имя интерфейса" "$T/out")" -ge 4 ]' "неверные имена не отклонены"

setup bad_ports
preinstall
cp "$ASCN_CONF" "$T/conf.orig"
run '\n22;reboot\n70000\n0022\n100:50\n1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16\n0\n' do_configure
check 'cmp -s "$ASCN_CONF" "$T/conf.orig"' "конфиг изменён после неверных портов"
check 'out_has "Неверный формат" && out_has "вне диапазона" && out_has "ведущих нулей" && out_has "больше конца" && out_has "не более 15"' "не все ошибки портов распознаны"

setup missing_interface_manual
preinstall
: > "$T/state/route_default"; : > "$T/state/route_all"
run 'ppp1\ny\n\n\ny\n' do_configure
check 'out_has "определить не удалось" && [ "$(conf ISP_INTERFACES)" = ppp1 ]' "ручной ввод отсутствующего интерфейса"

setup rci_wan_detect
preinstall
: > "$T/state/route_default"; : > "$T/state/route_all"
mkdir -p "$T/sysnet/eth2.2"
printf '{"ISP": {"id": "GigabitEthernet0/Vlan2", "description": "Provider", "global": true}, "Home": {"id": "Bridge0", "global": false}}\n' > "$T/state/rci_iface"
mkdir -p "$T/state/sysname_GigabitEthernet0"
printf '"eth2.2"\n' > "$T/state/sysname_GigabitEthernet0/Vlan2"
run '1\n\n\ny\n' do_configure
check '[ "$(conf ISP_INTERFACES)" = eth2.2 ] && out_has "Provider"' "RCI-обнаружение VLAN WAN: $(conf ISP_INTERFACES)"

setup cancel_configure
preinstall
cp "$ASCN_CONF" "$T/conf.orig"
run '1\n22\n\nn\n' do_configure
check 'cmp -s "$ASCN_CONF" "$T/conf.orig" && ! ls "$ASCN_DIR"/ascn.conf.bak.* >/dev/null 2>&1' "отмена в конце изменила конфиг"

setup configure_reload_ok
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
run 'ppp0\n22,8443\n\ny\n' do_configure
check '[ "$rc" -eq 0 ] && out_has "правила Antiscan в iptables на месте"' "успешный reload не подтверждён: rc=$rc"
check 'rules_for "INPUT ppp0 22,8443 ANTISCAN" && rules_for "FORWARD ppp0 22,80,443 ANTISCAN"' "правила не по новой конфигурации"
check 'grep -q -- "-C INPUT -i ppp0 -p tcp -m multiport --dports 22,8443 -j ANTISCAN" "$T/log/fw.log"' "состояние не проверено через iptables -C"
check 'grep -q -- "-S ANTISCAN$" "$T/log/fw.log"' "содержимое цепочки не проверено"
check_firewall_readonly

# reload отклонён проверкой конфигурации (exit 3): правила прежние, ascn.conf возвращается
setup configure_reload_invalid
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/reload_invalid"
cp "$ASCN_CONF" "$T/conf.orig"
run 'ppp0\n\n\ny\ny\n' do_configure
check '[ "$rc" -ne 0 ] && out_has "не применил новые параметры"' "отказ reload не распознан"
check 'cmp -s "$ASCN_CONF" "$T/conf.orig" && rules_for "INPUT eth3 22,80,443 ANTISCAN"' "прежние правила/конфиг не сохранены"
check '! grep -Eq "^ascn (update_rules|restart)" "$T/log/ascn.log"' "лишнее восстановление при целой защите"
check_firewall_readonly

# reload вернул 0, но правила не добавлены: раньше считалось успехом
setup configure_reload_norules
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/reload_norules"
run 'ppp0\n\n\ny\ny\n' do_configure
check 'out_has "защита Antiscan неполная" && out_has "цепочка-ANTISCAN"' "пропавшие правила при rc=0 не обнаружены"
check 'grep -q "^ascn update_rules" "$T/log/ascn.log" && rules_for "INPUT ppp0 22,80,443 ANTISCAN"' "правила не восстановлены update_rules"
check '[ "$rc" -eq 0 ] && [ "$(conf ISP_INTERFACES)" = ppp0 ] && ! grep -q "^ascn restart" "$T/log/ascn.log"' "update_rules: rc=$rc"
check_firewall_readonly

# reload прерван: правила удалены, остался lock, reload-процесса нет
setup configure_reload_interrupted
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/reload_interrupted"
run 'ppp0\n\n\ny\ny\ny\n' do_configure
check '[ ! -f "$ASCN_LOCK_FILE" ] && rules_for "INPUT ppp0 22,80,443 ANTISCAN"' "защита после прерванного reload не восстановлена"
check '[ "$rc" -eq 0 ] && out_has "Удалить зависший"' "lock: rc=$rc"
check_firewall_readonly

# reload ещё работает (ps): lock не трогаем
setup configure_reload_still_running
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/reload_interrupted"
mkdir -p "$T/proc/4242"; printf '/bin/sh\0/opt/bin/antiscan\0reload\0' > "$T/proc/4242/cmdline"
run 'ppp0\n\n\ny\ny\n' do_configure
check '[ "$rc" -ne 0 ] && [ -f "$ASCN_LOCK_FILE" ] && out_has "ещё работает"' "lock снят при работающем reload"
check '! grep -q "^ascn update_rules" "$T/log/ascn.log"' "update_rules при работающем reload"

# /proc недоступен: завершённость reload не проверить — lock не трогаем
setup configure_reload_no_proc
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/reload_interrupted"
export PROC_DIR="$T/no-proc"
run 'ppp0\n\n\ny\ny\n' do_configure
check '[ "$rc" -ne 0 ] && [ -f "$ASCN_LOCK_FILE" ] && out_has "не удаётся проверить"' "lock снят без проверки процессов"

# update_rules не помог → прежний ascn.conf + restart, состояние проверено
setup configure_reload_restore_restart
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/reload_norules" "$T/state/update_rules_fail"
cp "$ASCN_CONF" "$T/conf.orig"
run 'ppp0\n\n\ny\ny\ny\ny\n' do_configure
check 'cmp -s "$ASCN_CONF" "$T/conf.orig" && grep -q "^ascn restart" "$T/log/ascn.log"' "откат + restart не выполнены"
check '[ "$rc" -eq 0 ] && rules_for "INPUT eth3 22,80,443 ANTISCAN" && ! rules_for "INPUT ppp0 22,80,443 ANTISCAN"' "правила после отката: rc=$rc"
check_firewall_readonly

# Пользователь отказался от восстановления — честный отказ, не «успех»
setup configure_reload_recovery_declined
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/reload_norules"
run 'ppp0\n\n\ny\nn\nn\n' do_configure
check '[ "$rc" -ne 0 ] && out_has "не восстановлена"' "отказ от восстановления: rc=$rc"
check_firewall_readonly

# Пустая цепочка с верными переходами: -X не прошёл из-за перехода прежней
# конфигурации, add_rules цепочку не заполняет — успехом считаться не должно
setup chain_empty_stale_jump
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
echo "INPUT eth9 22 ANTISCAN" >> "$T/state/rules"
run 'ppp0\n\n\ny\ny\ny\n' do_configure
check '[ -f "$T/state/chain" ] && [ ! -s "$T/state/chain" ] && rules_for "INPUT eth3 22,80,443 ANTISCAN"' "модель: пустая цепочка не воспроизведена"
check '[ "$rc" -ne 0 ] && out_has "DROP-ascn_ips" && out_has "без защитных правил"' "пустая цепочка не обнаружена: rc=$rc"
check '! out_has "на месте" && ! out_has "Правила Antiscan восстановлены"' "ложное сообщение о восстановлении"
check '! grep -q "^ascn update_rules" "$T/log/ascn.log" && out_has "ссылаются переходы"' "update_rules для пустой цепочки / нет диагностики"
check_firewall_readonly

# Прерван между -F и -X: цепочка пустая, lock остался; restart пересоздаёт её
setup chain_empty_restart_fixes
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/interrupt_after_flush"
run 'ppp0\n\n\ny\ny\ny\n' do_configure
check '[ ! -f "$ASCN_LOCK_FILE" ] && grep -q "^ascn restart" "$T/log/ascn.log"' "restart не выполнен"
check '[ "$rc" -eq 0 ] && grep -q -- "--match-set ascn_ips src -j DROP" "$T/state/chain" && rules_for "INPUT ppp0 22,80,443 ANTISCAN"' "цепочка не пересоздана: rc=$rc"
check_firewall_readonly

# Нет DROP-правил (ошибки _iptables -A upstream не проверяет)
setup chain_no_drop
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/fill_no_drop"
run 'ppp0\n\n\ny\ny\ny\n' do_configure
check '[ "$rc" -ne 0 ] && out_has "DROP-ascn_ips" && out_has "DROP-ascn_subnets" && ! out_has "на месте"' "отсутствие DROP не обнаружено: rc=$rc"
check_firewall_readonly

# Частично созданная цепочка: DROP есть, правил наполнения ascn_ips нет
setup chain_partial
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/fill_partial"
run 'ppp0\n\n\ny\ny\ny\n' do_configure
check '[ "$rc" -ne 0 ] && out_has "connlimit" && out_has "recent-update" && ! out_has "DROP-ascn_ips" && ! out_has "на месте"' "частичная цепочка не обнаружена: rc=$rc"

# Нет сбора кандидатов в подсети (распределённые сканеры)
setup chain_no_candidates
preinstall
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/fill_no_candidates"
run 'ppp0\n\n\ny\ny\ny\n' do_configure
check '[ "$rc" -ne 0 ] && out_has "ANTISCAN:SET-ascn_candidates" && ! out_has "DROP-ascn_ips" && ! out_has "на месте"' "нет правила ascn_candidates не обнаружено: rc=$rc"
check_firewall_readonly

# Honeypot: норма и пустая ANTISCAN_HONEYPOT
setup honeypot_ok
preinstall
printf 'ISP_INTERFACES="eth3"\nPORTS="22"\nPORTS_FORWARDED=""\nENABLE_HONEYPOT="1"\nHONEYPOT_PORTS="23"\nENABLE_IPS_BAN="1"\n' > "$ASCN_CONF"
mkdir -p "$T/sysnet/ppp0"
start_ascn
run 'ppp0\n\n\ny\n' do_configure
check '[ "$rc" -eq 0 ] && out_has "на месте" && grep -q -- "-S ANTISCAN_HONEYPOT$" "$T/log/fw.log"' "honeypot: rc=$rc"

setup honeypot_chain_empty
preinstall
printf 'ISP_INTERFACES="eth3"\nPORTS="22"\nPORTS_FORWARDED=""\nENABLE_HONEYPOT="1"\nHONEYPOT_PORTS="23"\nENABLE_IPS_BAN="1"\n' > "$ASCN_CONF"
mkdir -p "$T/sysnet/ppp0"
start_ascn
touch "$T/state/hp_fill_empty"
rm -f "$T/state/chain_hp"; "$ASCN_INIT" update_rules >/dev/null 2>&1
run 'ppp0\n\n\ny\ny\ny\n' do_configure
check '[ "$rc" -ne 0 ] && out_has "ANTISCAN_HONEYPOT:DROP-ascn_honeypot" && out_has "ANTISCAN_HONEYPOT:SET-ascn_honeypot" && ! out_has "на месте"' "пустая honeypot-цепочка не обнаружена: rc=$rc"
check_firewall_readonly

# IPS выключен: цепочка только с RETURN — не ошибка
setup ips_disabled_ok
preinstall
printf 'ISP_INTERFACES="eth3"\nPORTS="22"\nPORTS_FORWARDED=""\nENABLE_IPS_BAN="0"\nCUSTOM_LISTS_BLOCK_MODE="0"\n' > "$ASCN_CONF"
mkdir -p "$T/sysnet/ppp0"
start_ascn
run 'ppp0\n\n\ny\n' do_configure
check '[ "$rc" -eq 0 ] && out_has "на месте" && ! out_has "ascn_candidates"' "ложная тревога при ENABLE_IPS_BAN=0: rc=$rc"
check '! grep -q ascn_candidates "$T/state/chain"' "модель: при ENABLE_IPS_BAN=0 правило кандидатов не создаётся"

# Прежний индекс не удалось отложить — свежесть не подтверждена, не принимаем
setup cached_index_unmovable
preinstall 1.10.5
mkdir -p "$T/opt/var/opkg-lists"; echo 1.10.5 > "$T/opt/var/opkg-lists/antiscan"
touch "$T/state/mv_fail"
run 'y\n' do_update
check '[ "$rc" -ne 0 ] && out_has "Не удалось отложить" && ! out_has "актуальная версия" && ! opkg_has "opkg upgrade"' "неперемещённый индекс принят: rc=$rc"

# Устаревший индекс в кэше opkg при недоступном репозитории
setup stale_index_update
preinstall 1.10.5
mkdir -p "$T/opt/var/opkg-lists"; echo 1.10.5 > "$T/opt/var/opkg-lists/antiscan"
rm -f "$T/state/net_primary"
run '' do_update
check '[ "$rc" -ne 0 ] && ! out_has "актуальная версия"' "устаревший индекс принят за свежий: rc=$rc"
check '[ "$(cat "$T/opt/var/opkg-lists/antiscan")" = 1.10.5 ] && ! ls "$T/opt/var/opkg-lists"/*ascn-prev* >/dev/null 2>&1' "кэш opkg не возвращён на место"
check '! opkg_has "opkg upgrade"' "upgrade по устаревшему индексу"

setup stale_index_install
mkdir -p "$T/opt/var/opkg-lists"; echo 1.10.6 > "$T/opt/var/opkg-lists/antiscan"
rm -f "$T/state/net_primary"
run 'y\n' do_install
check '[ "$rc" -ne 0 ] && ! opkg_has "opkg install antiscan"' "установка по устаревшему индексу"
check '[ ! -e "$OPKG_CONF_DIR/antiscan.conf" ]' "созданный feed не откатан"

# Другой репозиторий недоступен, индекс Antiscan загружен заново — продолжаем
setup other_feed_down
printf 'src/gz entware http://bin.entware.net/mipselsf-k3.4\n' >> "$T/opt/etc/opkg.conf"
touch "$T/state/other_fail"
run 'y\nn\n' do_install
check '[ "$rc" -eq 0 ] && [ -f "$T/state/inst_antiscan" ] && out_has "загружен заново"' "свежий индекс Antiscan отвергнут: rc=$rc"

# Строка feed дописана в чужой antiscan.conf → откат при неудаче, байт в байт
setup foreign_feed_rollback_network
printf 'src/gz other http://x' > "$OPKG_CONF_DIR/antiscan.conf"
cp -p "$OPKG_CONF_DIR/antiscan.conf" "$T/feed.orig"
rm -f "$T/state/net_primary"
run 'y\n' do_install
check '[ "$rc" -ne 0 ] && cmp -s "$OPKG_CONF_DIR/antiscan.conf" "$T/feed.orig"' "дописанная строка не откатана (сеть)"
check '! ls "$T/tmp"/ascn-feed.* >/dev/null 2>&1' "временная копия feed не удалена"

setup foreign_feed_rollback_install
printf '# my repo\nsrc/gz other http://x\n' > "$OPKG_CONF_DIR/antiscan.conf"
cp -p "$OPKG_CONF_DIR/antiscan.conf" "$T/feed.orig"
touch "$T/state/install_fail"
run 'y\n' do_install
check '[ "$rc" -ne 0 ] && cmp -s "$OPKG_CONF_DIR/antiscan.conf" "$T/feed.orig"' "дописанная строка не откатана (opkg install)"

setup created_feed_rollback_install
touch "$T/state/install_fail"
run 'y\n' do_install
check '[ "$rc" -ne 0 ] && [ ! -e "$OPKG_CONF_DIR/antiscan.conf" ]' "созданный feed не откатан после ошибки opkg install"

setup foreign_feed_changed_meanwhile
printf 'src/gz other http://x\n' > "$OPKG_CONF_DIR/antiscan.conf"
rm -f "$T/state/net_primary"
(
  . "$INSTALLER"
  ensure_feed "$FEED_URL_PRIMARY" >/dev/null
  echo 'src/gz extra http://y' >> "$OPKG_CONF_DIR/antiscan.conf"
  _install_rollback_feed
) > "$T/out" 2>&1
check 'grep -q "^src/gz extra http://y$" "$OPKG_CONF_DIR/antiscan.conf" && out_has "изменён во время установки"' "чужие изменения затёрты откатом"

setup foreign_feed_kept_on_success
printf 'src/gz other http://x\n' > "$OPKG_CONF_DIR/antiscan.conf"
run 'y\nn\n' do_install
check '[ "$rc" -eq 0 ] && grep -q "^src/gz other http://x$" "$OPKG_CONF_DIR/antiscan.conf" && grep -q "^src/gz antiscan $PRIMARY$" "$OPKG_CONF_DIR/antiscan.conf"' "feed после успешной установки"
check '! ls "$T/tmp"/ascn-feed.* >/dev/null 2>&1' "временная копия feed не удалена"

setup remote_session_warning
preinstall
export SSH_CLIENT="203.0.113.5 50000 22"
run '1\n\n\nn\n' do_configure
check 'out_has "203.0.113.5"' "нет предупреждения об удалённом доступе"
unset SSH_CLIENT

setup broken_config_refused
preinstall
printf 'ISP_INTERFACES="eth3"\nPORTS=$(reboot)\n' > "$ASCN_CONF"
run '' do_configure
check '[ "$rc" -ne 0 ] && out_has "не примет"' "битый ascn.conf не отклонён"

setup remove_keep
preinstall
touch "$ASCN_RUN_FILE"
printf 'TOKEN' > "$ASCN_DIR/.tkn"; printf 'KEY' > "$ASCN_DIR/.k"
chmod 644 "$ASCN_DIR/.tkn" "$ASCN_DIR/.k"
old_umask=$(umask); umask 022
run 'y\n\nn\n' do_remove
umask "$old_umask"
bk=$(find "$T/opt/etc" -maxdepth 1 -name 'antiscan-backup-*' | head -n 1)
check 'case "$(ls -ld "$bk")" in drwx------*) true ;; *) false ;; esac' "каталог копии доступен не только root: $(ls -ld "$bk" 2>&1)"
check 'case "$(ls -l "$bk/.tkn")$(ls -l "$bk/.k")" in -rw-------*-rw-------*) true ;; *) false ;; esac' "токен в копии читаем не только root"
check '[ "$(cat "$bk/.tkn")" = TOKEN ] && [ "$(cat "$bk/.k")" = KEY ]' "токен скопирован не полностью"
check 'case "$(ls -l "$ASCN_DIR/.tkn" 2>/dev/null)" in ""|-rw-r--r--*) true ;; *) false ;; esac' "права исходных файлов изменены"
check '[ "$rc" -eq 0 ] && [ ! -f "$T/state/inst_antiscan" ]' "пакет не удалён"
check 'grep -q "^ascn stop" "$T/log/ascn.log"' "служба не остановлена"
check '! opkg_has "autoremove"' "удаление затронуло зависимости"
check 'ls "$T/opt/etc"/antiscan-backup-*/ascn.conf >/dev/null 2>&1 && ls "$T/opt/etc"/antiscan-backup-*/.tkn >/dev/null 2>&1' "нет копии настроек"
check '[ -f "$ASCN_CONF" ] && [ -f "$OPKG_CONF_DIR/antiscan.conf" ]' "настройки/feed удалены вопреки выбору"
check 'out_has "Antiscan удалён."' "нет итогового сообщения"
check_firewall_readonly

setup remove_purge
preinstall
echo "keep me" > "$ASCN_DIR/notes.txt"
run 'y\nn\ny\n' do_remove
check '[ "$rc" -eq 0 ] && [ ! -f "$ASCN_CONF" ] && [ -f "$ASCN_DIR/notes.txt" ]' "удалены не только файлы Antiscan"
check '[ ! -e "$OPKG_CONF_DIR/antiscan.conf" ]' "feed не удалён по запросу"
check '[ -f "$T/opt/etc/opkg.conf" ]' "затронут opkg.conf"

setup remove_leftovers_reported
preinstall
touch "$T/state/chain_left"
echo '*/1 * * * * /opt/etc/init.d/S99ascn read_candidates &' > "$T/state/crontab"
run 'y\n\nn\n' do_remove
check 'out_has "цепочка ANTISCAN" && out_has "crontab"' "остатки не обнаружены"
check_firewall_readonly

setup remove_fail
preinstall
touch "$T/state/remove_fail"
run 'y\nn\n' do_remove
check '[ "$rc" -ne 0 ] && [ -f "$ASCN_CONF" ] && [ -f "$T/state/inst_antiscan" ]' "ошибка удаления не обработана"

setup remove_cancel
preinstall
run 'n\n' do_remove
check '[ -f "$T/state/inst_antiscan" ] && ! opkg_has "remove"' "отмена удаления не сработала"

setup service_and_list
preinstall
printf 'ISP_INTERFACES="ppp0"\nPORTS="22"\nPORTS_FORWARDED=""\nENABLE_HONEYPOT="1"\nHONEYPOT_PORTS="23"\n' > "$ASCN_CONF"
run '1\n' do_service
check '[ -f "$ASCN_RUN_FILE" ]' "start не сработал"
run '' do_list
check 'out_has "list ips" && out_has "list subnets" && out_has "list honeypot" && ! out_has "list ndm_lockout"' "списки блокировки"
run '2\ny\n' do_service
check '[ ! -f "$ASCN_RUN_FILE" ]' "stop не сработал"
run '3\ny\n' do_service
check '[ -f "$ASCN_RUN_FILE" ] && grep -q "^ascn restart" "$T/log/ascn.log"' "restart не сработал"
check_firewall_readonly

setup edit_config
preinstall
touch "$OPT_BIN/vi"
run '' do_edit
check 'grep -q "^ascn edit config" "$T/log/ascn.log" && ls "$ASCN_DIR"/ascn.conf.bak.* >/dev/null 2>&1' "edit config / бэкап"

setup unit_helpers
(
  . "$INSTALLER"
  parse_ports "22, 80,443,80" && [ "$PORTS_RESULT" = "22,80,443" ] || echo "parse_ports dedupe"
  parse_ports "40000:40100" && [ "$PORTS_EPHEMERAL" = 1 ] || echo "parse_ports ephemeral"
  parse_ports "" && [ -z "$PORTS_RESULT" ] || echo "parse_ports empty"
  parse_ifaces "eth3,ppp0 eth3" && [ "$IFACES_RESULT" = "eth3 ppp0" ] || echo "parse_ifaces"
  parse_ifaces "*" >/dev/null 2>&1 && echo "parse_ifaces glob"
  printf 'A="1"\n# c\n\nB="x y"\n' > "$T/f1"; conf_format_ok "$T/f1" >/dev/null || echo "format ok rejected"
  printf 'A="1"\n  \n' > "$T/f2"; conf_format_ok "$T/f2" >/dev/null && echo "whitespace line accepted"
  printf 'A="$(x)"\n' > "$T/f3"; conf_format_ok "$T/f3" >/dev/null && echo "dollar accepted"
  mkdir -p "$ASCN_DIR"
  printf '# head\nPORTS="1"\nX="keep"\nPORTS="2"\n' > "$ASCN_CONF"
  conf_write_values "ppp0" "22" "" || echo "write failed"
  [ "$(cat "$ASCN_CONF")" = "# head
PORTS=\"22\"
X=\"keep\"
ISP_INTERFACES=\"ppp0\"
PORTS_FORWARDED=\"\"" ] || { echo "conf_write_values:"; cat "$ASCN_CONF"; }
  printf 'src/gz other http://x\n' > "$OPKG_CONF_DIR/antiscan.conf"
  ensure_feed "$FEED_URL_PRIMARY" >/dev/null
  grep -q '^src/gz other http://x$' "$OPKG_CONF_DIR/antiscan.conf" || echo "ensure_feed overwrote foreign file"
  feed_is_official_file "$OPKG_CONF_DIR/antiscan.conf" && echo "foreign file treated as official"
  # Разбор RCI без jq (до установки Antiscan jq может отсутствовать)
  mkdir -p "$T/nojq"
  for t in tr sed grep head cat; do ln -s "$(command -v "$t")" "$T/nojq/$t"; done
  printf '{\n "ISP": {\n  "id": "PPPoE0",\n  "description": "Dom.ru",\n  "global": true\n },\n "Home": {\n  "id": "Bridge0",\n  "global": false\n }\n}\n' > "$T/state/rci_iface"
  r=$(PATH="$T/bin:$T/nojq"; command -v jq >/dev/null && echo "jq still visible"; rci_global_ifaces)
  [ "$r" = "PPPoE0|Dom.ru" ] || echo "rci_global_ifaces without jq: $r"
) > "$T/unit" 2>&1
check '[ ! -s "$T/unit" ]' "$(tr '\n' ' ' < "$T/unit")"

printf '%s: %d checks passed, %d failed\n' "$(basename "$0")" "$passes" "$failures"
[ "$failures" -eq 0 ]
