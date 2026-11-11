#!/bin/sh
# installer_antiscan.sh — меню Antiscan для Entware (Keenetic / Netcraze)
# Antiscan:    https://github.com/dimon27254/antiscan
# Репозиторий: https://dimon27254.github.io/antiscan/all (зеркало: https://bin.antiscan.ru/packages/all)
# Обёртка:     https://github.com/rndnaame/nfqws-menu
#
# Установщик не реализует firewall-логику: правила iptables/ipset, cron и hook
# netfilter.d создаёт и удаляет сам пакет Antiscan (S99ascn / opkg hooks).
# Здесь — только opkg, правка трёх параметров ascn.conf и штатный CLI Antiscan.
#
# Запуск:
#   sh installer_antiscan.sh
#   curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_antiscan.sh | sh
#
# shellcheck disable=SC3043  # local: поддерживается BusyBox ash / dash

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[0;36m')
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[!]${NC} $*"; }

# Пути (переопределяются только для тестов в изолированном окружении)
ASCN_PKG="antiscan"
ASCN_DIR="${ASCN_DIR:-/opt/etc/antiscan}"
ASCN_CONF="${ASCN_CONF:-$ASCN_DIR/ascn.conf}"
ASCN_INIT="${ASCN_INIT:-/opt/etc/init.d/S99ascn}"
ASCN_HOOK="${ASCN_HOOK:-/opt/etc/ndm/netfilter.d/099-ascn.sh}"
ASCN_RUN_FILE="${ASCN_RUN_FILE:-/tmp/ascn.run}"
OPKG_CONF_DIR="${OPKG_CONF_DIR:-/opt/etc/opkg}"
OPKG_MAIN_CONF="${OPKG_MAIN_CONF:-/opt/etc/opkg.conf}"
ASCN_FEED_CONF="$OPKG_CONF_DIR/antiscan.conf"
OPT_BIN="${OPT_BIN:-/opt/bin}"
RCI_BASE="${RCI_BASE:-http://127.0.0.1:79/rci}"
SYS_NET_DIR="${SYS_NET_DIR:-/sys/class/net}"
KMOD_DIR="${KMOD_DIR:-/lib/modules}"
ASCN_BACKUP_BASE="${ASCN_BACKUP_BASE:-/opt/etc}"

FEED_URL_PRIMARY="https://dimon27254.github.io/antiscan/all"
FEED_URL_MIRROR="https://bin.antiscan.ru/packages/all"

# Значения из ascn.conf пакета (etc/antiscan/ascn.conf upstream)
DEF_ISP="eth3"
DEF_PORTS="22,80,443"
DEF_FWD="22,80,443"

# Файлы пользователя в $ASCN_DIR (conffiles пакета + токен RCI, см. rci.sh upstream)
ASCN_USER_FILES="ascn.conf ascn_crontab.conf ascn_custom_blacklist.txt ascn_custom_exclude.txt ascn_custom_whitelist.txt .tkn .k"

NL='
'

# ---------------------------------------------------------------------------
# Ввод
# ---------------------------------------------------------------------------
REPLY_LINE=""

# Строка → REPLY_LINE. 1 = EOF (трактуем как отмену).
read_line() {
  REPLY_LINE=""
  if [ "${ASCN_NO_TTY:-0}" != "1" ] && [ -c /dev/tty ]; then
    IFS= read -r REPLY_LINE < /dev/tty || return 1
  else
    IFS= read -r REPLY_LINE || return 1
  fi
  REPLY_LINE=$(printf '%s' "$REPLY_LINE" | tr -d '\r')
  return 0
}

# $1=вопрос  $2=y|n (ответ по умолчанию). EOF → «нет».
confirm() {
  local hint="[y/N]"
  [ "$2" = "y" ] && hint="[Y/n]"
  printf '%s' "${YELLOW}[?]${NC} $1 $hint: "
  read_line || { echo; return 1; }
  case "$REPLY_LINE" in
    y|Y|yes|YES|д|Д|да|Да) return 0 ;;
    "") [ "$2" = "y" ] ;;
    *) return 1 ;;
  esac
}

# Команда с вводом с терминала: postinst (токен RCI) и antiscan edit (nano) читают
# stdin, а при «curl … | sh» stdin — это сам скрипт.
run_tty() {
  if [ "${ASCN_NO_TTY:-0}" != "1" ] && ( : < /dev/tty ) 2>/dev/null; then
    "$@" < /dev/tty
  else
    "$@"
  fi
}

pause() {
  printf '%s' "${DIM}Нажмите Enter...${NC} "
  read_line || true
}

# ---------------------------------------------------------------------------
# Сеть / RCI
# ---------------------------------------------------------------------------
http_get() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --connect-timeout 3 --max-time "${2:-8}" "$1" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- -T "${2:-8}" "$1" 2>/dev/null
  else
    return 1
  fi
}

rci_get() { http_get "$RCI_BASE/$1" 5; }

# Нужен ли токен для RCI (KeeneticOS 5.2+): required | open | unknown
rci_auth_state() {
  local code
  command -v curl >/dev/null 2>&1 || { echo unknown; return 0; }
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 "$RCI_BASE/whoami" 2>/dev/null)
  case "$code" in
    4??) echo required ;;
    2??) echo open ;;
    *)   echo unknown ;;
  esac
}

# Компонент «Модули ядра подсистемы Netfilter» (opkg-kmod-netfilter).
# NF_KMOD_STATE = yes | no | unknown, NF_KMOD_SOURCE — как определено.
NF_KMOD_STATE=""
NF_KMOD_SOURCE=""
check_nf_kmod() {
  local json
  NF_KMOD_STATE="unknown"
  NF_KMOD_SOURCE=""
  json=$(rci_get show/version) || json=""
  case "$json" in
    *'"release"'*|*'"title"'*|*'"components"'*)
      NF_KMOD_SOURCE="RCI show version"
      case "$json" in
        *opkg-kmod-netfilter*) NF_KMOD_STATE="yes" ;;
        *)                     NF_KMOD_STATE="no" ;;
      esac
      return 0
      ;;
  esac
  # RCI недоступен (или требует токен) — ищем модули, которые грузит Antiscan
  if lsmod 2>/dev/null | grep -q '^xt_recent ' && lsmod 2>/dev/null | grep -q '^xt_multiport '; then
    NF_KMOD_STATE="yes"; NF_KMOD_SOURCE="lsmod"
    return 0
  fi
  if [ -d "$KMOD_DIR" ] &&
     [ -n "$(find "$KMOD_DIR" -name 'xt_recent.ko*' 2>/dev/null | head -n 1)" ] &&
     [ -n "$(find "$KMOD_DIR" -name 'xt_multiport.ko*' 2>/dev/null | head -n 1)" ]; then
    NF_KMOD_STATE="yes"; NF_KMOD_SOURCE="модули в $KMOD_DIR"
  fi
  return 0
}

print_nf_kmod_help() {
  error "Не установлен компонент «Модули ядра подсистемы Netfilter» (opkg-kmod-netfilter)."
  echo "  Установите его через веб-интерфейс роутера:"
  echo "  «Параметры системы» → «Изменить набор компонентов» → «Модули ядра подсистемы Netfilter»."
  echo "  До KeeneticOS 4.3 компонент доступен только вместе с «Протокол IPv6»."
  echo "  После установки компонента роутер перезагрузится — затем запустите установку снова."
}

# ---------------------------------------------------------------------------
# opkg
# ---------------------------------------------------------------------------
pkg_installed() {
  opkg status "$1" 2>/dev/null | grep -Eq '^Status:.*[[:space:]]installed[[:space:]]*$'
}

# Пакет известен opkg, но не в состоянии installed (unpacked / half-configured)
pkg_broken() {
  local st
  st=$(opkg status "$1" 2>/dev/null | sed -n 's/^Status:[[:space:]]*//p' | head -n 1)
  [ -n "$st" ] || return 1
  case "$st" in *not-installed*) return 1 ;; esac
  pkg_installed "$1" && return 1
  return 0
}

pkg_version() {
  pkg_installed "$1" || return 0
  opkg status "$1" 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n 1
}

# Версия antiscan в загруженном индексе репозитория (пусто = индекса нет)
feed_version() {
  opkg list "$ASCN_PKG" 2>/dev/null | awk -v p="$ASCN_PKG" '$1 == p && $2 == "-" { print $3; exit }'
}

upgrade_available() {
  opkg list-upgradable 2>/dev/null | awk -v p="$ASCN_PKG" '$1 == p { f = 1 } END { exit !f }'
}

# ---------------------------------------------------------------------------
# Репозиторий Antiscan в opkg
# ---------------------------------------------------------------------------
FEED_FILE=""
FEED_URL=""
FEED_CREATED=0

# Первая строка src с репозиторием Antiscan → «файл url». 1 = не найдено.
feed_find() {
  local f res
  for f in "$OPKG_MAIN_CONF" "$OPKG_CONF_DIR"/*.conf; do
    [ -f "$f" ] || continue
    res=$(awk -v p="$FEED_URL_PRIMARY" -v m="$FEED_URL_MIRROR" '
      $1 ~ /^src/ {
        u = $3; sub(/\/+$/, "", u)
        if ($2 == "antiscan" || u == p || u == m) { print u; exit }
      }' "$f" 2>/dev/null)
    if [ -n "$res" ]; then
      printf '%s %s\n' "$f" "$res"
      return 0
    fi
  done
  return 1
}

# Файл содержит только одну строку «src/gz antiscan <официальный url>»
# (создан этим установщиком или официальным install.sh) — его можно менять.
feed_is_official_file() {
  [ -f "$1" ] || return 1
  awk -v p="$FEED_URL_PRIMARY" -v m="$FEED_URL_MIRROR" '
    /^[[:space:]]*$/ { next }
    { n++; if (!($1 == "src/gz" && $2 == "antiscan" && ($3 == p || $3 == m) && NF == 3)) bad = 1 }
    END { exit (bad || n != 1) }' "$1"
}

ensure_feed() {
  local found
  if found=$(feed_find); then
    FEED_FILE=${found%% *}
    FEED_URL=${found#* }
    info "Репозиторий Antiscan уже настроен: $FEED_URL ($FEED_FILE) — оставляем как есть."
    return 0
  fi
  mkdir -p "$OPKG_CONF_DIR" || { error "Не удалось создать $OPKG_CONF_DIR"; return 1; }
  if [ -e "$ASCN_FEED_CONF" ]; then
    # Чужой файл с тем же именем: только дописываем строку, не перезаписываем
    printf '\nsrc/gz antiscan %s\n' "$1" >> "$ASCN_FEED_CONF" || return 1
    info "Строка репозитория дописана в существующий $ASCN_FEED_CONF"
  else
    printf 'src/gz antiscan %s\n' "$1" > "$ASCN_FEED_CONF" || return 1
    FEED_CREATED=1
    info "Репозиторий записан: $ASCN_FEED_CONF"
  fi
  FEED_FILE="$ASCN_FEED_CONF"
  FEED_URL="$1"
  return 0
}

set_feed_url() {
  printf 'src/gz antiscan %s\n' "$1" > "$FEED_FILE" || return 1
  FEED_URL="$1"
}

# opkg update + проверка, что индекс Antiscan действительно загружен
FEED_VER=""
opkg_refresh() {
  local rc=0
  info "opkg update ..."
  opkg update || rc=$?
  FEED_VER=$(feed_version)
  if [ -n "$FEED_VER" ]; then
    [ "$rc" -ne 0 ] && warn "opkg update вернул код $rc (вероятно, недоступен другой репозиторий), индекс Antiscan загружен."
    return 0
  fi
  error "Индекс репозитория Antiscan не загружен (${FEED_URL:-?}). Сеть / DNS / HTTPS?"
  return 1
}

# Явно выбираемое зеркало — только для файла, который мы можем менять
refresh_with_fallback() {
  local alt old
  opkg_refresh && return 0
  if ! feed_is_official_file "$FEED_FILE"; then
    warn "Зеркало можно указать вручную в $FEED_FILE: src/gz antiscan $FEED_URL_MIRROR"
    return 1
  fi
  old="$FEED_URL"
  if [ "$old" = "$FEED_URL_MIRROR" ]; then alt="$FEED_URL_PRIMARY"; else alt="$FEED_URL_MIRROR"; fi
  if confirm "Попробовать зеркало $alt?" n; then
    set_feed_url "$alt" || return 1
    info "Репозиторий: $alt"
    opkg_refresh && return 0
    set_feed_url "$old" && warn "Зеркало тоже недоступно — возвращён $old"
  fi
  return 1
}

# wget-ssl + ca-bundle ставит и официальный install.sh (HTTPS-репозиторий)
ensure_https_deps() {
  local missing="" p
  for p in wget-ssl ca-bundle; do
    pkg_installed "$p" || missing="${missing:+$missing }$p"
  done
  [ -z "$missing" ] && return 0
  warn "Для HTTPS-репозитория Antiscan нужны пакеты (как в официальном install.sh): $missing"
  if ! confirm "Установить $missing?" y; then
    warn "Продолжаем без них — opkg может не скачать индекс по HTTPS."
    return 0
  fi
  info "opkg update (индекс Entware для $missing) ..."
  opkg update >/dev/null 2>&1 || true
  # shellcheck disable=SC2086  # список имён пакетов
  if ! opkg install $missing; then
    error "Не удалось установить: $missing"
    pkg_installed wget-nossl && warn "Установлен wget-nossl — при конфликте удалите его вручную: opkg remove wget-nossl"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# ascn.conf
# ---------------------------------------------------------------------------
# Значение KEY="..." (последнее вхождение, как при source). Файл не исполняется.
conf_get() {
  awk -v k="$1" '
    index($0, k "=\"") == 1 {
      v = substr($0, length(k) + 3); sub(/"[[:space:]]*$/, "", v); val = v; f = 1
    }
    END { if (f) print val }' "${2:-$ASCN_CONF}" 2>/dev/null
}

# Формат, который принимает Antiscan (validate_config_strings): пустые строки,
# комментарии с # в начале строки и только KEY="значение" без " \ ` $.
conf_format_ok() {
  awk '
    /^$/ || /^#/ { next }
    !/^[A-Z_]+="[^"\\`$]*"$/ { bad = 1; printf "  строка %d: %s\n", NR, $0 }
    END { exit bad }' "$1"
}

is_default_config() {
  [ "$(conf_get ISP_INTERFACES)" = "$DEF_ISP" ] &&
  [ "$(conf_get PORTS)" = "$DEF_PORTS" ] &&
  [ "$(conf_get PORTS_FORWARDED)" = "$DEF_FWD" ]
}

BACKUP_PATH=""
backup_conf() {
  local f="${1:-$ASCN_CONF}"
  BACKUP_PATH=""
  [ -f "$f" ] || return 0
  BACKUP_PATH="${f}.bak.$(date +%Y%m%d%H%M%S)"
  [ -e "$BACKUP_PATH" ] && BACKUP_PATH="${BACKUP_PATH}.$$"
  if cp -p "$f" "$BACKUP_PATH"; then
    info "Бэкап: $BACKUP_PATH"
    return 0
  fi
  error "Не удалось создать бэкап $f"
  BACKUP_PATH=""
  return 1
}

# Меняет только ISP_INTERFACES / PORTS / PORTS_FORWARDED, остальное без изменений.
# Значения уже провалидированы (parse_ifaces / parse_ports).
conf_write_values() {
  local tmp="${ASCN_CONF}.tmp.$$"
  cp -p "$ASCN_CONF" "$tmp" 2>/dev/null || : > "$tmp" || return 1
  if ! W_ISP="$1" W_PORTS="$2" W_FWD="$3" awk '
    BEGIN {
      n = split("ISP_INTERFACES PORTS PORTS_FORWARDED", keys, " ")
      v["ISP_INTERFACES"] = ENVIRON["W_ISP"]
      v["PORTS"] = ENVIRON["W_PORTS"]
      v["PORTS_FORWARDED"] = ENVIRON["W_FWD"]
    }
    match($0, /^[A-Z_]+="/) {
      k = substr($0, 1, RLENGTH - 2)
      if (k in v) {
        if (!(k in done)) { print k "=\"" v[k] "\""; done[k] = 1 }
        next
      }
    }
    { print }
    END { for (i = 1; i <= n; i++) if (!(keys[i] in done)) print keys[i] "=\"" v[keys[i]] "\"" }
  ' "$ASCN_CONF" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! conf_format_ok "$tmp" >/dev/null ||
     [ "$(conf_get ISP_INTERFACES "$tmp")" != "$1" ] ||
     [ "$(conf_get PORTS "$tmp")" != "$2" ] ||
     [ "$(conf_get PORTS_FORWARDED "$tmp")" != "$3" ]; then
    rm -f "$tmp"
    error "Проверка нового ascn.conf не прошла — файл не изменён."
    return 1
  fi
  mv -f "$tmp" "$ASCN_CONF"
}

# ---------------------------------------------------------------------------
# Валидация ввода
# ---------------------------------------------------------------------------
# Как в check_config Antiscan: буква + 1..14 символов [a-zA-Z0-9_.:-]
valid_iface_name() {
  case "$1" in ''|lo) return 1 ;; esac
  printf '%s\n' "$1" | grep -Eq '^[a-zA-Z][a-zA-Z0-9_.:-]{1,14}$'
}

# $1 — имена через пробел/запятую → IFACES_RESULT (без дублей, ≤10)
IFACES_RESULT=""
parse_ifaces() {
  local list i n=0
  IFACES_RESULT=""
  list=$(printf '%s' "$1" | tr ',' ' ')
  set -f
  for i in $list; do
    if ! valid_iface_name "$i"; then
      set +f
      error "Недопустимое имя интерфейса: «$i» (буква + 1..14 символов a-z A-Z 0-9 _ . : -)"
      return 1
    fi
    case " $IFACES_RESULT " in *" $i "*) continue ;; esac
    IFACES_RESULT="${IFACES_RESULT:+$IFACES_RESULT }$i"
    n=$((n + 1))
  done
  set +f
  if [ "$n" -lt 1 ]; then error "Не указан ни один интерфейс."; return 1; fi
  if [ "$n" -gt 10 ]; then error "Antiscan поддерживает не более 10 интерфейсов."; return 1; fi
  return 0
}

# $1 — «22,80,443» / «8000:8100» → PORTS_RESULT. Пусто = пустой список.
PORTS_RESULT=""
PORTS_EPHEMERAL=0
_ports_fail() { IFS=$_pp_ifs; set +f; error "$1"; return 1; }
parse_ports() {
  local p tok a b x cnt=0 out=""
  PORTS_RESULT=""
  PORTS_EPHEMERAL=0
  p=$(printf '%s' "$1" | tr -d ' \t')
  [ -z "$p" ] && return 0
  if ! printf '%s\n' "$p" | grep -Eq '^[0-9]{1,5}(:[0-9]{1,5})?(,[0-9]{1,5}(:[0-9]{1,5})?)*$'; then
    error "Неверный формат портов: «$p». Пример: 22,80,443 или 8000:8100"
    return 1
  fi
  _pp_ifs=$IFS
  set -f
  IFS=,
  for tok in $p; do
    IFS=$_pp_ifs
    case "$tok" in
      *:*) a=${tok%%:*}; b=${tok#*:} ;;
      *)   a=$tok; b="" ;;
    esac
    for x in $a $b; do
      case "$x" in 0*) _ports_fail "Порт без ведущих нулей и не 0: «$x»"; return 1 ;; esac
      [ "$x" -le 65535 ] || { _ports_fail "Порт вне диапазона 1..65535: «$x»"; return 1; }
    done
    if [ -n "$b" ] && [ "$a" -gt "$b" ]; then
      _ports_fail "Начало диапазона больше конца: «$tok»"; return 1
    fi
    case ",$out," in *",$tok,"*) IFS=,; continue ;; esac
    out="${out:+$out,}$tok"
    if [ -n "$b" ]; then
      cnt=$((cnt + 2))
      [ "$a" -le 60999 ] && [ "$b" -ge 32768 ] && PORTS_EPHEMERAL=1
    else
      cnt=$((cnt + 1))
      [ "$a" -ge 32768 ] && [ "$a" -le 60999 ] && PORTS_EPHEMERAL=1
    fi
    IFS=,
  done
  IFS=$_pp_ifs
  set +f
  if [ "$cnt" -gt 15 ]; then
    error "Antiscan принимает не более 15 портов (диапазон считается за 2)."
    return 1
  fi
  PORTS_RESULT=$out
  return 0
}

# ---------------------------------------------------------------------------
# Определение WAN (только подсказка — пользователь подтверждает выбор)
# ---------------------------------------------------------------------------
WAN_RAW=""
WAN_LIST=""   # строки «iface|источник|описание»

_wan_add() {
  valid_iface_name "$1" || return 0
  case "$1" in br[0-9]*|br-*) return 0 ;; esac
  WAN_RAW="${WAN_RAW}$1|$2|$3${NL}"
}

# Интерфейсы-подключения к интернету из RCI ("global": true) → «id|описание»
rci_global_ifaces() {
  local json
  json=$(rci_get show/interface) || return 0
  [ -n "$json" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r '.. | objects | select(.global? == true) | select((.id? // "") != "")
      | "\(.id)|\(.description // "")"' 2>/dev/null
  else
    printf '%s' "$json" | tr '\n' ' ' | tr '{' '\n' |
      grep -E '"global"[[:space:]]*:[[:space:]]*true' | while IFS= read -r b; do
        id=$(printf '%s' "$b" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
        desc=$(printf '%s' "$b" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
        [ -n "$id" ] && printf '%s|%s\n' "$id" "$desc"
      done
  fi
}

# NDMS-имя → unix-имя: «show interface <имя> system-name» (RCI, затем ndmc).
# Формат ответа не разбираем: берём первое слово, которое реально есть в /sys/class/net.
rci_system_name() {
  local out tok
  case "$1" in ''|*[!A-Za-z0-9/._-]*) return 1 ;; esac
  out=$(rci_get "show/interface/system-name?name=$1") || out=""
  if [ -z "$out" ] && command -v ndmc >/dev/null 2>&1; then
    out=$(ndmc -c "show interface $1 system-name" 2>/dev/null) || out=""
  fi
  for tok in $(printf '%s' "$out" | tr -c 'A-Za-z0-9_.:-' ' '); do
    if valid_iface_name "$tok" && [ -e "$SYS_NET_DIR/$tok" ]; then
      printf '%s\n' "$tok"
      return 0
    fi
  done
  return 1
}

detect_wan() {
  local d id desc sys
  WAN_RAW=""
  set -f
  for d in $(ip -4 route show default 2>/dev/null | awk '$1 == "default" { for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1) }'); do
    _wan_add "$d" "маршрут по умолчанию" ""
  done
  for d in $(ip -4 route show table all 2>/dev/null | awk '$1 == "default" { for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1) }'); do
    _wan_add "$d" "default в доп. таблице" ""
  done
  set +f
  while IFS='|' read -r id desc; do
    [ -n "$id" ] || continue
    sys=$(rci_system_name "$id") || continue
    desc=$(printf '%s' "$desc" | tr -d '\000-\037|')
    _wan_add "$sys" "RCI $id" "$desc"
  done <<EOF
$(rci_global_ifaces)
EOF
  WAN_LIST=$(printf '%s' "$WAN_RAW" | awk -F'|' '
    $1 == "" { next }
    !($1 in seen) { seen[$1] = ++n; nm[n] = $1; src[n] = $2; ds[n] = $3; next }
    { i = seen[$1]; if (index(src[i], $2) == 0) src[i] = src[i] ", " $2; if (ds[i] == "") ds[i] = $3 }
    END { for (i = 1; i <= n; i++) print nm[i] "|" src[i] "|" ds[i] }')
}

wan_list_has() {
  printf '%s\n' "$WAN_LIST" | cut -d'|' -f1 | grep -qx "$1"
}

is_tunnel_name() {
  case "$1" in
    nwg*|wg*|awg*|opkgtun*|tun*|tap*|ovpn*|ipsec*|sstp*|t2s*|sing*|xray*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Состояние Antiscan
# ---------------------------------------------------------------------------
is_running() { [ -f "$ASCN_RUN_FILE" ]; }

need_installed() {
  if [ -x "$ASCN_INIT" ]; then
    return 0
  fi
  warn "Antiscan не установлен (нет $ASCN_INIT). Установка — пункт 1."
  return 1
}

status_line() {
  local v
  v=$(pkg_version "$ASCN_PKG")
  if [ -n "$v" ]; then
    if is_running; then
      printf '%s\n' "${GREEN}Установлен: antiscan $v · запущен${NC}"
    else
      printf '%s\n' "${YELLOW}Установлен: antiscan $v · не запущен${NC}"
    fi
  elif pkg_broken "$ASCN_PKG"; then
    printf '%s\n' "${RED}antiscan: установка не завершена (opkg status)${NC}"
  else
    printf '%s\n' "${DIM}Не установлен${NC}"
  fi
}

# Предупреждение о риске заблокировать собственный удалённый доступ
warn_remote_session() {
  local ip
  ip=${SSH_CLIENT:-${SSH_CONNECTION:-}}
  ip=${ip%% *}
  [ -n "$ip" ] || return 0
  case "$ip" in
    10.*|192.168.*|127.*|169.254.*|::1|fe80:*|fd*|fc*) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
  esac
  warn "Вы подключены извне с адреса $ip."
  warn "Если он превысит лимиты Antiscan, доступ с него будет заблокирован (по умолчанию на 10 суток)."
  echo "  Добавьте его в исключения: п.5 → «antiscan edit custom_exclude» и USE_CUSTOM_EXCLUDE_LIST=\"1\"."
}

show_status() {
  local v found
  echo
  printf '%s\n' "${BOLD}Статус Antiscan${NC}"
  v=$(pkg_version "$ASCN_PKG")
  if [ -n "$v" ]; then
    info "Пакет opkg: $ASCN_PKG $v"
  elif pkg_broken "$ASCN_PKG"; then
    warn "Пакет opkg: установка не завершена — $(opkg status "$ASCN_PKG" 2>/dev/null | sed -n 's/^Status:[[:space:]]*//p' | head -n 1)"
  else
    warn "Пакет opkg: не установлен"
  fi
  if found=$(feed_find); then
    info "Репозиторий: ${found#* } (${found%% *})"
  else
    warn "Репозиторий Antiscan в opkg не настроен"
  fi
  if [ -x "$ASCN_INIT" ]; then info "Служба: $ASCN_INIT"; else warn "Служба: нет $ASCN_INIT"; fi
  if [ -f "$ASCN_HOOK" ]; then info "Hook netfilter.d: $ASCN_HOOK"; else warn "Hook netfilter.d: нет $ASCN_HOOK"; fi
  if [ -f "$ASCN_CONF" ]; then
    info "ISP_INTERFACES=\"$(conf_get ISP_INTERFACES)\"  PORTS=\"$(conf_get PORTS)\"  PORTS_FORWARDED=\"$(conf_get PORTS_FORWARDED)\""
    is_default_config && warn "ascn.conf со значениями по умолчанию — проверьте интерфейсы и порты (п.4)."
  fi
  if [ -x "$ASCN_INIT" ]; then
    echo
    printf '%s\n' "${DIM}antiscan status (проверка обновлений без интернета может занять до минуты):${NC}"
    "$ASCN_INIT" status
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 1) Установка
# ---------------------------------------------------------------------------
check_entware() {
  if ! command -v opkg >/dev/null 2>&1; then
    error "opkg не найден. Нужен Entware (Keenetic / Netcraze)."
    return 1
  fi
  if [ "$(id -u 2>/dev/null)" != "0" ]; then
    warn "Скрипт запущен не от root — opkg может не иметь прав."
  fi
  return 0
}

do_install() {
  local rc=0 auth v
  echo
  printf '%s\n' "${BOLD}Установка Antiscan${NC}"
  check_entware || return 1

  if pkg_installed "$ASCN_PKG"; then
    v=$(pkg_version "$ASCN_PKG")
    info "Antiscan уже установлен: $v — повторная установка не нужна."
    upgrade_available && warn "В локальном индексе opkg есть более новая версия — пункт 7."
    [ -f "$ASCN_CONF" ] && is_default_config && warn "ascn.conf со значениями по умолчанию — настройка: пункт 4."
    return 0
  fi
  if pkg_broken "$ASCN_PKG"; then
    error "opkg считает установку antiscan незавершённой:"
    opkg status "$ASCN_PKG" 2>/dev/null | sed -n 's/^Status:/  Status:/p'
    echo "  Удалите пакет (пункт 8) и установите заново."
    return 1
  fi
  [ -f "$ASCN_CONF" ] && info "Найден ascn.conf от прежней установки — opkg его сохранит (conffile)."

  check_nf_kmod
  case "$NF_KMOD_STATE" in
    yes) info "Модули ядра Netfilter: есть (${NF_KMOD_SOURCE})" ;;
    no)  print_nf_kmod_help; return 1 ;;
    *)
      warn "Не удалось проверить компонент «Модули ядра подсистемы Netfilter» (RCI недоступен)."
      warn "Без него Antiscan не запустится."
      confirm "Продолжить установку?" n || { info "Отменено."; return 0; }
      ;;
  esac

  auth=$(rci_auth_state)
  if [ "$auth" = "required" ]; then
    warn "RCI требует авторизацию (KeeneticOS 5.2+): во время установки Antiscan попросит токен доступа."
    echo "  Создайте токен в веб-интерфейсе или CLI роутера заранее. Позже: antiscan token set"
  fi

  echo
  warn "После установки пакет сразу запускает Antiscan со значениями по умолчанию:"
  echo "  ISP_INTERFACES=\"$DEF_ISP\"  PORTS=\"$DEF_PORTS\"  PORTS_FORWARDED=\"$DEF_FWD\""
  echo "  Сразу после установки будет предложено проверить интерфейсы и порты."
  echo "  Antiscan работает только для IPv4 и TCP; правила — в таблице filter (INPUT/FORWARD)."
  confirm "Установить Antiscan?" y || { info "Отменено."; return 0; }

  FEED_CREATED=0
  ensure_feed "$FEED_URL_PRIMARY" || return 1
  if ! ensure_https_deps || ! refresh_with_fallback; then
    _install_rollback_feed
    return 1
  fi
  info "В репозитории: antiscan $FEED_VER"

  info "opkg install $ASCN_PKG"
  run_tty opkg install "$ASCN_PKG" || rc=$?

  if ! pkg_installed "$ASCN_PKG"; then
    error "Antiscan не установлен (opkg код $rc)."
    pkg_broken "$ASCN_PKG" && error "Пакет распакован, но не настроен (post-install). Подробности выше."
    return 1
  fi
  if [ ! -x "$ASCN_INIT" ] || [ ! -f "$ASCN_CONF" ]; then
    error "Пакет отмечен установленным, но нет $ASCN_INIT или $ASCN_CONF."
    return 1
  fi
  [ "$rc" -ne 0 ] && warn "opkg вернул код $rc, но пакет установлен (вероятно, ошибка post-install)."
  info "Установлен: antiscan $(pkg_version "$ASCN_PKG")"
  if is_running; then
    info "Antiscan запущен."
  else
    warn "Antiscan не запущен. Частые причины: не введён токен RCI (antiscan token set),"
    warn "нет компонента Netfilter, недоступен RCI. Запуск — пункт 3."
  fi
  post_install_setup
  return 0
}

_install_rollback_feed() {
  if [ "$FEED_CREATED" = "1" ] && [ -f "$ASCN_FEED_CONF" ]; then
    rm -f "$ASCN_FEED_CONF" && info "Откат: удалён созданный $ASCN_FEED_CONF"
  fi
}

post_install_setup() {
  if ! is_default_config; then
    info "ascn.conf содержит пользовательские настройки — оставлен без изменений."
    return 0
  fi
  detect_wan
  if is_running && ! wan_list_has "$DEF_ISP"; then
    warn "Интерфейс по умолчанию «$DEF_ISP» не найден среди WAN-подключений этого роутера."
    if confirm "Остановить Antiscan до завершения настройки?" y; then
      "$ASCN_INIT" stop
      if is_running; then error "Antiscan не остановился."; else info "Antiscan остановлен."; fi
    fi
  fi
  if confirm "Настроить WAN-интерфейсы и порты сейчас?" y; then
    do_configure
  else
    warn "Настройка отложена — пункт 4."
  fi
}

# ---------------------------------------------------------------------------
# 3) Запуск / остановка / перезапуск
# ---------------------------------------------------------------------------
warn_bans_dropped() {
  if [ "$(conf_get SAVE_IPSETS)" = "1" ]; then
    echo "  SAVE_IPSETS=\"1\": накопленные списки сохраняются при перезапуске Antiscan."
  else
    warn "Остановка снимает все блокировки Antiscan (накопленные списки не сохраняются: SAVE_IPSETS=\"0\")."
  fi
}

do_service() {
  need_installed || return 1
  echo
  printf '%s\n' "${BOLD}Служба Antiscan${NC}  $(is_running && echo "${GREEN}запущена${NC}" || echo "${YELLOW}не запущена${NC}")"
  echo "  1) Запустить"
  echo "  2) Остановить"
  echo "  3) Перезапустить"
  echo "  0) Назад"
  printf '%s' "${BOLD}Выбор: ${NC}"
  read_line || return 0
  case "$REPLY_LINE" in
    1)
      if is_running; then info "Antiscan уже запущен."; return 0; fi
      if is_default_config; then
        warn "ascn.conf со значениями по умолчанию (ISP_INTERFACES=\"$DEF_ISP\")."
        confirm "Всё равно запустить?" n || return 0
      fi
      run_tty "$ASCN_INIT" start
      if is_running; then info "Antiscan запущен."; else error "Antiscan не запустился (см. сообщения выше)."; return 1; fi
      ;;
    2)
      if ! is_running; then info "Antiscan не запущен."; return 0; fi
      warn_bans_dropped
      confirm "Остановить Antiscan?" n || return 0
      "$ASCN_INIT" stop
      if is_running; then error "Antiscan не остановился."; return 1; else info "Antiscan остановлен."; fi
      ;;
    3)
      is_running && warn_bans_dropped
      confirm "Перезапустить Antiscan?" y || return 0
      run_tty "$ASCN_INIT" restart
      if is_running; then info "Antiscan перезапущен."; else error "Antiscan не запустился после перезапуска."; return 1; fi
      ;;
    *) return 0 ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# 4) WAN-интерфейсы и порты
# ---------------------------------------------------------------------------
NEW_ISP=""
select_interfaces() {
  local cur="$1" n i line name src desc mark t picked
  detect_wan
  echo
  printf '%s\n' "${BOLD}ISP_INTERFACES${NC} — интерфейсы интернет-подключений (unix-имена)."
  if [ -n "$WAN_LIST" ]; then
    echo "  Найдено (только подсказка, проверьте):"
    n=0
    while IFS='|' read -r name src desc; do
      [ -n "$name" ] || continue
      n=$((n + 1))
      mark=""
      [ -e "$SYS_NET_DIR/$name" ] || mark="${mark} ${RED}[нет в системе]${NC}"
      is_tunnel_name "$name" && mark="${mark} ${YELLOW}[туннель/VPN]${NC}"
      printf '    %d) %-12s %s%s%s\n' "$n" "$name" "${DIM}$src${desc:+ · $desc}${NC}" "$mark" ""
    done <<EOF
$WAN_LIST
EOF
  else
    warn "Интерфейсы интернет-подключений определить не удалось — введите вручную."
  fi
  echo "  Unix-имя в CLI роутера: show interface <имя> system-name (например eth3, ppp0, eth2.2)."
  while :; do
    printf '%s' "  Номера и/или имена через пробел [Enter — «${cur:-нет}», 0 — отмена]: "
    read_line || return 1
    line=$REPLY_LINE
    case "$line" in
      0) return 1 ;;
      "")
        [ -n "$cur" ] || { warn "Текущее значение пустое — укажите интерфейс."; continue; }
        line=$cur
        ;;
    esac
    picked=""
    set -f
    for t in $(printf '%s' "$line" | tr ',' ' '); do
      case "$t" in
        *[!0-9]*) picked="$picked $t" ;;
        *)
          name=$(printf '%s\n' "$WAN_LIST" | awk -F'|' -v k="$t" 'NF && ++i == k { print $1 }')
          if [ -z "$name" ]; then
            set +f; error "Нет пункта с номером $t"; picked="__bad__"; break
          fi
          picked="$picked $name"
          ;;
      esac
    done
    set +f
    [ "$picked" = "__bad__" ] && continue
    parse_ifaces "$picked" || continue
    for i in $IFACES_RESULT; do
      case "$i" in
        br*) warn "$i — обычно мост локальной сети (LAN), не интернет-подключение." ;;
      esac
      if [ ! -e "$SYS_NET_DIR/$i" ]; then
        warn "Интерфейса $i сейчас нет в системе (PPPoE/VPN может появиться позже)."
      fi
      is_tunnel_name "$i" && warn "$i похож на туннель/VPN: Antiscan будет учитывать входящие подключения и через него."
    done
    if printf '%s\n' "$IFACES_RESULT" | grep -Eq '(^| )br'; then
      confirm "Точно использовать «$IFACES_RESULT»?" n || continue
    else
      for i in $IFACES_RESULT; do
        if [ ! -e "$SYS_NET_DIR/$i" ]; then
          confirm "Использовать «$IFACES_RESULT»?" n || continue 2
          break
        fi
      done
    fi
    NEW_ISP=$IFACES_RESULT
    return 0
  done
}

listening_tcp_ports() {
  netstat -lnt 2>/dev/null | awk '$1 ~ /^tcp/ { n = split($4, a, ":"); p = a[n]; if (p ~ /^[0-9]+$/) print p }' |
    sort -n | uniq | tr '\n' ' '
}

# $1 = PORTS | PORTS_FORWARDED, $2 = текущее значение → NEW_PORTS_VALUE
NEW_PORTS_VALUE=""
ask_ports() {
  local key="$1" cur="$2" lp
  echo
  if [ "$key" = "PORTS" ]; then
    printf '%s\n' "${BOLD}PORTS${NC} — TCP-порты служб самого роутера, открытые в интернет (SSH, веб, VPN-сервер…)."
    lp=$(listening_tcp_ports)
    [ -n "$lp" ] && echo "  Слушающие TCP-порты роутера (не все доступны из интернета): $lp"
  else
    printf '%s\n' "${BOLD}PORTS_FORWARDED${NC} — TCP-порты назначения на устройствах LAN для переадресации."
    echo "  Указывайте порт из поля «Направлять на порт», а не внешний «Открыть порт»."
    echo "  Пример: снаружи 8443 → 192.168.1.10:443 — указывать 443."
  fi
  echo "  Формат: 22,80,443 или 8000:8100 (до 15 портов, диапазон = 2)."
  while :; do
    printf '%s' "  $key [Enter — «${cur:-пусто}», - — пусто, 0 — отмена]: "
    read_line || return 1
    case "$REPLY_LINE" in
      0) return 1 ;;
      -) NEW_PORTS_VALUE=""; return 0 ;;
      "") parse_ports "$cur" || continue ;;
      *)  parse_ports "$REPLY_LINE" || continue ;;
    esac
    if [ "$PORTS_EPHEMERAL" = "1" ]; then
      warn "Порты 32768–60999 используются для исходящих соединений: ответы на них тоже попадут под лимиты Antiscan."
      confirm "Оставить «$PORTS_RESULT»?" n || continue
    fi
    NEW_PORTS_VALUE=$PORTS_RESULT
    return 0
  done
}

do_configure() {
  local cur_isp cur_ports cur_fwd new_ports new_fwd rc=0
  need_installed || return 1
  if [ ! -f "$ASCN_CONF" ]; then error "Нет $ASCN_CONF"; return 1; fi
  if ! conf_format_ok "$ASCN_CONF"; then
    error "ascn.conf содержит строки, которые Antiscan не примет (см. выше). Исправьте через пункт 5."
    return 1
  fi
  cur_isp=$(conf_get ISP_INTERFACES)
  cur_ports=$(conf_get PORTS)
  cur_fwd=$(conf_get PORTS_FORWARDED)
  echo
  printf '%s\n' "${BOLD}Настройка Antiscan${NC} (остальные параметры ascn.conf не меняются)"
  echo "  Текущие: ISP_INTERFACES=\"$cur_isp\"  PORTS=\"$cur_ports\"  PORTS_FORWARDED=\"$cur_fwd\""
  echo "  Honeypot, геоблокировка и прочие режимы здесь не включаются."

  select_interfaces "$cur_isp" || { info "Отменено — ascn.conf не изменён."; return 0; }
  ask_ports PORTS "$cur_ports" || { info "Отменено — ascn.conf не изменён."; return 0; }
  new_ports=$NEW_PORTS_VALUE
  ask_ports PORTS_FORWARDED "$cur_fwd" || { info "Отменено — ascn.conf не изменён."; return 0; }
  new_fwd=$NEW_PORTS_VALUE
  if [ -z "$new_ports" ] && [ -z "$new_fwd" ]; then
    error "PORTS и PORTS_FORWARDED не могут быть пустыми одновременно — ascn.conf не изменён."
    return 1
  fi

  echo
  printf '%s\n' "${BOLD}Итог${NC}"
  echo "  ISP_INTERFACES=\"$NEW_ISP\"    (было \"$cur_isp\")"
  echo "  PORTS=\"$new_ports\"    (было \"$cur_ports\")"
  echo "  PORTS_FORWARDED=\"$new_fwd\"    (было \"$cur_fwd\")"
  case ",$new_ports," in *,22,*) warn_remote_session ;; esac
  if [ "$NEW_ISP" = "$cur_isp" ] && [ "$new_ports" = "$cur_ports" ] && [ "$new_fwd" = "$cur_fwd" ]; then
    info "Изменений нет — ascn.conf не тронут."
    return 0
  fi
  confirm "Сохранить в $ASCN_CONF?" n || { info "Отменено — ascn.conf не изменён."; return 0; }

  backup_conf || return 1
  if ! conf_write_values "$NEW_ISP" "$new_ports" "$new_fwd"; then
    error "Не удалось записать ascn.conf. Бэкап: $BACKUP_PATH"
    return 1
  fi
  info "ascn.conf обновлён."

  if is_running; then
    info "Применяем: antiscan reload"
    "$ASCN_INIT" reload || rc=$?
    if [ "$rc" -eq 0 ] && is_running; then
      info "Конфигурация применена."
    else
      error "antiscan reload завершился с ошибкой (код $rc)."
      if confirm "Вернуть прежний ascn.conf из бэкапа?" y; then
        cp -p "$BACKUP_PATH" "$ASCN_CONF" && info "Восстановлено из $BACKUP_PATH. Проверьте службу: пункт 3."
      fi
      return 1
    fi
  else
    if confirm "Antiscan не запущен. Запустить сейчас?" y; then
      run_tty "$ASCN_INIT" start
      if is_running; then info "Antiscan запущен."; else error "Antiscan не запустился (см. сообщения выше)."; return 1; fi
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 5) Редактирование ascn.conf (штатный antiscan edit config)
# ---------------------------------------------------------------------------
do_edit() {
  local ed="" e
  need_installed || return 1
  for e in nano vim vi; do
    [ -f "$OPT_BIN/$e" ] && { ed=$e; break; }
  done
  if [ -z "$ed" ]; then
    warn "antiscan edit использует $OPT_BIN/nano, vim или vi — редактор не найден."
    confirm "Установить nano (opkg install nano)?" n || return 0
    opkg install nano || { error "Не удалось установить nano."; return 1; }
  fi
  backup_conf || return 1
  info "antiscan edit config (после сохранения Antiscan сам проверит файл и применит его)"
  run_tty "$ASCN_INIT" edit config
  if [ -n "$BACKUP_PATH" ] && command -v cmp >/dev/null 2>&1 && cmp -s "$BACKUP_PATH" "$ASCN_CONF"; then
    rm -f "$BACKUP_PATH"
    info "ascn.conf не изменён."
  elif [ -n "$BACKUP_PATH" ]; then
    info "Прежняя версия: $BACKUP_PATH"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 6) Заблокированные адреса (antiscan list)
# ---------------------------------------------------------------------------
do_list() {
  need_installed || return 1
  if ! is_running; then
    warn "Antiscan не запущен — списков блокировки нет."
    return 0
  fi
  echo
  printf '%s\n' "${BOLD}Заблокированные IP${NC}"
  "$ASCN_INIT" list ips
  echo
  printf '%s\n' "${BOLD}Заблокированные подсети${NC}"
  "$ASCN_INIT" list subnets
  if [ "$(conf_get ENABLE_HONEYPOT)" = "1" ]; then
    echo
    printf '%s\n' "${BOLD}Ловушка (honeypot)${NC}"
    "$ASCN_INIT" list honeypot
  fi
  if [ "$(conf_get READ_NDM_LOCKOUT_IPSETS)" = "1" ]; then
    echo
    printf '%s\n' "${BOLD}Списки NDMS (ip lockout-policy)${NC}"
    "$ASCN_INIT" list ndm_lockout
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 7) Обновление
# ---------------------------------------------------------------------------
do_update() {
  local old new was_running=0 rc=0 o_isp o_ports o_fwd crontab_bak="" conf_bak
  echo
  printf '%s\n' "${BOLD}Обновление Antiscan${NC}"
  check_entware || return 1
  if ! pkg_installed "$ASCN_PKG"; then
    warn "Antiscan не установлен через opkg — установка: пункт 1."
    return 1
  fi
  old=$(pkg_version "$ASCN_PKG")
  FEED_CREATED=0
  ensure_feed "$FEED_URL_PRIMARY" || return 1
  if ! refresh_with_fallback; then
    _install_rollback_feed
    return 1
  fi
  if ! upgrade_available; then
    info "Установлена актуальная версия: $old (в репозитории: $FEED_VER)."
    return 0
  fi
  info "Доступно обновление: $old → $FEED_VER"
  confirm "Обновить Antiscan?" y || { info "Отменено."; return 0; }

  is_running && was_running=1
  o_isp=$(conf_get ISP_INTERFACES); o_ports=$(conf_get PORTS); o_fwd=$(conf_get PORTS_FORWARDED)
  backup_conf || return 1
  if [ -f "$ASCN_DIR/ascn_crontab.conf" ]; then
    conf_bak=$BACKUP_PATH
    backup_conf "$ASCN_DIR/ascn_crontab.conf" && crontab_bak=$BACKUP_PATH
    BACKUP_PATH=$conf_bak
  fi

  info "opkg upgrade $ASCN_PKG"
  run_tty opkg upgrade "$ASCN_PKG" || rc=$?
  new=$(pkg_version "$ASCN_PKG")
  if [ -z "$new" ]; then
    error "После обновления пакет не в состоянии installed (opkg код $rc). Бэкап: $BACKUP_PATH"
    return 1
  fi
  if [ "$new" = "$old" ]; then
    error "Версия не изменилась ($old), opkg код $rc."
    return 1
  fi
  [ "$rc" -ne 0 ] && warn "opkg вернул код $rc, но версия обновлена."
  info "Обновлено: $old → $new"

  if [ "$(conf_get ISP_INTERFACES)" != "$o_isp" ] || [ "$(conf_get PORTS)" != "$o_ports" ] ||
     [ "$(conf_get PORTS_FORWARDED)" != "$o_fwd" ]; then
    warn "Параметры ascn.conf изменились при обновлении. Прежняя версия: $BACKUP_PATH"
  else
    info "Настройки сохранены (бэкап: $BACKUP_PATH${crontab_bak:+, $crontab_bak})."
  fi
  [ -f "${ASCN_CONF}-opkg" ] && warn "opkg положил новую версию конфига рядом: ${ASCN_CONF}-opkg"

  if is_running; then
    info "Antiscan запущен."
  elif [ "$was_running" = "1" ]; then
    warn "Antiscan был запущен до обновления, сейчас — нет."
    if confirm "Запустить?" y; then
      run_tty "$ASCN_INIT" start
      if is_running; then info "Antiscan запущен."; else error "Antiscan не запустился."; fi
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 8) Удаление
# ---------------------------------------------------------------------------
do_remove() {
  local keep=1 bdir="" f rc=0 left="" ok=1 ipsets_dir
  ipsets_dir=$(conf_get IPSETS_DIRECTORY)
  echo
  printf '%s\n' "${BOLD}Удаление Antiscan${NC}"
  if ! pkg_installed "$ASCN_PKG" && ! pkg_broken "$ASCN_PKG"; then
    warn "Пакет antiscan не установлен в opkg."
    [ -d "$ASCN_DIR" ] && echo "  Остались настройки: $ASCN_DIR (не трогаем)."
    return 0
  fi
  echo "  opkg remove antiscan: служба останавливается штатно (prerm), задачи cron удаляются (postrm)."
  echo "  Зависимости (ipset, iptables, curl, jq, cron) и другие пакеты не удаляются."
  confirm "Удалить Antiscan?" n || { info "Отменено."; return 0; }
  if [ -d "$ASCN_DIR" ]; then
    confirm "Сохранить настройки (ascn.conf, crontab, списки, токен)?" y || keep=0
  fi

  if [ "$keep" = "1" ] && [ -d "$ASCN_DIR" ]; then
    bdir="$ASCN_BACKUP_BASE/antiscan-backup-$(date +%Y%m%d%H%M%S)"
    if ! mkdir -p "$bdir"; then error "Не удалось создать $bdir — удаление отменено."; return 1; fi
    for f in $ASCN_USER_FILES; do
      [ -f "$ASCN_DIR/$f" ] || continue
      cp -p "$ASCN_DIR/$f" "$bdir/" || { error "Не удалось скопировать $f — удаление отменено."; return 1; }
    done
    info "Копия настроек: $bdir"
  fi

  if is_running && [ -x "$ASCN_INIT" ]; then
    info "Остановка: antiscan stop"
    "$ASCN_INIT" stop
  fi

  info "opkg remove $ASCN_PKG"
  opkg remove "$ASCN_PKG" || rc=$?
  if pkg_installed "$ASCN_PKG"; then
    error "opkg remove не удалил пакет (код $rc). Настройки не тронуты."
    return 1
  fi
  [ "$rc" -ne 0 ] && warn "opkg вернул код $rc."

  # Проверка фактического состояния (только чтение)
  [ -e "$ASCN_INIT" ] && { warn "Остался $ASCN_INIT"; ok=0; }
  [ -e "$ASCN_HOOK" ] && { warn "Остался hook $ASCN_HOOK"; ok=0; }
  [ -e "$ASCN_RUN_FILE" ] && { warn "Остался флаг работы $ASCN_RUN_FILE"; ok=0; }
  if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q 'S99ascn'; then
    warn "В crontab остались задачи S99ascn."; ok=0
  fi
  if command -v iptables >/dev/null 2>&1 && iptables -w -t filter -L ANTISCAN -n >/dev/null 2>&1; then
    warn "В iptables осталась цепочка ANTISCAN (служба не была остановлена штатно)."
    warn "Перезагрузка роутера уберёт её; nfqws-menu чужие цепочки не трогает."
    ok=0
  fi

  if [ "$keep" = "0" ]; then
    for f in $ASCN_USER_FILES ascn.conf-opkg ascn_crontab.conf-opkg; do
      [ -f "$ASCN_DIR/$f" ] && rm -f "$ASCN_DIR/$f"
    done
    for f in "$ASCN_DIR"/ascn.conf.bak.* "$ASCN_DIR"/ascn_crontab.conf.bak.*; do
      [ -f "$f" ] && rm -f "$f"
    done
    rmdir "$ASCN_DIR/scripts" 2>/dev/null || true
    if [ -d "$ASCN_DIR" ] && ! rmdir "$ASCN_DIR" 2>/dev/null; then
      left=$(find "$ASCN_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')
      warn "В $ASCN_DIR остались посторонние файлы (не удалены): $left"
    fi
    [ -d "$ASCN_DIR" ] || info "Настройки удалены: $ASCN_DIR"
  fi
  [ -n "$ipsets_dir" ] && echo "  Каталог списков IPSETS_DIRECTORY=\"$ipsets_dir\" не трогаем — удалите вручную при необходимости."

  if feed_is_official_file "$ASCN_FEED_CONF"; then
    if confirm "Удалить репозиторий Antiscan из opkg ($ASCN_FEED_CONF)?" n; then
      rm -f "$ASCN_FEED_CONF" && info "Удалён $ASCN_FEED_CONF"
    fi
  fi

  if [ "$ok" = "1" ]; then
    info "Antiscan удалён."
  else
    warn "Antiscan удалён из opkg, но есть остатки (см. выше)."
  fi
  [ -n "$bdir" ] && info "Настройки сохранены в $bdir (и/или оставлены opkg в $ASCN_DIR)."
  return 0
}

# ---------------------------------------------------------------------------
# Меню
# ---------------------------------------------------------------------------
main_menu() {
  while :; do
    if [ "${ASCN_NO_TTY:-0}" != "1" ]; then clear 2>/dev/null || true; fi
    printf '%s\n' "${CYAN}================================================${NC}"
    printf '%s\n' "${CYAN}${BOLD}                   Antiscan${NC}"
    printf '%s\n' "${CYAN}================================================${NC}"
    echo
    printf '%s\n' "${DIM}Блокировка IP, сканирующих порты и подбирающих пароли (IPv4, TCP).${NC}"
    printf '%s\n' "${DIM}github.com/dimon27254/antiscan · opkg: dimon27254.github.io/antiscan${NC}"
    echo
    status_line
    echo
    echo "  1) Установить Antiscan"
    echo "  2) Статус и версия"
    echo "  3) Запуск / остановка / перезапуск"
    echo "  4) Настроить WAN-интерфейсы и TCP-порты"
    echo "  5) Открыть конфигурацию (antiscan edit config)"
    echo "  6) Заблокированные IP и подсети"
    echo "  7) Обновить Antiscan"
    echo "  8) Удалить Antiscan"
    echo "  9) Назад"
    echo
    printf '%s' "${BOLD}Выбор: ${NC}"
    read_line || exit 0
    echo
    case "$REPLY_LINE" in
      1) do_install ;;
      2) show_status ;;
      3) do_service ;;
      4) do_configure ;;
      5) do_edit ;;
      6) do_list ;;
      7) do_update ;;
      8) do_remove ;;
      9|0|"") exit 0 ;;
      *) warn "Неверный пункт" ;;
    esac
    pause
  done
}

# ASCN_INSTALLER_LIB=1 — только загрузить функции (tests/antiscan-installer.sh)
[ "${ASCN_INSTALLER_LIB:-0}" = "1" ] || main_menu
