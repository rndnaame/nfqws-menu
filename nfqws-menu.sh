#!/bin/sh
# nfqws-menu.sh — интерактивное меню установки/управления
# nfqws-keenetic / nfqws2-keenetic / nfqws-keenetic-web для Entware (Keenetic / Netcraze)
# Репозиторий стратегий: https://github.com/rndnaame/nfqws-menu
#
# Версионирование (MAJOR.MINOR.PATCH):
#   PATCH (+0.0.1) — небольшие правки
#   MINOR (+0.1.0) — средние изменения
#   MAJOR (+1.0.0) — критические изменения

set -e

SCRIPT_VERSION="0.6.15"

REPO_URL="https://github.com/rndnaame/nfqws-menu"
RAW_BASE="https://raw.githubusercontent.com/rndnaame/nfqws-menu/main"
STRATEGIES_API="https://api.github.com/repos/rndnaame/nfqws-menu/contents/strategies"

# Не трогаем LD_LIBRARY_PATH: глобальный export /opt ломает ndmc (OpenSSL),
# а system-only ломает Entware wget. Без export окружение как в обычной SSH.

# ---------------------------------------------------------------------------
# Цвета
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  ESC=$(printf '\033')
  RED="${ESC}[0;31m"
  GREEN="${ESC}[0;32m"
  YELLOW="${ESC}[1;33m"
  BLUE="${ESC}[0;34m"
  CYAN="${ESC}[0;36m"
  MAGENTA="${ESC}[0;35m"
  DIM="${ESC}[2m"
  NC="${ESC}[0m"
  BOLD="${ESC}[1m"
else
  RED= GREEN= YELLOW= BLUE= CYAN= MAGENTA= DIM= NC= BOLD=
fi

# ---------------------------------------------------------------------------
# Язык UI  (/opt/etc/nfqws-menu.lang, env NFQWS_MENU_LANG / NFQWS_MENU_UTF8)
# Авто: SSH → ru, иначе en
# ---------------------------------------------------------------------------
UI_LANG_FILE="/opt/etc/nfqws-menu.lang"

ui_detect_default_lang() {
  case "${NFQWS_MENU_LANG:-}" in
    ru|RU|utf8|UTF8) echo "ru"; return ;;
    en|EN|ascii|ASCII) echo "en"; return ;;
  esac
  case "${NFQWS_MENU_UTF8:-}" in
    1|yes|true|on|ON)  echo "ru"; return ;;
    0|no|false|off|OFF) echo "en"; return ;;
  esac
  if [ -f "$UI_LANG_FILE" ]; then
    case "$(cat "$UI_LANG_FILE" 2>/dev/null | tr -d ' \r\n')" in
      ru|RU) echo "ru"; return ;;
      en|EN) echo "en"; return ;;
    esac
  fi
  if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; then
    echo "ru"; return
  fi
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) echo "ru"; return ;;
  esac
  echo "en"
}

ui_apply_lang() {
  UI_LANG="$1"
  case "$UI_LANG" in
    ru)
      UI_UTF8=1
      RUN_MARK=" ⚡"
      LBL_ARCH="Архитектура"
      LBL_INSTALLED="Установленные компоненты:"
      LBL_NONE="— ничего не установлено —"
      LBL_COMPONENTS="КОМПОНЕНТЫ"
      LBL_STRATEGIES="СТРАТЕГИИ/СПИСКИ"
      LBL_UTILS="УТИЛИТЫ"
      LBL_REMOVE="СЕРВИС"
      LBL_1="Установить NFQWS/NFQWS2"
      LBL_2="Установить веб-интерфейс"
      LBL_3="Выбор стратегии"
      LBL_4="Обновить IPSet List"
      LBL_5="Обход блокировки DoT/DoH"
      LBL_6="Управление DoT/DoH"
      LBL_7="Загрузить rkn.list (125k+ доменов)"
      LBL_7F="Смена активных fake:blob"
      LBL_77="Change language"
      LBL_88="Удаление пакетов"
      LBL_99="Обновить скрипт"
      LBL_00="Выход"
      LBL_PROMPT="Выберите пункт [Enter = выход]: "
      LBL_BACK="Нажмите Enter для возврата в меню..."
      LBL_LANG_TITLE="Язык интерфейса"
      LBL_LANG_CUR="Текущий"
      LBL_LANG_SAVED="Язык сохранён"
      ;;
    *)
      UI_LANG="en"
      UI_UTF8=0
      RUN_MARK=" *"
      LBL_ARCH="Arch"
      LBL_INSTALLED="Installed:"
      LBL_NONE="-- none --"
      LBL_COMPONENTS="COMPONENTS"
      LBL_STRATEGIES="STRATEGIES/LISTS"
      LBL_UTILS="UTILS"
      LBL_REMOVE="SERVICE"
      LBL_1="Install NFQWS/NFQWS2"
      LBL_2="Install web UI"
      LBL_3="Select strategy"
      LBL_4="Update IPSet List"
      LBL_5="Bypass DoT/DoH blocks"
      LBL_6="Manage DoT/DoH"
      LBL_7="Download rkn.list (125k+ domains)"
      LBL_7F="Change active fake:blob"
      LBL_77="Change language"
      LBL_88="Remove packages"
      LBL_99="Update this script"
      LBL_00="Exit"
      LBL_PROMPT="Select item [Enter = exit]: "
      LBL_BACK="Press Enter to return to menu..."
      LBL_LANG_TITLE="Interface language"
      LBL_LANG_CUR="Current"
      LBL_LANG_SAVED="Language saved"
      ;;
  esac
}

ui_apply_lang "$(ui_detect_default_lang)"

menu_change_language() {
  if [ "$UI_LANG" = "ru" ]; then
    ui_apply_lang "en"
  else
    ui_apply_lang "ru"
  fi
  mkdir -p /opt/etc 2>/dev/null || true
  echo "$UI_LANG" > "$UI_LANG_FILE" 2>/dev/null || true
}

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[x]${NC} $*"; }
ask()   { printf '%s' "${CYAN}[?]${NC} $*"; }

# ---------------------------------------------------------------------------
# Общие хелперы
# ---------------------------------------------------------------------------

# confirm_yes: Y/n — да по умолчанию. confirm_no: y/N — нет по умолчанию.
confirm_yes() {
  ask "${1:-Continue?} [Y/n]: "
  read -r ans
  case "$ans" in n|N|н|Н) return 1 ;; esac
  return 0
}

confirm_no() {
  ask "${1:-Continue?} [y/N]: "
  read -r ans
  case "$ans" in y|Y|д|Д) return 0 ;; esac
  return 1
}

# Скачать URL в stdout (curl предпочтительнее)
fetch_url() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$1"
  else
    return 1
  fi
}

# Скачать URL в файл
download_file() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$url" -o "$dest"
  else
    wget -qO "$dest" --no-cache "$url" 2>/dev/null || wget -qO "$dest" "$url"
  fi
}

# curl|wget | sh для удалённых install.sh
run_remote_sh() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url" | sh
  else
    error "Нужны curl или wget."
    return 1
  fi
}

# Записать opkg-репозиторий и обновить индекс
ensure_opkg_repo() {
  local name="$1" url="$2"
  mkdir -p /opt/etc/opkg
  echo "src/gz $name $url" > "/opt/etc/opkg/${name}.conf"
  opkg update
}

# Установка/обновление opkg-пакета (если установлен — upgrade)
opkg_install_or_upgrade() {
  local pkg="$1"
  if is_installed "$pkg"; then
    info "Пакет $pkg уже установлен — обновление..."
    opkg update
    opkg upgrade "$pkg"
    info "Обновление завершено."
  else
    info "Установка $pkg..."
    opkg update
    opkg install "$pkg"
    info "Установка завершена."
  fi
}

# Перезапуск init-скрипта, если есть
service_restart() {
  local init="$1"
  [ -x "$init" ] && "$init" restart 2>/dev/null || true
}

# Бэкап файла с меткой времени
backup_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  info "Бэкап: ${f}.bak.*"
}

# ---------------------------------------------------------------------------
# Архитектура (кэш)
# ---------------------------------------------------------------------------
ARCH=""
ARCH_RAW=""

detect_arch() {
  if [ -n "$ARCH" ]; then
    info "$LBL_ARCH: $ARCH ($ARCH_RAW)"
    return 0
  fi
  ARCH_RAW=$(opkg print-architecture 2>/dev/null | sort -k3 -nr | awk '$2!="all"{print $2;exit}')
  case "$ARCH_RAW" in
    aarch64*|arm*) ARCH="aarch64" ;;
    mipsel*)       ARCH="mipsel"  ;;
    mips*)         ARCH="mips"    ;;
    x86_64*|amd64) ARCH="x86_64"  ;;
    x86*)          ARCH="x86"     ;;
    *)
      error "Unknown arch: $ARCH_RAW"
      exit 1
      ;;
  esac
  info "$LBL_ARCH: $ARCH ($ARCH_RAW)"
}

# ---------------------------------------------------------------------------
# Кэш opkg / процессов
# ---------------------------------------------------------------------------
OPKG_INSTALLED_CACHE=""
PROC_CACHE=""
PORT90_CACHE=""

refresh_opkg_cache() {
  OPKG_INSTALLED_CACHE=$(opkg list-installed 2>/dev/null)
}

refresh_proc_cache() {
  PROC_CACHE=$(ps w 2>/dev/null || ps 2>/dev/null || true)
}

is_installed() {
  [ -n "$OPKG_INSTALLED_CACHE" ] || refresh_opkg_cache
  printf '%s\n' "$OPKG_INSTALLED_CACHE" | grep -q "^$1 "
}

pkg_version() {
  [ -n "$OPKG_INSTALLED_CACHE" ] || refresh_opkg_cache
  printf '%s\n' "$OPKG_INSTALLED_CACHE" | grep "^$1 - " | head -1 | sed "s/^$1 - //"
}

port_is_open() {
  local port="$1" ok=1
  if [ "$port" = "90" ] && [ -n "$PORT90_CACHE" ]; then
    [ "$PORT90_CACHE" = "1" ]
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]" && ok=0
  elif command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]" && ok=0
  elif [ -r /proc/net/tcp ]; then
    grep -q ":$(printf '%04X' "$port") " /proc/net/tcp 2>/dev/null && ok=0
  fi
  if [ "$port" = "90" ]; then
    if [ "$ok" -eq 0 ]; then PORT90_CACHE=1; else PORT90_CACHE=0; fi
  fi
  return "$ok"
}

proc_running() {
  local name="$1"
  [ -n "$PROC_CACHE" ] || refresh_proc_cache
  printf '%s\n' "$PROC_CACHE" | grep -q "$name"
}

# kind: nfqws|nfqws2|web|usque|tg-ws-proxy → 1 если «запущен»
service_is_up() {
  case "$1" in
    nfqws|nfqws2|usque|tg-ws-proxy|magitrickle) proc_running "$1" ;;
    web)
      port_is_open 90 || proc_running lighttpd
      ;;
    *) return 1 ;;
  esac
}

print_pkg_info() {
  local name="$1" kind="$2" ver mark=""
  is_installed "$name" || return 1
  ver=$(pkg_version "$name")
  [ -z "$ver" ] && ver="?"
  service_is_up "$kind" && mark="$RUN_MARK"
  printf '  %s%-22s%s %s%s\n' "$GREEN" "$name" "$NC" "$ver" "$mark"
  return 0
}

print_tool_info() {
  printf '  %s%-22s%s %s\n' "$GREEN" "$1" "$NC" "$2"
}

show_installed() {
  local shown=0
  PORT90_CACHE=""
  refresh_opkg_cache
  refresh_proc_cache

  echo
  printf '%s\n' "${BOLD}${LBL_INSTALLED}${NC}"

  print_pkg_info "nfqws-keenetic"     "nfqws"       && shown=1
  print_pkg_info "nfqws2-keenetic"    "nfqws2"      && shown=1
  print_pkg_info "nfqws-keenetic-web" "web"         && shown=1
  print_pkg_info "usque-keenetic"     "usque"       && shown=1
  print_pkg_info "tg-ws-proxy"        "tg-ws-proxy" && shown=1
  print_pkg_info "magitrickle"        "magitrickle" && shown=1

  if [ -x /opt/bin/dpi-detector ] || command -v dpi-detector >/dev/null 2>&1; then
    local dpi_bin dpi_ver=""
    if [ -x /opt/bin/dpi-detector ]; then
      dpi_bin="/opt/bin/dpi-detector"
    else
      dpi_bin=$(command -v dpi-detector)
    fi
    dpi_ver=$("$dpi_bin" --version 2>/dev/null | head -1 | sed -n 's/.*dpi-detector[[:space:]]\+\([^[:space:]]*\).*/\1/p')
    print_tool_info "dpi-detector" "${dpi_ver:-ok}"
    shown=1
  fi

  if is_installed "awg-manager" || [ -d /opt/etc/awg-manager ]; then
    local awg_name="awg-manager" awg_info="ok"
    if [ -x /opt/etc/awg-manager/singbox/sing-box ] || [ -f /opt/etc/awg-manager/singbox/sing-box ]; then
      awg_name="awg-manager [+SB]"
    fi
    if is_installed "awg-manager"; then
      awg_info=$(pkg_version awg-manager)
      [ -z "$awg_info" ] && awg_info="ok"
    fi
    print_tool_info "$awg_name" "$awg_info"
    shown=1
  fi

  if [ -f /opt/keenkit.sh ]; then
    local kk_ver
    kk_ver=$(grep -E '^SCRIPT_VERSION=' /opt/keenkit.sh 2>/dev/null | head -1 | \
      sed -n 's/^SCRIPT_VERSION=["'\'']\([^"'\'']*\)["'\''].*/\1/p')
    print_tool_info "KeenKit" "${kk_ver:-ok}"
    shown=1
  fi

  # Прочие S* init-скрипты (не дублируем уже показанные)
  if [ -d /opt/etc/init.d ]; then
    local f base svc ver
    for f in /opt/etc/init.d/S[0-9][0-9]*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      base=$(basename "$f")
      svc=$(echo "$base" | sed 's/^S[0-9][0-9]//')
      [ -n "$svc" ] || continue
      case "$svc" in
        nfqws|nfqws2|lighttpd|usque|tg-ws-proxy|magitrickle) continue ;;
        awg-manager)
          is_installed "awg-manager" || [ -d /opt/etc/awg-manager ] && continue
          ;;
      esac
      ver=$(pkg_version "$svc")
      if proc_running "$svc"; then
        printf '  %s%-22s%s %s%s\n' "$GREEN" "$svc" "$NC" "${ver:-}" "$RUN_MARK"
      else
        printf '  %s%-22s%s %s\n' "$GREEN" "$svc" "$NC" "${ver:-}"
      fi
      shown=1
    done
  fi

  if [ "$shown" -eq 0 ]; then
    printf '  %s%s%s\n' "$DIM" "$LBL_NONE" "$NC"
  fi
  echo
}

# ---------------------------------------------------------------------------
# Выбор версии NFQWS (1 / 2 / both) — общий для strategy и ipset
# ---------------------------------------------------------------------------
# $1 = allow_both (1|0). Результат в переменную NFQWS_VER.
need_nfqws_installed() {
  local has1=0 has2=0
  is_installed "nfqws-keenetic"  && has1=1
  is_installed "nfqws2-keenetic" && has2=1
  if [ "$has1" -eq 0 ] && [ "$has2" -eq 0 ]; then
    warn "Ни одна версия NFQWS не установлена."
    if confirm_yes "Перейти к установке?"; then
      menu_install_nfqws
    fi
    return 1
  fi
  HAS_NFQWS1=$has1
  HAS_NFQWS2=$has2
  return 0
}

pick_nfqws_ver() {
  # $1 = allow_both (1|0). Ставит NFQWS_VER = 1|2|both
  local allow_both="${1:-0}"
  if [ "$HAS_NFQWS1" -eq 1 ] && [ "$HAS_NFQWS2" -eq 1 ]; then
    echo
    echo "Установлены обе версии."
    echo "  1) nfqws-keenetic  (v1)"
    echo "  2) nfqws2-keenetic (v2)"
    [ "$allow_both" = "1" ] && echo "  a) Обе"
    ask "Выбор [1/2$([ "$allow_both" = "1" ] && echo '/a')]: "
    read -r c
    case "$c" in
      1) NFQWS_VER=1 ;;
      2) NFQWS_VER=2 ;;
      a|A|а|А)
        [ "$allow_both" = "1" ] || return 1
        NFQWS_VER=both
        ;;
      *) return 1 ;;
    esac
  elif [ "$HAS_NFQWS1" -eq 1 ]; then
    NFQWS_VER=1
  else
    NFQWS_VER=2
  fi
  return 0
}

nfqws_conf_path() {
  case "$1" in
    1) echo "/opt/etc/nfqws/nfqws.conf" ;;
    2) echo "/opt/etc/nfqws2/nfqws2.conf" ;;
  esac
}

nfqws_init_path() {
  case "$1" in
    1) echo "/opt/etc/init.d/S51nfqws" ;;
    2) echo "/opt/etc/init.d/S51nfqws2" ;;
  esac
}

nfqws_lists_dir() {
  case "$1" in
    1) echo "/opt/etc/nfqws" ;;
    2) echo "/opt/etc/nfqws2/lists" ;;
  esac
}

# ---------------------------------------------------------------------------
# 1–2. Установка пакетов
# ---------------------------------------------------------------------------
install_deps() {
  info "Установка зависимостей..."
  opkg update
  opkg install ca-certificates wget-ssl 2>/dev/null || true
  opkg remove wget-nossl 2>/dev/null || true
}

ask_web_install() {
  echo
  if confirm_no "Установить веб-интерфейс nfqws-keenetic-web?"; then
    install_web
  fi
}

install_nfqws1() {
  info "Установка nfqws-keenetic (версия 1)..."
  install_deps
  ensure_opkg_repo "nfqws-keenetic" "https://nfqws.github.io/nfqws-keenetic/$ARCH"
  opkg install nfqws-keenetic
  info "nfqws-keenetic установлен."
  ask_web_install
}

install_nfqws2() {
  info "Установка nfqws2-keenetic (версия 2)..."
  if is_installed "nfqws-keenetic"; then
    warn "Обнаружен nfqws-keenetic. Рекомендуется удалить его перед установкой nfqws2."
    if confirm_no "Удалить nfqws-keenetic и веб-интерфейс?"; then
      opkg remove --autoremove nfqws-keenetic-web nfqws-keenetic 2>/dev/null || true
    fi
  fi
  install_deps
  ensure_opkg_repo "nfqws2-keenetic" "https://nfqws.github.io/nfqws2-keenetic/$ARCH"
  opkg install nfqws2-keenetic
  info "nfqws2-keenetic установлен."
  ask_web_install
}

menu_install_nfqws() {
  echo
  printf '%s\n' "${BOLD}Выберите версию для установки:${NC}"
  echo "  1) nfqws-keenetic  (версия 1)"
  echo "  2) nfqws2-keenetic (версия 2)"
  echo "  0) Назад"
  ask "Ваш выбор [1/2/0]: "
  read -r choice
  case "$choice" in
    1) install_nfqws1 ;;
    2) install_nfqws2 ;;
    0|"") return ;;
    *) warn "Неверный выбор" ;;
  esac
}

install_web() {
  info "Установка nfqws-keenetic-web..."
  install_deps
  ensure_opkg_repo "nfqws-keenetic-web" "https://nfqws.github.io/nfqws-keenetic-web/all"
  opkg install nfqws-keenetic-web
  info "Веб-интерфейс установлен."
  info "Адрес: http://<IP-роутера>:90"
  info "Логин/пароль — учётные данные Entware (по умолчанию root / keenetic)"
}

# ---------------------------------------------------------------------------
# 3. Стратегии
# ---------------------------------------------------------------------------
list_strategies() {
  # Как в 0.5.16: curl/wget | grep в каждой ветке (на busybox ash так надёжнее).
  local ver="$1"
  local url="${STRATEGIES_API}/${ver}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" 2>/dev/null | grep -o '"name": *"[^"]*\.conf"' | sed 's/.*"\([^"]*\)".*/\1/'
  else
    wget -qO- "$url" 2>/dev/null | grep -o '"name": *"[^"]*\.conf"' | sed 's/.*"\([^"]*\)".*/\1/'
  fi
}

detect_isp_interface() {
  local iface=""
  if command -v ip >/dev/null 2>&1; then
    iface=$(ip route 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  fi
  if [ -z "$iface" ]; then
    iface=$(route -n 2>/dev/null | awk '/^0\.0\.0\.0/ {print $8; exit}')
  fi
  if [ -z "$iface" ]; then
    iface=$(route 2>/dev/null | awk '/^default/ {print $NF; exit}')
  fi
  echo "$iface"
}

fix_isp_interface() {
  local conf="$1" detected current
  detected=$(detect_isp_interface)
  if [ -z "$detected" ]; then
    warn "Не удалось определить интерфейс провайдера (route/ip route)."
    return 1
  fi
  current=$(grep -E '^ISP_INTERFACE=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
  info "Интерфейс провайдера (default route): $detected"
  [ -n "$current" ] && info "В конфиге сейчас: ISP_INTERFACE=\"$current\""
  if [ "$current" = "$detected" ]; then
    info "ISP_INTERFACE уже совпадает с интерфейсом провайдера."
    return 0
  fi
  if ! confirm_yes "Установить ISP_INTERFACE=\"$detected\"?"; then
    warn "ISP_INTERFACE не изменён."
    return 0
  fi
  if grep -qE '^ISP_INTERFACE=' "$conf" 2>/dev/null; then
    sed -i "s|^ISP_INTERFACE=.*|ISP_INTERFACE=\"$detected\"|" "$conf"
  else
    printf 'ISP_INTERFACE="%s"\n' "$detected" | cat - "$conf" > "${conf}.new" && mv "${conf}.new" "$conf"
  fi
  info "ISP_INTERFACE=\"$detected\" записан в $conf"
}

extract_blob_paths() {
  grep -vE '^[[:space:]]*#' "$1" 2>/dev/null | tr ' \t' '\n' | \
    sed -n -e 's/.*@\(\/[^[:space:]"]*\.bin\).*/\1/p' \
           -e 's/.*=\(\/[^[:space:]"]*\.bin\).*/\1/p' | sort -u
}

extract_list_paths() {
  grep -vE '^[[:space:]]*#' "$1" 2>/dev/null | tr ' \t' '\n' | \
    sed -n -e 's/.*[=:]\(\/[^[:space:]"]*\.list\).*/\1/p' \
           -e 's/^\(\/[^[:space:]"]*\.list\)$/\1/p' | sort -u
}

# Универсальная проверка отсутствующих файлов из конфига
# $1=label $2=conf $3=extractor_func $4=repo_subdir $5=ask_msg
check_conf_files() {
  local label="$1" conf="$2" extractor="$3" repo_sub="$4" ask_msg="$5"
  local paths path name missing=0 missing_list=""

  if [ ! -f "$conf" ]; then
    warn "Конфиг $conf не найден — проверка $label пропущена."
    return 1
  fi

  paths=$($extractor "$conf")
  if [ -z "$paths" ]; then
    info "В конфиге нет ссылок на $label — проверка не требуется."
    return 0
  fi

  info "$label, указанные в конфиге:"
  for path in $paths; do
    if [ -f "$path" ]; then
      info "  OK  $path"
    else
      warn "  нет $path"
      missing=1
      missing_list="$missing_list $path"
    fi
  done

  [ "$missing" -eq 0 ] && { info "Все используемые $label на месте."; return 0; }

  warn "Часть $label отсутствует."
  confirm_yes "$ask_msg" || return 0

  for path in $missing_list; do
    name=$(basename "$path")
    mkdir -p "$(dirname "$path")"
    if [ "$repo_sub" = "lists" ] && [ "$name" = "auto.list" ]; then
      touch "$path"
      info "  создан пустой $path (заполняется демоном)"
      continue
    fi
    info "Скачивание $name → $path"
    if download_file "${RAW_BASE}/strategies/${repo_sub}/${name}" "$path"; then
      info "  готово"
    elif [ "$repo_sub" = "lists" ]; then
      touch "$path"
      warn "  нет в репозитории — создан пустой $path"
    else
      warn "  не удалось скачать $name (нет в репозитории?)"
    fi
  done
}

check_blobs() { check_conf_files "blobs" "$2" extract_blob_paths "blobs" "Скачать отсутствующие blobs из strategies/blobs/?"; }
check_lists() { check_conf_files "lists" "$2" extract_list_paths "lists" "Скачать/создать отсутствующие lists?"; }

update_lists() {
  local ver="$1" dest_dir name
  dest_dir=$(nfqws_lists_dir "$ver")
  mkdir -p "$dest_dir"
  for name in user.list exclude.list ipset.list ipset_exclude.list; do
    info "Обновление $name ..."
    if download_file "${RAW_BASE}/strategies/lists/${name}" "${dest_dir}/${name}"; then
      info "  → ${dest_dir}/${name}"
    else
      warn "  не удалось скачать $name (пропуск)"
    fi
  done
  info "Списки обновлены (auto.list не изменялся)."
}

apply_strategy() {
  local ver="$1" conf_name="$2" conf_path conf_dest tmp
  conf_dest=$(nfqws_conf_path "$ver")

  if [ "$conf_name" = "default" ]; then
    if [ "$ver" = "1" ]; then
      conf_path="https://raw.githubusercontent.com/nfqws/nfqws-keenetic/master/etc/nfqws/nfqws.conf"
    else
      conf_path="https://raw.githubusercontent.com/nfqws/nfqws2-keenetic/master/etc/nfqws2/nfqws2.conf"
    fi
  else
    conf_path="${RAW_BASE}/strategies/nfqws${ver}/${conf_name}"
  fi

  if [ ! -f "$conf_dest" ]; then
    error "Конфиг $conf_dest не найден. Сначала установите соответствующий пакет."
    return 1
  fi

  info "Скачивание стратегии: $conf_name"
  info "URL: $conf_path"
  tmp="/tmp/nfqws-strategy-$$.conf"
  if ! download_file "$conf_path" "$tmp"; then
    error "Не удалось скачать $conf_path"
    return 1
  fi

  backup_file "$conf_dest"

  if grep -qE '^(ISP_INTERFACE|NFQWS_ARGS|NFQWS_BASE_ARGS)=' "$tmp" 2>/dev/null; then
    cp "$tmp" "$conf_dest"
    info "Конфиг полностью заменён стратегией $conf_name"
  else
    warn "Файл стратегии не выглядит как полный конфиг — попробуйте вручную."
    cat "$tmp"
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"

  echo
  info "=== Проверка ISP_INTERFACE ==="
  fix_isp_interface "$conf_dest"

  echo
  info "=== Проверка blobs ==="
  check_blobs "$ver" "$conf_dest"

  echo
  info "=== Проверка lists ==="
  check_lists "$ver" "$conf_dest"

  echo
  if confirm_no "Принудительно обновить все lists (user/exclude/ipset) из репозитория?"; then
    update_lists "$ver"
  else
    info "Принудительное обновление lists пропущено."
  fi

  echo
  service_restart "$(nfqws_init_path "$ver")"
  info "Сервис перезапущен."
}

detect_current_strategy() {
  local conf="$1"
  [ -f "$conf" ] || return 0
  grep -iE 'general[[:space:]]*\(' "$conf" 2>/dev/null | \
    sed -n 's/.*(\([^)]*\)).*/\1/p' | head -1 | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

menu_strategy() {
  need_nfqws_installed || return
  pick_nfqws_ver 0 || return

  local conf_dest current_id dir list i files f base num idx selected
  conf_dest=$(nfqws_conf_path "$NFQWS_VER")
  current_id=$(detect_current_strategy "$conf_dest")
  [ -n "$current_id" ] && info "Текущая стратегия в конфиге: $current_id"

  dir="nfqws${NFQWS_VER}"
  echo
  info "Доступные стратегии ($dir):"
  list=$(list_strategies "$dir" || true)
  if [ -z "$list" ]; then
    warn "Не удалось получить список с GitHub API (сеть / rate limit / нет curl|wget)."
    warn "Будет доступен только default из официального репозитория nfqws."
  fi

  i=1
  files="default"
  if [ -z "$current_id" ]; then
    printf "  %s%2d) default  (стандартная из репозитория nfqws)  <-- текущая?%s\n" "$GREEN$BOLD" "$i" "$NC"
  else
    printf "  %2d) default  (стандартная из репозитория nfqws)\n" "$i"
  fi
  i=2

  # shellcheck disable=SC2086
  for f in $list; do
    base=$(echo "$f" | sed 's/\.conf$//' | tr '[:upper:]' '[:lower:]')
    if [ -n "$current_id" ] && [ "$base" = "$current_id" ]; then
      printf "  %s%2d) %s  <-- текущая%s\n" "$GREEN$BOLD" "$i" "$f" "$NC"
    else
      printf "  %2d) %s\n" "$i" "$f"
    fi
    files="$files $f"
    i=$((i + 1))
  done
  echo "   0) Назад"
  ask "Номер стратегии: "
  read -r num
  [ -z "$num" ] || [ "$num" = "0" ] && return

  idx=1
  selected=""
  for f in $files; do
    if [ "$idx" = "$num" ]; then
      selected="$f"
      break
    fi
    idx=$((idx + 1))
  done
  [ -z "$selected" ] && { warn "Неверный номер"; return; }

  apply_strategy "$NFQWS_VER" "$selected"
}

# ---------------------------------------------------------------------------
# 4. IPSet List
# ---------------------------------------------------------------------------
IPSET_SOURCE_URL="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt"

update_ipset_list() {
  need_nfqws_installed || return
  pick_nfqws_ver 1 || return

  local tmp cleaned count
  tmp="/tmp/nfqws-ipset-$$.txt"
  cleaned="/tmp/nfqws-ipset-clean-$$.txt"

  info "Скачивание IPSet с Flowseal/zapret-discord-youtube ..."
  info "URL: $IPSET_SOURCE_URL"
  if ! download_file "$IPSET_SOURCE_URL" "$tmp"; then
    error "Не удалось скачать список."
    rm -f "$tmp"
    return 1
  fi

  grep -vE '^[[:space:]]*(#|;|$)' "$tmp" | sed 's/[[:space:]]*$//' | grep -vE '^$' > "$cleaned" || true
  count=$(wc -l < "$cleaned" 2>/dev/null | tr -d ' ')
  if [ -z "$count" ] || [ "$count" = "0" ]; then
    error "Скачанный файл пуст или не содержит записей."
    rm -f "$tmp" "$cleaned"
    return 1
  fi
  info "Записей в списке: $count"

  write_ipset() {
    local dest="$1" dir
    dir=$(dirname "$dest")
    mkdir -p "$dir"
    backup_file "$dest"
    cp "$cleaned" "$dest"
    info "Записано: $dest ($count строк)"
  }

  case "$NFQWS_VER" in
    1)
      write_ipset "/opt/etc/nfqws/ipset.list"
      service_restart /opt/etc/init.d/S51nfqws
      info "Сервис nfqws перезапущен."
      ;;
    2)
      write_ipset "/opt/etc/nfqws2/lists/ipset.list"
      service_restart /opt/etc/init.d/S51nfqws2
      info "Сервис nfqws2 перезапущен."
      ;;
    both)
      write_ipset "/opt/etc/nfqws/ipset.list"
      write_ipset "/opt/etc/nfqws2/lists/ipset.list"
      service_restart /opt/etc/init.d/S51nfqws
      service_restart /opt/etc/init.d/S51nfqws2
      info "Сервисы перезапущены."
      ;;
  esac
  rm -f "$tmp" "$cleaned"
}

# ---------------------------------------------------------------------------
# 5. rkn.list (zapret4rocket) → nfqws2 lists + MODE_LIST
# ---------------------------------------------------------------------------
RKN_LIST_URL="https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/refs/heads/master/extra_strats/TCP/RKN/List.txt"
RKN_LIST_DEST="/opt/etc/nfqws2/lists/rkn.list"
RKN_HOSTLIST_ARG="--hostlist=/opt/etc/nfqws2/lists/rkn.list"

update_rkn_list() {
  refresh_opkg_cache
  if ! is_installed "nfqws2-keenetic"; then
    error "Пункт доступен только при установленном nfqws2-keenetic."
    return 1
  fi

  local conf="/opt/etc/nfqws2/nfqws2.conf"
  local tmp="/tmp/nfqws-rkn-$$.txt" cleaned="/tmp/nfqws-rkn-clean-$$.txt" count

  info "Скачивание rkn.list (zapret4rocket) ..."
  info "URL: $RKN_LIST_URL"
  if ! download_file "$RKN_LIST_URL" "$tmp"; then
    error "Не удалось скачать список."
    rm -f "$tmp"
    return 1
  fi

  grep -vE '^[[:space:]]*(#|;|$)' "$tmp" | sed 's/[[:space:]]*$//' | grep -vE '^$' > "$cleaned" || true
  count=$(wc -l < "$cleaned" 2>/dev/null | tr -d ' ')
  if [ -z "$count" ] || [ "$count" = "0" ]; then
    error "Скачанный файл пуст или не содержит записей."
    rm -f "$tmp" "$cleaned"
    return 1
  fi
  info "Записей в списке: $count"

  mkdir -p "$(dirname "$RKN_LIST_DEST")"
  cp "$cleaned" "$RKN_LIST_DEST"
  info "Записано: $RKN_LIST_DEST ($count строк)"
  rm -f "$tmp" "$cleaned"

  if [ ! -f "$conf" ]; then
    warn "Конфиг не найден: $conf — MODE_LIST не обновлён."
    return 0
  fi

  # -- перед паттерном: иначе grep воспринимает --hostlist=... как свою опцию
  if grep -qF -- "$RKN_HOSTLIST_ARG" "$conf" 2>/dev/null; then
    info "MODE_LIST уже содержит $RKN_HOSTLIST_ARG"
  elif grep -qE '^MODE_LIST=' "$conf" 2>/dev/null; then
    backup_file "$conf"
    # Вставляем --hostlist=...rkn.list перед закрывающей кавычкой MODE_LIST="..."
    sed -i "s|^\\(MODE_LIST=\"[^\"]*\\)\"|\\1 ${RKN_HOSTLIST_ARG}\"|" "$conf"
    if grep -qF -- "$RKN_HOSTLIST_ARG" "$conf" 2>/dev/null; then
      warn "В MODE_LIST добавлено: $RKN_HOSTLIST_ARG"
    else
      warn "Не удалось изменить MODE_LIST автоматически — добавьте вручную:"
      warn "  MODE_LIST=\"... $RKN_HOSTLIST_ARG\""
    fi
  else
    backup_file "$conf"
    printf '\nMODE_LIST="--hostlist=/opt/etc/nfqws2/lists/user.list %s"\n' "$RKN_HOSTLIST_ARG" >> "$conf"
    info "MODE_LIST создан с user.list и rkn.list"
  fi

  service_restart /opt/etc/init.d/S51nfqws2
  info "Сервис nfqws2 перезапущен."
}

# ---------------------------------------------------------------------------
# 6. DoT/DoH bypass strategy в NFQWS_ARGS_CUSTOM
# ---------------------------------------------------------------------------
DOT_DOH_STRATEGY='               #DNS
               --filter-tcp=443,853 --filter-l7=tls
               --hostlist-domains=dot.pub,doh.pub,controld.com,opendns.com,anycast.censurfridns.dk,dns.alidns.com,libredns.gr,cloudflare-dns.com,one.one.one.one,opennameserver.org,cleanbrowsing.org,dns.adguard-dns.com,dns.comss.one,dns.nextdns.io,freedns.controld.com,dns10.quad9.net,dns.google
               --out-range=-d10
               --payload=tls_client_hello
               --lua-desync=circular:fails=2:time=60:retrans=3:nld=2
               --lua-desync=multisplit:pos=sniext+2:seqovl=3:padencap
               --lua-desync=fake:blob=fake_default_tls:optional:tcp_seq=-10000:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=rzd.ru:repeat=2
               --new
               --filter-udp=853 --filter-l7=quic
               --hostlist-domains=dns.adguard-dns.com,dns.nextdns.io
               --payload=quic_initial
               --lua-desync=send:ipfrag:ipfrag_pos_udp=128'

ensure_port_in_var() {
  local conf_file="$1" var="$2" port="$3" line val new_val
  line=$(grep -E "^${var}=" "$conf_file" 2>/dev/null | head -1)
  if [ -z "$line" ]; then
    printf '%s=%s\n' "$var" "$port" >> "$conf_file"
    info "${var}: создано со значением $port"
    return 0
  fi
  val=${line#${var}=}
  val=$(echo "$val" | tr -d '"' | tr -d "'")
  if echo ",$val," | grep -qE ",${port},"; then
    info "${var}: порт $port уже есть ($val)"
    return 0
  fi
  if [ -z "$val" ]; then new_val="$port"; else new_val="${val},${port}"; fi
  sed -i "s|^${var}=.*|${var}=${new_val}|" "$conf_file"
  info "${var}: добавлен порт $port → ${new_val}"
}

menu_dot_doh() {
  # refresh — кэш мог устареть; return 0 — set -e не должен выкидывать из меню
  refresh_opkg_cache
  if ! is_installed "nfqws2-keenetic"; then
    error "Пункт доступен только при установленном nfqws2-keenetic."
    return 0
  fi
  local conf="/opt/etc/nfqws2/nfqws2.conf"
  if [ ! -f "$conf" ]; then
    error "Конфиг $conf не найден."
    return 0
  fi

  echo
  confirm_yes "Добавить в NFQWS_ARGS_CUSTOM стратегию обхода блокировки DoT/DoH публичных DNS?" || {
    info "Отменено."; return 0
  }

  if grep -qE '#DNS|dot\.pub,doh\.pub' "$conf" 2>/dev/null; then
    warn "Похоже, стратегия DoT/DoH уже присутствует в конфиге."
    confirm_no "Добавить повторно?" || { info "Отменено."; return 0; }
  fi

  backup_file "$conf"

  local tmp="/tmp/nfqws2-conf-$$.tmp"
  local strat_tmp="/tmp/nfqws2-dot-$$.txt"
  printf '%s\n' "$DOT_DOH_STRATEGY" > "$strat_tmp"

  local found=0 in_block=0 has_content=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" -eq 0 ]; then
      case "$line" in
        NFQWS_ARGS_CUSTOM=\"\")
          found=1
          printf 'NFQWS_ARGS_CUSTOM="\n' >> "$tmp"
          cat "$strat_tmp" >> "$tmp"
          printf '"\n' >> "$tmp"
          ;;
        NFQWS_ARGS_CUSTOM=\")
          found=1; in_block=1
          printf '%s\n' "$line" >> "$tmp"
          ;;
        NFQWS_ARGS_CUSTOM=\"*\")
          found=1
          local body
          body=${line#NFQWS_ARGS_CUSTOM=\"}
          body=${body%\"}
          printf 'NFQWS_ARGS_CUSTOM="\n' >> "$tmp"
          if [ -n "$(echo "$body" | tr -d '[:space:]')" ]; then
            printf '%s\n' "$body" >> "$tmp"
            printf -- '--new\n' >> "$tmp"
          fi
          cat "$strat_tmp" >> "$tmp"
          printf '"\n' >> "$tmp"
          ;;
        NFQWS_ARGS_CUSTOM=\"*)
          found=1; in_block=1; has_content=1
          printf '%s\n' "$line" >> "$tmp"
          ;;
        *)
          printf '%s\n' "$line" >> "$tmp"
          ;;
      esac
    else
      case "$line" in
        \"|[[:space:]]*\")
          [ "$has_content" -eq 1 ] && printf -- '--new\n' >> "$tmp"
          cat "$strat_tmp" >> "$tmp"
          printf '%s\n' "$line" >> "$tmp"
          in_block=0
          ;;
        *\")
          local body
          body=${line%\"}
          if [ -n "$(echo "$body" | tr -d '[:space:]\\')" ]; then
            printf '%s\n' "$body" >> "$tmp"
            has_content=1
          fi
          [ "$has_content" -eq 1 ] && printf -- '--new\n' >> "$tmp"
          cat "$strat_tmp" >> "$tmp"
          printf '"\n' >> "$tmp"
          in_block=0
          ;;
        *)
          if [ -n "$(echo "$line" | tr -d '[:space:]\\')" ]; then
            has_content=1
          fi
          printf '%s\n' "$line" >> "$tmp"
          ;;
      esac
    fi
  done < "$conf"

  if [ "$found" -eq 0 ]; then
    printf '\nNFQWS_ARGS_CUSTOM="\n' >> "$tmp"
    cat "$strat_tmp" >> "$tmp"
    printf '"\n' >> "$tmp"
  fi

  if [ "$in_block" -eq 1 ]; then
    error "Не найдена закрывающая кавычка NFQWS_ARGS_CUSTOM — конфиг не изменён."
    rm -f "$tmp" "$strat_tmp"
    return 1
  fi

  mv "$tmp" "$conf"
  rm -f "$strat_tmp"
  info "Стратегия DoT/DoH добавлена в NFQWS_ARGS_CUSTOM."

  echo
  info "=== Проверка портов 853 (DoT) ==="
  ensure_port_in_var "$conf" "TCP_PORTS" "853"
  ensure_port_in_var "$conf" "UDP_PORTS" "853"
  service_restart /opt/etc/init.d/S51nfqws2
  info "Сервис nfqws2 перезапущен."
}

# ---------------------------------------------------------------------------
# 9. Управление DoT/DoH через ndmc
# ---------------------------------------------------------------------------
show_dns_servers() {
  if ! command -v ndmc >/dev/null 2>&1; then
    error "ndmc не найден. Функция доступна только на Keenetic/Netcraze OS."
    return 1
  fi

  ndmc -c "show dns-proxy" 2>/dev/null | awk -v c_reset="$NC" \
    -v c_bold="$BOLD" -v c_cyan="$CYAN" -v c_green="$GREEN" \
    -v c_yellow="$YELLOW" -v c_magenta="$MAGENTA" -v c_dim="$DIM" '
    BEGIN {
      dot_gen_cnt = 0; doh_gen_cnt = 0; dom_cnt = 0; dot_c = 0; doh_c = 0
      scope = 0; in_filters = 0
    }
    /proxy-name:/ {
      if ($0 ~ /System/) { scope = 1 }
      else if (scope == 1) { scope = 2 }
      next
    }
    scope != 1 { next }
    /^[ \t]*proxy-tls-filters:/ || /^[ \t]*proxy-https-filters:/ {
      if (in_dot && addr != "") commit_dot()
      if (in_doh && uri != "") commit_doh()
      in_filters = 1; in_dot = 0; in_doh = 0
      addr = ""; sni = ""; uri = ""; domain = ""; reading_uri = 0
      next
    }
    /^[ \t]*proxy-tls:/ || /^[ \t]*proxy-https:/ {
      if (in_dot && addr != "") commit_dot()
      if (in_doh && uri != "") commit_doh()
      in_filters = 0; in_dot = 0; in_doh = 0
      addr = ""; sni = ""; uri = ""; domain = ""; reading_uri = 0
      next
    }
    /^[ \t]*server-tls:[ \t]*$/ {
      if (in_filters) next
      if (in_dot && addr != "") commit_dot()
      in_dot = 1; in_doh = 0; reading_uri = 0
      addr = ""; sni = ""; domain = ""; next
    }
    /^[ \t]*server-https:[ \t]*$/ {
      if (in_filters) next
      if (in_dot && addr != "") commit_dot()
      if (in_doh && uri != "") commit_doh()
      in_doh = 1; in_dot = 0; reading_uri = 0
      addr = ""; sni = ""; uri = ""; domain = ""; next
    }
    in_dot && $1 ~ /^address:$/ { addr = $2; next }
    in_dot && $1 ~ /^port:$/    { if ($2 != "" && $2 != "853") addr = addr ":" $2; next }
    in_dot && $1 ~ /^sni:$/     { sni = $2; next }
    in_dot && $1 ~ /^domain:$/  { domain = $2; next }
    in_doh && $1 ~ /^uri:$/     { reading_uri = 1; uri = $2; next }
    in_doh && reading_uri && ($1 ~ /^(format|spki|interface|domain):$/) { reading_uri = 0 }
    in_doh && reading_uri { uri = uri $1; next }
    in_doh && $1 ~ /^domain:$/  { domain = $2; reading_uri = 0; next }
    END {
      if (in_dot && addr != "") commit_dot()
      if (in_doh && uri != "") commit_doh()
      print c_cyan "┌────────────────────────────────────────────────────────┐" c_reset
      print c_cyan "│" c_bold "          УПРАВЛЕНИЕ DNS СЕРВЕРАМИ KEENETIC             " c_cyan "│" c_reset
      print c_cyan "└────────────────────────────────────────────────────────┘" c_reset
      print "\n" c_bold c_magenta "  [ DoT Серверы ]" c_reset " " c_dim "[" dot_c+0 "/8]" c_reset
      if (dot_gen_cnt == 0) print "  " c_dim "— нет общих серверов —" c_reset
      for (i = 0; i < dot_gen_cnt; i++) print dot_gen[i]
      print "\n" c_bold c_cyan "  [ DoH Серверы ]" c_reset " " c_dim "[" doh_c+0 "/8]" c_reset
      if (doh_gen_cnt == 0) print "  " c_dim "— нет общих серверов —" c_reset
      for (i = 0; i < doh_gen_cnt; i++) print doh_gen[i]
      print "\n" c_bold c_yellow "  [ Персональные привязки к доменам ]" c_reset
      if (dom_cnt == 0) print "  " c_dim "— привязки отсутствуют —" c_reset
      for (i = 0; i < dom_cnt; i++) print dom_list[i]
      print "\n" c_dim "────────────────────────────────────────────────────────" c_reset
    }
    function commit_dot() {
      target = (sni != "") ? addr " " sni : addr
      if (domain == "") {
        key = "dot|" target
        if (!(key in seen_gen)) { seen_gen[key] = 1; dot_gen[dot_gen_cnt++] = "  " c_cyan "🔒" c_reset " " target }
      } else {
        key = "dom|dot|" domain "|" target
        if (!(key in seen_dom)) {
          seen_dom[key] = 1
          dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " target " " c_magenta "[DoT]" c_reset
        }
      }
      dot_c++; in_dot = 0; addr = ""; sni = ""; domain = ""
    }
    function commit_doh() {
      gsub(/[ \t\r\n]/, "", uri)
      if (uri == "") return
      if (domain == "") {
        key = "doh|" uri
        if (!(key in seen_gen)) { seen_gen[key] = 1; doh_gen[doh_gen_cnt++] = "  " c_green "⚡" c_reset " " uri }
      } else {
        key = "dom|doh|" domain "|" uri
        if (!(key in seen_dom)) {
          seen_dom[key] = 1
          dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " uri " " c_cyan "[DoH]" c_reset
        }
      }
      doh_c++; in_doh = 0; uri = ""; domain = ""; reading_uri = 0
    }
  '
}

dns_save_config() {
  printf '%s' "Сохранение конфигурации..."
  if ndmc -c "system configuration save" > /dev/null 2>&1; then
    printf ' %s\n' "${GREEN}[ГОТОВО]${NC}"
  else
    printf ' %s\n' "${RED}[ОШИБКА]${NC}"
    warn "ndmc не смог сохранить конфигурацию"
  fi
  sleep 1
}

apply_dot() {
  local ip="$1" sni="$2" domain="$3" port="$4" cmd
  cmd="dns-proxy tls upstream $ip"
  [ -n "$port" ] && cmd="$cmd $port"
  [ -n "$sni" ] && cmd="$cmd sni $sni"
  [ -n "$domain" ] && cmd="$cmd domain $domain"
  printf '%s\n' "${CYAN}Применение DoT ($ip):${NC} ndmc -c \"$cmd\""
  ndmc -c "$cmd" > /dev/null 2>&1 || warn "ndmc вернул ошибку при добавлении DoT $ip"
}

apply_doh() {
  local uri="$1" domain="$2" cmd
  cmd="dns-proxy https upstream $uri"
  [ -n "$domain" ] && cmd="$cmd domain $domain"
  printf '%s\n' "${CYAN}Применение DoH ($uri):${NC} ndmc -c \"$cmd\""
  ndmc -c "$cmd" > /dev/null 2>&1 || warn "ndmc вернул ошибку при добавлении DoH $uri"
}

# Data-driven DoT: N|label|ip|sni|port
# port пустой = default 853
dot_servers_data() {
  cat <<'EOF'
1|Yandex Primary|77.88.8.8|common.dot.dns.yandex.net|
2|Yandex Secondary|77.88.8.1|common.dot.dns.yandex.net|
3|Cloudflare Standard Primary|1.1.1.1|cloudflare-dns.com|
4|Cloudflare Standard Secondary|1.0.0.1|cloudflare-dns.com|
5|Cloudflare Malware Primary|1.1.1.2|cloudflare-dns.com|
6|Cloudflare Malware Secondary|1.0.0.2|cloudflare-dns.com|
7|Cloudflare Malware+Adult Primary|1.1.1.3|cloudflare-dns.com|
8|Cloudflare Malware+Adult Secondary|1.0.0.3|cloudflare-dns.com|
9|Quad9 Primary|9.9.9.9|dns.quad9.net|
10|Quad9 Secondary|149.112.112.112|dns.quad9.net|
11|CleanBrowsing Sec Filter 1|185.228.168.9|security-filter-dns.cleanbrowsing.org|853
12|CleanBrowsing Sec Filter 2|185.228.169.9|security-filter-dns2.cleanbrowsing.org|853
13|OpenDNS Primary|208.67.222.222|dns.opendns.com|
14|OpenDNS Secondary|208.67.220.220|dns.opendns.com|
15|DNS.SB Primary|185.222.222.222|dot.sb|
16|DNS.SB Secondary|45.11.45.11|dot.sb|
17|dns0.eu|dns0.eu|dns0.eu|
18|OpenNameServer ns1|217.160.70.42|ns1.opennameserver.org|
19|OpenNameServer ns2|213.202.211.221|ns2.opennameserver.org|
20|OpenNameServer ns3|81.169.136.222|ns3.opennameserver.org|
21|OpenNameServer ns4|185.181.61.24|ns4.opennameserver.org|
22|IIJ Japan|public.dns.iij.jp|public.dns.iij.jp|
23|Tiar Japan|jp.tiar.app|jp.tiar.app|
24|Xbox-DNS|xbox-dns.ru|xbox-dns.ru|
25|Comss DNS|dns.comss.one|dns.comss.one|
26|Malw Link|dns.malw.link|dns.malw.link|
27|Cloudflare Gateway|5u35p8m9i7.cloudflare-gateway.com|5u35p8m9i7.cloudflare-gateway.com|
28|Geo Hide|geohide.ru|geohide.ru|
EOF
}

# Data-driven DoH: N|label|uri
doh_servers_data() {
  cat <<'EOF'
1|Yandex Primary|https://77.88.8.8/dns-query
2|Yandex Secondary|https://77.88.8.1/dns-query
3|Cloudflare|https://cloudflare-dns.com/dns-query
4|Quad9|https://dns.quad9.net/dns-query
5|CleanBrowsing|https://doh.cleanbrowsing.org/doh/security-filter/
6|OpenDNS|https://doh.opendns.com/dns-query
7|DNS.SB|https://doh.dns.sb/dns-query
8|dns0.eu|https://dns0.eu/
9|OpenNameServer ns1|https://ns1.opennameserver.org/dns-query
10|OpenNameServer ns2|https://ns2.opennameserver.org/dns-query
11|OpenNameServer ns3|https://ns3.opennameserver.org/dns-query
12|OpenNameServer ns4|https://ns4.opennameserver.org/dns-query
13|IIJ Japan|https://public.dns.iij.jp/dns-query
14|Tiar Japan app|https://jp.tiar.app/dns-query
15|Tiar Japan org|https://jp.tiarap.org/dns-query
16|Xbox-DNS|https://xbox-dns.ru/dns-query
17|Comss DNS|https://dns.comss.one/dns-query
18|Malw Link|https://dns.malw.link/dns-query
19|Cloudflare Gateway|https://5u35p8m9i7.cloudflare-gateway.com/dns-query
20|Geo Hide|https://dns.geohide.ru/dns-query
EOF
}

print_dns_menu_header() {
  # $1 = section markers: lines "N|section_title" before item N
  :
}

add_dot_menu() {
  echo
  printf '%s\n' "${BOLD}Выбор DoT серверов (можно несколько через запятую, напр. 1,3,20):${NC}"
  printf '%s\n' " ${YELLOW}--- Яндекс & Cloudflare ---${NC}"
  echo " 1) Yandex Primary (77.88.8.8)"
  echo " 2) Yandex Secondary (77.88.8.1)"
  echo " 3) Cloudflare Standard Primary (1.1.1.1)"
  echo " 4) Cloudflare Standard Secondary (1.0.0.1)"
  echo " 5) Cloudflare Malware Primary (1.1.1.2)"
  echo " 6) Cloudflare Malware Secondary (1.0.0.2)"
  echo " 7) Cloudflare Malware+Adult Primary (1.1.1.3)"
  echo " 8) Cloudflare Malware+Adult Secondary (1.0.0.3)"
  printf '%s\n' " ${YELLOW}--- Безопасность & Приватность ---${NC}"
  echo " 9) Quad9 Primary (9.9.9.9)"
  echo "10) Quad9 Secondary (149.112.112.112)"
  echo "11) CleanBrowsing Sec Filter 1 (185.228.168.9)"
  echo "12) CleanBrowsing Sec Filter 2 (185.228.169.9)"
  echo "13) OpenDNS Primary (208.67.222.222)"
  echo "14) OpenDNS Secondary (208.67.220.220)"
  echo "15) DNS.SB Primary (185.222.222.222)"
  echo "16) DNS.SB Secondary (45.11.45.11)"
  echo "17) dns0.eu (dns0.eu)"
  printf '%s\n' " ${YELLOW}--- OpenNameServer ---${NC}"
  echo "18) OpenNameServer ns1 (217.160.70.42)"
  echo "19) OpenNameServer ns2 (213.202.211.221)"
  echo "20) OpenNameServer ns3 (81.169.136.222)"
  echo "21) OpenNameServer ns4 (185.181.61.24)"
  printf '%s\n' " ${YELLOW}--- Япония ---${NC}"
  echo "22) IIJ Japan (public.dns.iij.jp)"
  echo "23) Tiar Japan (jp.tiar.app)"
  printf '%s\n' " ${GREEN}--- Proxy-DNS (Обход блокировок) ---${NC}"
  echo "24) Xbox-DNS (xbox-dns.ru)"
  echo "25) Comss DNS (dns.comss.one)"
  echo "26) Malw Link (dns.malw.link)"
  echo "27) Cloudflare Gateway (5u35p8m9i7.cloudflare-gateway.com)"
  echo "28) Geo Hide (geohide.ru)"
  printf '%s\n' " ${YELLOW}--- Свой вариант ---${NC}"
  echo "29) Ввести вручную (IP / Port / SNI)"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  ask "Привязать выбранные к домену? (пусто для всех): "
  read -r domain

  local added_any=0 choice num label ip sni port
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    if [ "$choice" = "29" ]; then
      ask "Введите IP/Хост: "; read -r manual_ip
      ask "Введите Порт (по умолчанию 853, отмена - Enter): "; read -r manual_port
      ask "Введите SNI (отмена - Enter): "; read -r manual_sni
      if [ -n "$manual_ip" ]; then
        apply_dot "$manual_ip" "$manual_sni" "$domain" "$manual_port"
        added_any=1
      fi
      continue
    fi
    line=$(dot_servers_data | grep -E "^${choice}\|")
    [ -n "$line" ] || continue
    # N|label|ip|sni|port
    num=$(echo "$line" | cut -d'|' -f1)
    ip=$(echo "$line" | cut -d'|' -f3)
    sni=$(echo "$line" | cut -d'|' -f4)
    port=$(echo "$line" | cut -d'|' -f5)
    apply_dot "$ip" "$sni" "$domain" "$port"
    added_any=1
  done
  [ "$added_any" -eq 1 ] && dns_save_config
}

add_doh_menu() {
  echo
  printf '%s\n' "${BOLD}Выбор DoH серверов (можно несколько через запятую, напр. 1,3,13):${NC}"
  printf '%s\n' " ${YELLOW}--- Яндекс & Cloudflare ---${NC}"
  echo " 1) Yandex Primary (https://77.88.8.8/dns-query)"
  echo " 2) Yandex Secondary (https://77.88.8.1/dns-query)"
  echo " 3) Cloudflare (https://cloudflare-dns.com/dns-query)"
  printf '%s\n' " ${YELLOW}--- Безопасность & Приватность ---${NC}"
  echo " 4) Quad9 (https://dns.quad9.net/dns-query)"
  echo " 5) CleanBrowsing (https://doh.cleanbrowsing.org/doh/security-filter/)"
  echo " 6) OpenDNS (https://doh.opendns.com/dns-query)"
  echo " 7) DNS.SB (https://doh.dns.sb/dns-query)"
  echo " 8) dns0.eu (https://dns0.eu/)"
  printf '%s\n' " ${YELLOW}--- OpenNameServer ---${NC}"
  echo " 9) OpenNameServer ns1 (https://ns1.opennameserver.org/dns-query)"
  echo "10) OpenNameServer ns2 (https://ns2.opennameserver.org/dns-query)"
  echo "11) OpenNameServer ns3 (https://ns3.opennameserver.org/dns-query)"
  echo "12) OpenNameServer ns4 (https://ns4.opennameserver.org/dns-query)"
  printf '%s\n' " ${YELLOW}--- Япония ---${NC}"
  echo "13) IIJ Japan (https://public.dns.iij.jp/dns-query)"
  echo "14) Tiar Japan app (https://jp.tiar.app/dns-query)"
  echo "15) Tiar Japan org (https://jp.tiarap.org/dns-query)"
  printf '%s\n' " ${GREEN}--- Proxy-DNS (Обход блокировок) ---${NC}"
  echo "16) Xbox-DNS (https://xbox-dns.ru/dns-query)"
  echo "17) Comss DNS Keenetic/MikroTik (https://dns.comss.one/dns-query)"
  echo "18) Malw Link (https://dns.malw.link/dns-query)"
  echo "19) Cloudflare Gateway (https://5u35p8m9i7.cloudflare-gateway.com/dns-query)"
  echo "20) Geo Hide (https://dns.geohide.ru/dns-query)"
  printf '%s\n' " ${YELLOW}--- Свой вариант ---${NC}"
  echo "21) Ввести вручную (произвольный URI)"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  ask "Привязать выбранные к домену? (пусто для всех): "
  read -r domain

  local added_any=0 choice line uri
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    if [ "$choice" = "21" ]; then
      ask "Введите URI DoH сервера: "; read -r manual_uri
      if [ -n "$manual_uri" ]; then
        apply_doh "$manual_uri" "$domain"
        added_any=1
      fi
      continue
    fi
    line=$(doh_servers_data | grep -E "^${choice}\|")
    [ -n "$line" ] || continue
    uri=$(echo "$line" | cut -d'|' -f3)
    apply_doh "$uri" "$domain"
    added_any=1
  done
  [ "$added_any" -eq 1 ] && dns_save_config
}

add_domain_menu() {
  echo
  printf '%s\n' "${BOLD}Быстрая привязка DNS к целевым доменам (можно несколько через запятую, напр. 1,3,5):${NC}"
  echo " 1) CleanBrowsing DoT (185.228.168.9 + SNI) ➔ instagram.com"
  echo " 2) CleanBrowsing DoH (doh.cleanbrowsing.org) ➔ instagram.com"
  echo " 3) sw.ext.io DoT ➔ rutor.is & rutor.info"
  echo " 4) Malw Link DoH (dns.malw.link) ➔ ntc.party"
  echo " 5) Xbox-DNS DoT ➔ gql.twitch.tv & usher.ttvnw.net"
  echo " 6) Xbox-DNS DoH ➔ gql.twitch.tv & usher.ttvnw.net"
  echo " 7) Ввести свой домен и выбрать сервер"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  local added_any=0 choice
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    case $choice in
      1) apply_dot "185.228.168.9" "security-filter-dns.cleanbrowsing.org" "instagram.com" "853"; added_any=1 ;;
      2) apply_doh "https://doh.cleanbrowsing.org/doh/security-filter/" "instagram.com"; added_any=1 ;;
      3)
        apply_dot "sw.ext.io" "" "rutor.is"
        apply_dot "sw.ext.io" "" "rutor.info"
        added_any=1
        ;;
      4) apply_doh "https://dns.malw.link/dns-query" "ntc.party"; added_any=1 ;;
      5)
        apply_dot "xbox-dns.ru" "xbox-dns.ru" "gql.twitch.tv"
        apply_dot "xbox-dns.ru" "xbox-dns.ru" "usher.ttvnw.net"
        added_any=1
        ;;
      6)
        apply_doh "https://xbox-dns.ru/dns-query" "gql.twitch.tv"
        apply_doh "https://xbox-dns.ru/dns-query" "usher.ttvnw.net"
        added_any=1
        ;;
      7)
        ask "Введите домен (например: example.com): "; read -r dom
        [ -z "$dom" ] && continue
        echo "Тип протокола: 1) DoT  2) DoH"
        ask "Выберите [1-2]: "; read -r ptype
        if [ "$ptype" = "1" ]; then
          ask "Введите IP/Хост DoT: "; read -r dot_ip
          ask "Введите SNI (необязательно): "; read -r dot_sni
          ask "Введите порт (по умолчанию 853, Enter - пропустить): "; read -r dot_port
          [ -n "$dot_ip" ] && { apply_dot "$dot_ip" "$dot_sni" "$dom" "$dot_port"; added_any=1; }
        elif [ "$ptype" = "2" ]; then
          ask "Введите URI DoH: "; read -r doh_uri
          [ -n "$doh_uri" ] && { apply_doh "$doh_uri" "$dom"; added_any=1; }
        fi
        ;;
    esac
  done
  [ "$added_any" -eq 1 ] && dns_save_config
}

remove_dns_menu() {
  local tmp_list="/tmp/dns_rem_list.txt"
  rm -f "$tmp_list"

  ndmc -c "show dns-proxy" 2>/dev/null | awk '
    /server-tls:/ {
      if (in_dot && addr != "") {
        p = (port != "") ? port : "853"
        key = addr "|" p
        if (!(key in dot_order)) { dot_addrs[dot_cnt++] = key; dot_order[key] = 1 }
        if (domain != "") {
          dom_key = key "|" domain
          if (!(dom_key in dot_dom_seen)) {
            dot_dom_seen[dom_key] = 1
            dot_doms[key] = (dot_doms[key] != "") ? dot_doms[key] ", " domain : domain
          }
        }
      }
      in_dot=1; in_doh=0; addr=""; port=""; domain=""; next
    }
    in_dot && /address:/ { addr=$2 }
    in_dot && /port:/ { port=$2 }
    in_dot && /domain:/ { domain=$2 }
    /server-https:/ {
      if (in_dot && addr != "") {
        p = (port != "") ? port : "853"
        key = addr "|" p
        if (!(key in dot_order)) { dot_addrs[dot_cnt++] = key; dot_order[key] = 1 }
        if (domain != "") {
          dom_key = key "|" domain
          if (!(dom_key in dot_dom_seen)) {
            dot_dom_seen[dom_key] = 1
            dot_doms[key] = (dot_doms[key] != "") ? dot_doms[key] ", " domain : domain
          }
        }
      }
      if (in_doh && uri != "") {
        gsub(/[ \t\r\n]/, "", uri)
        if (!(uri in doh_order)) { doh_addrs[doh_cnt++] = uri; doh_order[uri] = 1 }
        if (domain != "") {
          dom_key = uri "|" domain
          if (!(dom_key in doh_dom_seen)) {
            doh_dom_seen[dom_key] = 1
            doh_doms[uri] = (doh_doms[uri] != "") ? doh_doms[uri] ", " domain : domain
          }
        }
      }
      in_doh=1; in_dot=0; addr=""; port=""; uri=""; domain=""; next
    }
    in_doh && /uri:/ { reading_uri=1; uri=$2; next }
    in_doh && reading_uri && (/format:/ || /spki:/ || /interface:/ || /domain:/) { reading_uri=0 }
    in_doh && reading_uri { uri=uri $1 }
    in_doh && /domain:/ { domain=$2 }
    END {
      if (in_dot && addr != "") {
        p = (port != "") ? port : "853"
        key = addr "|" p
        if (!(key in dot_order)) { dot_addrs[dot_cnt++] = key; dot_order[key] = 1 }
        if (domain != "") {
          dom_key = key "|" domain
          if (!(dom_key in dot_dom_seen)) {
            dot_dom_seen[dom_key] = 1
            dot_doms[key] = (dot_doms[key] != "") ? dot_doms[key] ", " domain : domain
          }
        }
      }
      if (in_doh && uri != "") {
        gsub(/[ \t\r\n]/, "", uri)
        if (!(uri in doh_order)) { doh_addrs[doh_cnt++] = uri; doh_order[uri] = 1 }
        if (domain != "") {
          dom_key = uri "|" domain
          if (!(dom_key in doh_dom_seen)) {
            doh_dom_seen[dom_key] = 1
            doh_doms[uri] = (doh_doms[uri] != "") ? doh_doms[uri] ", " domain : domain
          }
        }
      }
      idx = 1
      for (i = 0; i < dot_cnt; i++) {
        split(dot_addrs[i], parts, "|")
        print idx " | dot | " parts[1] " | " parts[2] " | " dot_doms[dot_addrs[i]]
        idx++
      }
      for (i = 0; i < doh_cnt; i++) {
        u = doh_addrs[i]
        print idx " | doh | " u " | | " doh_doms[u]
        idx++
      }
    }
  ' > "$tmp_list"

  if [ ! -s "$tmp_list" ]; then
    echo
    warn "Нет настроенных DNS серверов для удаления."
    sleep 1
    return
  fi

  echo
  printf '%s\n' "${BOLD}${RED}Список настроенных серверов для удаления:${NC}"
  while IFS='|' read -r num type target port doms; do
    num=$(echo "$num" | xargs)
    type=$(echo "$type" | xargs)
    target=$(echo "$target" | xargs)
    port=$(echo "$port" | xargs)
    doms=$(echo "$doms" | xargs)
    label_type=""
    [ "$type" = "dot" ] && label_type="${MAGENTA}[DoT]${NC}"
    [ "$type" = "doh" ] && label_type="${CYAN}[DoH]${NC}"
    dom_info=""
    [ -n "$doms" ] && dom_info=" ${YELLOW}(domains: $doms)${NC}"
    printf ' %s%s)%s %s %s%s\n' "$BOLD" "$num" "$NC" "$label_type" "$target" "$dom_info"
  done < "$tmp_list"

  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите номера для удаления (можно несколько через запятую): "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && { rm -f "$tmp_list"; return; }

  local removed_any=0 choice line type target port cmd
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    line=$(grep -E "^$choice \|" "$tmp_list")
    [ -n "$line" ] || continue
    type=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
    target=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
    port=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
    if [ "$type" = "dot" ]; then
      if [ -n "$port" ] && [ "$port" != "853" ]; then
        cmd="no dns-proxy tls upstream $target $port"
      else
        cmd="no dns-proxy tls upstream $target"
      fi
    elif [ "$type" = "doh" ]; then
      cmd="no dns-proxy https upstream $target"
    else
      continue
    fi
    printf '%s\n' "${RED}Удаление:${NC} ndmc -c \"$cmd\""
    if ndmc -c "$cmd" > /dev/null 2>&1; then
      removed_any=1
    else
      warn "ndmc не смог удалить: $target"
    fi
  done
  rm -f "$tmp_list"
  [ "$removed_any" -eq 1 ] && dns_save_config
}

menu_dns_manage() {
  if ! command -v ndmc >/dev/null 2>&1; then
    error "ndmc не найден. Управление DoT/DoH доступно только на Keenetic/Netcraze OS."
    return 1
  fi
  while true; do
    clear 2>/dev/null || true
    show_dns_servers
    echo
    printf '%s\n' " ${BOLD}1)${NC} Добавить DoT сервер(ы)"
    printf '%s\n' " ${BOLD}2)${NC} Добавить DoH сервер(ы)"
    printf '%s\n' " ${BOLD}3)${NC} ${YELLOW}Привязать домен к DNS (Пресеты)${NC}"
    printf '%s\n' " ${BOLD}4)${NC} ${RED}Удалить сервер(ы)${NC}"
    printf '%s\n' " ${BOLD}0)${NC} Назад"
    printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
    ask "Выберите действие [0-4]: "
    read -r choice
    case $choice in
      1) add_dot_menu ;;
      2) add_doh_menu ;;
      3) add_domain_menu ;;
      4) remove_dns_menu ;;
      0|"") return 0 ;;
      *) warn "Неверный ввод, попробуйте снова."; sleep 1 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# 99. Обновить скрипт
# ---------------------------------------------------------------------------
resolve_script_path() {
  local src=""
  if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    src="$SCRIPT_PATH"
  else
    src=$0
    case "$src" in /*) ;; *) src="$(pwd)/$src" ;; esac
  fi
  echo "$src"
}

extract_script_version() {
  grep -E '^SCRIPT_VERSION=' "$1" 2>/dev/null | head -1 | \
    sed -n 's/^SCRIPT_VERSION="\([^"]*\)".*/\1/p'
}

update_self() {
  local url tmp remote_ver dest="/opt/nfqws-menu.sh"
  url="${RAW_BASE}/nfqws-menu.sh?t=$(date +%s)"
  tmp="/tmp/nfqws-menu-update-$$.sh"
  if ! download_file "$url" "$tmp" 2>/dev/null; then
    url="${RAW_BASE}/nfqws-menu.sh"
    if ! download_file "$url" "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      return 1
    fi
  fi
  if ! head -1 "$tmp" | grep -qE '^#!/(usr/)?bin/(sh|bash)' || ! grep -q 'SCRIPT_VERSION=' "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  remote_ver=$(extract_script_version "$tmp")
  [ -z "$remote_ver" ] && remote_ver="?"
  if ! cat "$tmp" > "$dest"; then
    rm -f "$tmp"
    return 1
  fi
  chmod +x "$dest" 2>/dev/null || true
  rm -f "$tmp"
  unset SCRIPT_PATH
  export SCRIPT_PATH="$dest"
  exec sh "$dest"
}

# ---------------------------------------------------------------------------
# 10–14. Утилиты
# ---------------------------------------------------------------------------
DPI_DETECTOR_INSTALL_URL="https://raw.githubusercontent.com/Runnin4ik/dpi-detector/rust/install.sh"
AWG_MANAGER_INSTALL_URL="https://raw.githubusercontent.com/rndnaame/awg-compressed/main/install-compressed.sh"
KEENKIT_INSTALL_URL="https://raw.githubusercontent.com/spatiumstas/KeenKit/main/install.sh"

cleanup_dpi_detector_dupes() {
  local primary="" f
  if [ -x /opt/bin/dpi-detector ]; then
    primary="/opt/bin/dpi-detector"
  elif command -v dpi-detector >/dev/null 2>&1; then
    primary=$(command -v dpi-detector)
  fi
  for f in /tmp/dpi-detector /opt/root/dpi-detector ${HOME:+$HOME/dpi-detector} /tmp/dpi-detector* /opt/root/dpi-detector*; do
    [ -f "$f" ] || continue
    [ -n "$primary" ] && [ "$f" = "$primary" ] && continue
    [ -n "$primary" ] && [ -f "$primary" ] && rm -f "$f" && info "  удалён дубликат: $f"
  done
  if [ -x /opt/bin/dpi-detector ]; then
    info "Основной бинарник: /opt/bin/dpi-detector"
  elif [ -n "$primary" ]; then
    info "Основной бинарник: $primary"
  fi
}

menu_dpi_detector() {
  echo
  info "dpi-detector (rust) — установка актуальной версии"
  if [ -x /opt/bin/dpi-detector ]; then
    info "Основной бинарник на месте: /opt/bin/dpi-detector"
    cleanup_dpi_detector_dupes
    info "Запуск /opt/bin/dpi-detector ..."
    if [ -c /dev/tty ]; then
      /opt/bin/dpi-detector </dev/tty
    else
      /opt/bin/dpi-detector
    fi
    return 0
  fi
  info "Источник: $DPI_DETECTOR_INSTALL_URL"
  echo
  confirm_yes "Установить dpi-detector?" || { info "Отменено."; return 0; }
  info "Запуск установщика..."
  run_remote_sh "$DPI_DETECTOR_INSTALL_URL" || return 1
  echo
  info "Очистка дубликатов dpi-detector (/tmp, /opt/root)..."
  cleanup_dpi_detector_dupes
  info "Установка dpi-detector завершена."
  if [ -x /opt/bin/dpi-detector ]; then
    info "Запуск /opt/bin/dpi-detector ..."
    if [ -c /dev/tty ]; then
      /opt/bin/dpi-detector </dev/tty
    else
      /opt/bin/dpi-detector
    fi
  else
    warn "Бинарник /opt/bin/dpi-detector не найден — запуск пропущен."
  fi
}

menu_awg_manager() {
  echo
  info "awg-manager — установка через awg-compressed"
  info "Источник: $AWG_MANAGER_INSTALL_URL"
  echo
  confirm_yes "Запустить установщик awg-manager?" || { info "Отменено."; return 0; }
  info "Запуск установщика..."
  run_remote_sh "$AWG_MANAGER_INSTALL_URL" || return 1
  info "Установщик awg-manager завершил работу."
}

menu_keenkit() {
  echo
  if [ -f /opt/keenkit.sh ]; then
    info "Найден /opt/keenkit.sh — запуск..."
    if [ -c /dev/tty ]; then
      sh /opt/keenkit.sh </dev/tty
    else
      sh /opt/keenkit.sh
    fi
    return 0
  fi
  info "KeenKit — установка"
  info "Источник: $KEENKIT_INSTALL_URL"
  echo
  confirm_yes "Запустить установщик KeenKit?" || { info "Отменено."; return 0; }
  info "Запуск установщика..."
  if command -v curl >/dev/null 2>&1; then
    curl -L -s "$KEENKIT_INSTALL_URL" > /tmp/keenkit-install.sh && sh /tmp/keenkit-install.sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO /tmp/keenkit-install.sh "$KEENKIT_INSTALL_URL" && sh /tmp/keenkit-install.sh
  else
    error "Нужны curl или wget."
    return 1
  fi
  rm -f /tmp/keenkit-install.sh 2>/dev/null || true
  info "Установщик KeenKit завершил работу."
}

menu_tg_ws_proxy() {
  echo
  info "TG WS Proxy Go (tg-ws-proxy)"
  if is_installed "tg-ws-proxy"; then
    opkg_install_or_upgrade tg-ws-proxy
  else
    info "Пакет не установлен — установка..."
    run_remote_sh "https://raw.githubusercontent.com/spatiumstas/feedly/main/add-repo.sh" || return 1
    opkg install tg-ws-proxy
    info "Установка завершена."
  fi
  echo
  printf '%s\n' "${BOLD}Дополнительная информация:${NC}"
  cat << 'EOF'
# Entware (KeeneticOS):
#   /opt/etc/tg-ws-proxy/config.conf
#   /opt/etc/tg-ws-proxy/secret.conf
https://github.com/spatiumstas/tg-ws-proxy-go

SECRET должен быть строкой из 32 hex-символов. Если оставить пустым, он будет автоматически сгенерирован при запуске.
DC_IP_DEFAULT и DC_IP_DEFAULT_POOL — глобальные значения по умолчанию для DC (2,4).
EXTRA_ARGS используется для переопределений по DC и дополнительных флагов, см. CFProxy.
Полный список доступных команд: --help.
FAKE_TLS_DOMAIN включает режим Fake TLS (ee secret link). Оставьте пустым для стандартного режима dd.
CFPROXY_DOMAINS — локальный список fallback-доменов.
CFPROXY_DOMAINS_URL — значение по умолчанию/зеркало

# Entware (KeeneticOS)
/opt/etc/init.d/S99tg-ws-proxy (start / stop / status / restart)
EOF
}

menu_usque_keenetic() {
  echo
  info "usque-keenetic"
  [ -z "$ARCH" ] && detect_arch

  if is_installed "usque-keenetic"; then
    opkg_install_or_upgrade usque-keenetic
  else
    info "Пакет не установлен — установка..."
    ensure_opkg_repo "usque-keenetic" "https://side-effect-tm.github.io/usque-keenetic/$ARCH"
    info "Репозиторий: https://side-effect-tm.github.io/usque-keenetic/$ARCH"
    opkg install usque-keenetic
    info "Установка завершена."
  fi

  echo
  printf '%s\n' "${BOLD}Управление сервисом${NC}"
  cat << 'EOF'
/opt/etc/init.d/S51usque (start | stop | restart)
EOF
  echo
  printf '%s\n' "${BOLD}Конфигурация${NC}"
  echo "Файл конфигурации расположен по пути /opt/etc/usque/usque.conf"
  cat << 'EOF'
# Интерфейс. Определяется автоматически при установке.
# Должен быть вида opkgtun*
IFACE="opkgtun0"
EOF
}

menu_magitrickle() {
  echo
  info "MagiTrickle"
  refresh_opkg_cache

  if is_installed "magitrickle"; then
    info "Пакет установлен — обновление..."
    opkg update
    opkg install magitrickle
    if [ -x /opt/etc/init.d/S99magitrickle ]; then
      /opt/etc/init.d/S99magitrickle restart
      info "Сервис перезапущен: /opt/etc/init.d/S99magitrickle restart"
    else
      warn "Init-скрипт /opt/etc/init.d/S99magitrickle не найден."
    fi
    info "Обновление завершено."
  else
    info "Пакет не установлен — установка..."
    confirm_yes "Добавить репозиторий MagiTrickle и установить пакет?" || { info "Отменено."; return 0; }
    info "Добавление репозитория..."
    if command -v wget >/dev/null 2>&1; then
      wget -qO- http://bin.magitrickle.dev/packages/add_repo.sh | sh || return 1
    elif command -v curl >/dev/null 2>&1; then
      curl -fsSL http://bin.magitrickle.dev/packages/add_repo.sh | sh || return 1
    else
      error "Нужны wget или curl."
      return 1
    fi
    opkg update
    opkg install magitrickle
    if [ -x /opt/etc/init.d/S99magitrickle ]; then
      /opt/etc/init.d/S99magitrickle start
      info "Сервис запущен: /opt/etc/init.d/S99magitrickle start"
    else
      warn "Init-скрипт /opt/etc/init.d/S99magitrickle не найден."
    fi
    info "Установка завершена."
  fi

  echo
  printf '%s\n' "${BOLD}Управление сервисом${NC}"
  cat << 'EOF'
/opt/etc/init.d/S99magitrickle (start | stop | restart | status)
EOF
}

# ---------------------------------------------------------------------------
# 88. Удаление
# ---------------------------------------------------------------------------
remove_backups() {
  local dirs="/opt/etc/nfqws /opt/etc/nfqws2 /opt/etc/nfqws2/lists"
  local f count=0 found=""

  echo
  info "Поиск резервных копий (.bak.* , *.conf-opkg , *.list-opkg)..."
  for d in $dirs; do
    [ -d "$d" ] || continue
    for f in "$d"/*.bak.* "$d"/*.conf-opkg "$d"/*.list-opkg; do
      [ -f "$f" ] || continue
      found="$found $f"
    done
  done
  if [ -z "$found" ]; then
    info "Резервные копии не найдены."
    return 0
  fi
  for f in $found; do
    echo "  $f"
    count=$((count + 1))
  done
  echo
  if confirm_no "Удалить найденные файлы ($count шт.)?"; then
    for f in $found; do
      rm -f "$f" && info "  удалён: $f" || warn "  не удалось: $f"
    done
    info "Готово."
  else
    info "Отменено."
  fi
}

is_dpi_detector_installed() {
  [ -x /opt/bin/dpi-detector ] || command -v dpi-detector >/dev/null 2>&1
}

remove_dpi_detector() {
  local paths="/opt/bin/dpi-detector /tmp/dpi-detector" f found=0
  [ -n "$HOME" ] && paths="$paths $HOME/dpi-detector"
  for f in $paths; do
    [ -f "$f" ] && rm -f "$f" && info "  удалён: $f" && found=1
  done
  f=$(command -v dpi-detector 2>/dev/null || true)
  [ -n "$f" ] && [ -f "$f" ] && rm -f "$f" && info "  удалён: $f" && found=1
  if [ "$found" -eq 0 ]; then
    warn "dpi-detector не найден."
  else
    info "dpi-detector удалён."
  fi
}

is_awg_manager_installed() {
  is_installed "awg-manager" || [ -d /opt/etc/awg-manager ]
}

remove_awg_manager() {
  if is_installed "awg-manager"; then
    opkg remove awg-manager 2>/dev/null || opkg remove --autoremove awg-manager 2>/dev/null || true
  fi
  [ -d /opt/etc/awg-manager ] && rm -rf /opt/etc/awg-manager && info "  удалён каталог: /opt/etc/awg-manager"
  info "awg-manager удалён."
}

remove_tg_ws_proxy() {
  if is_installed "tg-ws-proxy"; then
    opkg remove tg-ws-proxy 2>/dev/null || opkg remove --autoremove tg-ws-proxy 2>/dev/null || true
    info "tg-ws-proxy удалён."
  else
    warn "tg-ws-proxy не установлен."
  fi
  if [ -f /opt/etc/opkg/feedly.conf ]; then
    echo
    if confirm_no "Удалить репозиторий feedly (/opt/etc/opkg/feedly.conf)?"; then
      rm -f /opt/etc/opkg/feedly.conf && info "  удалён: /opt/etc/opkg/feedly.conf"
    else
      info "Репозиторий feedly оставлен."
    fi
  fi
}

remove_usque_keenetic() {
  if is_installed "usque-keenetic"; then
    opkg remove --autoremove usque-keenetic 2>/dev/null || true
    info "usque-keenetic удалён."
  else
    warn "usque-keenetic не установлен."
  fi
  [ -f /opt/etc/opkg/usque-keenetic.conf ] && rm -f /opt/etc/opkg/usque-keenetic.conf && info "  удалён: /opt/etc/opkg/usque-keenetic.conf"
}

remove_keenkit() {
  if [ -f /opt/keenkit.sh ]; then
    rm -f /opt/keenkit.sh && info "  удалён: /opt/keenkit.sh"
    info "KeenKit удалён."
  else
    warn "KeenKit не найден (/opt/keenkit.sh)."
  fi
}

remove_magitrickle() {
  if is_installed "magitrickle"; then
    [ -x /opt/etc/init.d/S99magitrickle ] && /opt/etc/init.d/S99magitrickle stop 2>/dev/null || true
    opkg remove magitrickle 2>/dev/null || opkg remove --autoremove magitrickle 2>/dev/null || true
    info "magitrickle удалён."
  else
    warn "magitrickle не установлен."
  fi
  if [ -f /opt/etc/opkg/magitrickle.conf ]; then
    echo
    if confirm_no "Удалить репозиторий MagiTrickle (/opt/etc/opkg/magitrickle.conf)?"; then
      rm -f /opt/etc/opkg/magitrickle.conf && info "  удалён: /opt/etc/opkg/magitrickle.conf"
    else
      info "Репозиторий MagiTrickle оставлен."
    fi
  fi
}

remove_opera_proxy() {
  if is_installed "opera-proxy"; then
    [ -x /opt/etc/init.d/S99opera-proxy ] && /opt/etc/init.d/S99opera-proxy stop 2>/dev/null || true
    [ -x /opt/etc/init.d/S80opera-proxy ] && /opt/etc/init.d/S80opera-proxy stop 2>/dev/null || true
    opkg remove opera-proxy 2>/dev/null || opkg remove --autoremove opera-proxy 2>/dev/null || true
    info "opera-proxy удалён."
  else
    warn "opera-proxy не установлен."
  fi
  if [ -f /opt/etc/opkg/sw.ext.io.conf ]; then
    echo
    if confirm_no "Удалить репозиторий opera-proxy (/opt/etc/opkg/sw.ext.io.conf)?"; then
      rm -f /opt/etc/opkg/sw.ext.io.conf && info "  удалён: /opt/etc/opkg/sw.ext.io.conf"
    else
      info "Репозиторий opera-proxy оставлен."
    fi
  fi
}

# ---------------------------------------------------------------------------
# 7. Смена активных fake:blob
# ---------------------------------------------------------------------------
nfqws_blobs_dir() {
  case "$1" in
    1) echo "/opt/etc/nfqws" ;;
    2) echo "/opt/etc/nfqws2/blobs" ;;
  esac
}

# map_file: name|basename
# list_file: idx|section|name|basename
parse_fake_blobs() {
  local conf="$1"
  local map_file="$2"
  local list_file="$3"
  local cur_sec="?" in_quote=0 line name path base
  local seen_file="/tmp/nfqws-fakeblob-seen-$$"
  local raw_file="/tmp/nfqws-fakeblob-raw-$$"

  : > "$map_file"
  : > "$list_file"
  : > "$seen_file"
  : > "$raw_file"

  # 1) Маппинг --blob=name:path
  tr ' \t' '\n' < "$conf" 2>/dev/null | grep -E '^--blob=' | while IFS= read -r tok; do
    name=${tok#--blob=}
    name=${name%%:*}
    path=${tok#--blob=${name}:}
    path=${path#@}
    # убрать хвост кавычек/мусор от закрытия multiline
    path=$(printf '%s' "$path" | tr -d '"'"'"'')
    case "$path" in
      0x*|0X*) base="(hex)" ;;
      *) base=$(basename "$path" 2>/dev/null) ;;
    esac
    base=$(printf '%s' "$base" | tr -d '"'"'"'')
    [ -n "$name" ] && [ -n "$base" ] && printf '%s|%s\n' "$name" "$base"
  done | sort -u > "$map_file"

  # 2) Построчный обход: секция + fake:blob=
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      NFQWS_BASE_ARGS=\"*|NFQWS_ARGS=\"*|NFQWS_ARGS_QUIC=\"*|NFQWS_ARGS_UDP=\"*|NFQWS_ARGS_CUSTOM=\"*|NFQWS_EXTRA_ARGS=\"*)
        cur_sec=${line%%=*}
        in_quote=1
        case "$line" in
          *\")
            # однострочный VAR="..." — всё ещё ищем fake на этой строке
            ;;
        esac
        ;;
      NFQWS_BASE_ARGS=|NFQWS_ARGS=|NFQWS_ARGS_QUIC=|NFQWS_ARGS_UDP=|NFQWS_ARGS_CUSTOM=|NFQWS_EXTRA_ARGS=)
        cur_sec=${line%%=*}
        in_quote=0
        ;;
    esac

    if echo "$line" | grep -q 'fake:blob='; then
      echo "$line" | grep -oE 'fake:blob=[^:[:space:]"]+' 2>/dev/null | while IFS= read -r fb; do
        name=${fb#fake:blob=}
        case "$name" in
          0x*|0X*|'') continue ;;
        esac
        if grep -qxF "$name" "$seen_file" 2>/dev/null; then
          continue
        fi
        echo "$name" >> "$seen_file"
        base=$(grep -E "^${name}\|" "$map_file" 2>/dev/null | head -1 | cut -d'|' -f2)
        [ -z "$base" ] && base="(нет --blob= / встроенный)"
        printf '%s|%s|%s\n' "$cur_sec" "$name" "$base" >> "$raw_file"
      done
    fi

    if [ "$in_quote" -eq 1 ]; then
      case "$line" in
        NFQWS_*ARGS*=\"*) ;;
        *\")
          in_quote=0
          ;;
      esac
    fi
  done < "$conf"

  # Нумерация уникальных имён (первое появление)
  local idx=0
  : > "$list_file"
  while IFS='|' read -r sec name base; do
    [ -z "$name" ] && continue
    if grep -qE "\|${name}\|" "$list_file" 2>/dev/null; then
      continue
    fi
    idx=$((idx + 1))
    printf '%s|%s|%s|%s\n' "$idx" "$sec" "$name" "$base" >> "$list_file"
  done < "$raw_file"

  rm -f "$raw_file" "$seen_file"
  [ "$idx" -gt 0 ]
}

list_repo_blobs() {
  local cache="/tmp/nfqws-repo-blobs.list"
  local now age=999999
  now=$(date +%s 2>/dev/null || echo 0)
  if [ -f "$cache" ]; then
    age=$((now - $(stat -c %Y "$cache" 2>/dev/null || echo 0)))
  fi
  if [ -f "$cache" ] && [ "$age" -lt 3600 ]; then
    cat "$cache"
    return 0
  fi
  if fetch_url "${STRATEGIES_API}/blobs" 2>/dev/null | \
      grep -oE '"name":[[:space:]]*"[^"]+\.bin"' | \
      sed 's/.*"\([^"]*\.bin\)".*/\1/' | sort -u > "$cache"; then
    cat "$cache"
    return 0
  fi
  printf '%s\n' \
    ACTIVE_DISCORD_UDP.bin ACTIVE_GAME_UDP.bin \
    quic_initial_4pda_to.bin quic_initial_5ka_ru.bin quic_initial_rutube_ru.bin \
    quic_initial_steamcommunity_com.bin quic_initial_tencent_com.bin \
    quic_initial_www_google_com.bin \
    stun.bin stun2.bin \
    tls_clienthello_4pda_to.bin tls_clienthello_5ka_ru.bin \
    tls_clienthello_max_ru.bin tls_clienthello_sochi_park.bin \
    tls_clienthello_www_google_com.bin
}

menu_change_fake_blob() {
  need_nfqws_installed || return 0
  pick_nfqws_ver 0 || { warn "Отменено."; return 0; }

  local conf blobs_dir map_file list_file
  conf=$(nfqws_conf_path "$NFQWS_VER")
  blobs_dir=$(nfqws_blobs_dir "$NFQWS_VER")
  if [ ! -f "$conf" ]; then
    error "Конфиг $conf не найден."
    return 0
  fi

  map_file="/tmp/nfqws-fakeblob-map-$$"
  list_file="/tmp/nfqws-fakeblob-list-$$"

  echo
  info "Анализ конфига: $conf"
  if ! parse_fake_blobs "$conf" "$map_file" "$list_file"; then
    warn "В конфиге не найдено использований fake:blob=NAME: (кроме hex)."
    rm -f "$map_file" "$list_file"
    return 0
  fi

  echo
  printf '%s\n' "${BOLD}Сейчас в конфиге найдены следующие fake:blob:${NC}"
  local last_sec="" idx sec name base
  while IFS='|' read -r idx sec name base; do
    if [ "$sec" != "$last_sec" ]; then
      echo
      printf '%s\n' "${CYAN}${sec}${NC}"
      last_sec=$sec
    fi
    printf '  [%s] %s (%s)\n' "$idx" "$name" "$base"
  done < "$list_file"
  echo

  ask "Какой из найденных fake:blob требуется заменить? (номер / Enter = отмена): "
  read -r choice
  case "$choice" in
    ''|0|q|Q|н|Н) info "Отменено."; rm -f "$map_file" "$list_file"; return 0 ;;
  esac
  if ! echo "$choice" | grep -qE '^[0-9]+$'; then
    warn "Нужен номер."
    rm -f "$map_file" "$list_file"
    return 0
  fi

  local sel_line sel_name sel_base sel_sec
  sel_line=$(grep -E "^${choice}\|" "$list_file" | head -1)
  if [ -z "$sel_line" ]; then
    warn "Номер $choice не найден в списке."
    rm -f "$map_file" "$list_file"
    return 0
  fi
  sel_sec=$(echo "$sel_line" | cut -d'|' -f2)
  sel_name=$(echo "$sel_line" | cut -d'|' -f3)
  sel_base=$(echo "$sel_line" | cut -d'|' -f4)

  info "Выбрано: [$choice] $sel_name ($sel_base) в $sel_sec"

  echo
  printf '%s\n' "${BOLD}Доступные blob-файлы для замены (--blob=${sel_name}:...):${NC}"
  echo

  local i=1 b cand_file="/tmp/nfqws-blob-cands-$$"
  : > "$cand_file"

  if [ -d "$blobs_dir" ]; then
    for b in "$blobs_dir"/*.bin; do
      [ -f "$b" ] || continue
      printf '%s\n' "$(basename "$b")"
    done
  fi | sort -u > "/tmp/nfqws-local-blobs-$$"

  list_repo_blobs > "/tmp/nfqws-repo-blobs-$$"

  {
    cat "/tmp/nfqws-local-blobs-$$" 2>/dev/null
    cat "/tmp/nfqws-repo-blobs-$$" 2>/dev/null
  } | awk '!a[$0]++' > "$cand_file"

  i=1
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    if [ -f "${blobs_dir}/${b}" ]; then
      printf '  [%2d] %s  (локально)\n' "$i" "$b"
    else
      printf '  [%2d] %s  (из репозитория)\n' "$i" "$b"
    fi
    i=$((i + 1))
  done < "$cand_file"
  local max_cand=$((i - 1))

  if [ "$max_cand" -lt 1 ]; then
    warn "Нет доступных .bin файлов."
    rm -f "$map_file" "$list_file" "$cand_file" /tmp/nfqws-local-blobs-$$ /tmp/nfqws-repo-blobs-$$
    return 0
  fi
  echo
  ask "Номер blob-файла для замены (Enter = отмена): "
  read -r bchoice
  case "$bchoice" in
    ''|0|q|Q) info "Отменено."; rm -f "$map_file" "$list_file" "$cand_file" /tmp/nfqws-local-blobs-$$ /tmp/nfqws-repo-blobs-$$; return 0 ;;
  esac
  if ! echo "$bchoice" | grep -qE '^[0-9]+$' || [ "$bchoice" -lt 1 ] || [ "$bchoice" -gt "$max_cand" ]; then
    warn "Неверный номер."
    rm -f "$map_file" "$list_file" "$cand_file" /tmp/nfqws-local-blobs-$$ /tmp/nfqws-repo-blobs-$$
    return 0
  fi

  local new_bin new_path
  new_bin=$(sed -n "${bchoice}p" "$cand_file")
  new_path="${blobs_dir}/${new_bin}"

  if [ ! -f "$new_path" ]; then
    info "Скачивание $new_bin → $new_path ..."
    mkdir -p "$blobs_dir"
    if ! download_file "${RAW_BASE}/strategies/blobs/${new_bin}" "$new_path"; then
      error "Не удалось скачать $new_bin"
      rm -f "$map_file" "$list_file" "$cand_file" /tmp/nfqws-local-blobs-$$ /tmp/nfqws-repo-blobs-$$
      return 1
    fi
    info "Скачано."
  fi

  backup_file "$conf"

  local tmp="/tmp/nfqws-fakeblob-edit-$$.conf"
  if grep -qE -- "--blob=${sel_name}:" "$conf"; then
    sed -E "s|--blob=${sel_name}:[^[:space:]\"]*|--blob=${sel_name}:@${new_path}|g" "$conf" > "$tmp"
  else
    warn "В конфиге нет --blob=${sel_name}:... — добавляю в NFQWS_BASE_ARGS."
    local inserted=0
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$inserted" -eq 0 ]; then
        case "$line" in
          NFQWS_BASE_ARGS=\"*)
            printf '%s\n' "$line" >> "$tmp"
            case "$line" in
              *\")
                # однострочный — добавим после через sed-подобную вставку на следующей итерации сложно;
                # вставим отдельную строку с дописыванием после открытия, если multi-line
                ;;
              *)
                printf '                 --blob=%s:@%s\n' "$sel_name" "$new_path" >> "$tmp"
                inserted=1
                ;;
            esac
            continue
            ;;
          NFQWS_BASE_ARGS=\")
            printf '%s\n' "$line" >> "$tmp"
            printf '                 --blob=%s:@%s\n' "$sel_name" "$new_path" >> "$tmp"
            inserted=1
            continue
            ;;
        esac
      fi
      printf '%s\n' "$line" >> "$tmp"
    done < "$conf"
    if [ "$inserted" -eq 0 ]; then
      printf '\n# added by nfqws-menu\nNFQWS_BASE_ARGS="${NFQWS_BASE_ARGS} --blob=%s:@%s"\n' \
        "$sel_name" "$new_path" >> "$tmp"
    fi
  fi

  if [ ! -s "$tmp" ]; then
    error "Ошибка формирования нового конфига."
    rm -f "$tmp" "$map_file" "$list_file" "$cand_file" /tmp/nfqws-local-blobs-$$ /tmp/nfqws-repo-blobs-$$
    return 1
  fi

  mv "$tmp" "$conf"
  info "Готово: --blob=${sel_name}:@${new_path}"
  info "  (было: $sel_base → стало: $new_bin)"

  echo
  if confirm_yes "Перезапустить сервис nfqws${NFQWS_VER}?"; then
    service_restart "$(nfqws_init_path "$NFQWS_VER")"
    info "Сервис перезапущен."
  else
    info "Перезапуск пропущен — примените вручную."
  fi

  rm -f "$map_file" "$list_file" "$cand_file" /tmp/nfqws-local-blobs-$$ /tmp/nfqws-repo-blobs-$$
  return 0
}


menu_remove() {
  echo
  printf '%s\n' "${BOLD}Что удалить?${NC}"
  echo

  refresh_opkg_cache

  local items="" p i=1 target idx
  is_installed "nfqws-keenetic"     && items="$items nfqws-keenetic"
  is_installed "nfqws2-keenetic"    && items="$items nfqws2-keenetic"
  is_installed "nfqws-keenetic-web" && items="$items nfqws-keenetic-web"
  is_dpi_detector_installed         && items="$items dpi-detector"
  is_awg_manager_installed          && items="$items awg-manager"
  is_installed "tg-ws-proxy"        && items="$items tg-ws-proxy"
  is_installed "usque-keenetic"     && items="$items usque-keenetic"
  is_installed "magitrickle"        && items="$items magitrickle"
  is_installed "opera-proxy"        && items="$items opera-proxy"
  [ -f /opt/keenkit.sh ]            && items="$items KeenKit"

  if [ -n "$items" ]; then
    for p in $items; do
      printf "  [%d] %s\n" "$i" "$p"
      i=$((i + 1))
    done
  else
    warn "Установленных пакетов не найдено."
  fi
  echo "  [a] Удалить все пакеты NFQWS"
  echo "  [b] Удалить резервные копии (.bak.* / *-opkg)"
  echo "  [0] Назад"
  echo
  ask "Выбор (номер / a / b / 0): "
  read -r choice

  case "$choice" in
    0|"") return ;;
    b|B|б|Б) remove_backups ;;
    a|A|а|А)
      if confirm_no "Точно удалить все пакеты NFQWS (и dpi-detector, если есть)?"; then
        opkg remove --autoremove nfqws-keenetic-web nfqws2-keenetic nfqws-keenetic 2>/dev/null || true
        remove_dpi_detector
        info "Удаление завершено."
      fi
      ;;
    *)
      idx=1; target=""
      for p in $items; do
        [ "$idx" = "$choice" ] && { target="$p"; break; }
        idx=$((idx + 1))
      done
      [ -z "$target" ] && { warn "Неверный выбор"; return; }
      confirm_no "Удалить $target?" || return
      case "$target" in
        dpi-detector)  remove_dpi_detector ;;
        awg-manager)   remove_awg_manager ;;
        tg-ws-proxy)   remove_tg_ws_proxy ;;
        usque-keenetic) remove_usque_keenetic ;;
        magitrickle)   remove_magitrickle ;;
        opera-proxy)   remove_opera_proxy ;;
        KeenKit)       remove_keenkit ;;
        *)
          opkg remove --autoremove "$target"
          info "$target удалён."
          ;;
      esac
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Главное меню
# ---------------------------------------------------------------------------
main_menu() {
  while true; do
    clear 2>/dev/null || true
    echo
    printf '%s\n' "${BOLD}${BLUE}========================================${NC}"
    printf '%s\n' "${BOLD}${BLUE}     NFQWS-MENU (Entware)  v${SCRIPT_VERSION}${NC}"
    printf '%s\n' "${BOLD}${BLUE}========================================${NC}"
    echo
    detect_arch
    show_installed
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_COMPONENTS}${NC}"
    echo "      1.  $LBL_1"
    echo "      2.  $LBL_2"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_STRATEGIES}${NC}"
    echo "      3.  $LBL_3"
    echo "      4.  $LBL_4"
    echo "      5.  $LBL_7"
    echo "      6.  $LBL_5"
    echo "      7.  $LBL_7F"
    echo
    echo "      9.  $LBL_6"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_UTILS}${NC}"
    echo "      10. dpi-detector"
    echo "      11. awg-manager"
    echo "      12. KeenKit"
    echo "      13. TG WS Proxy Go"
    echo "      14. usque-keenetic"
    echo "      15. MagiTrickle"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_REMOVE}${NC}"
    echo "      77. $LBL_77"
    echo "      88. $LBL_88"
    echo
    echo "      99. $LBL_99"
    echo "      00. $LBL_00"
    echo
    ask "$LBL_PROMPT"
    read -r choice

    # || true — при set -e любой return 1 из пункта не должен завершать скрипт
    case "$choice" in
      1)  menu_install_nfqws || true ;;
      2)  install_web || true ;;
      3)  menu_strategy || true ;;
      4)  update_ipset_list || true ;;
      5)  update_rkn_list || true ;;
      6)  menu_dot_doh || true ;;
      7)  menu_change_fake_blob || true ;;
      9)  menu_dns_manage || true ;;
      10) menu_dpi_detector || true ;;
      11) menu_awg_manager || true ;;
      12) menu_keenkit || true ;;
      13) menu_tg_ws_proxy || true ;;
      14) menu_usque_keenetic || true ;;
      15) menu_magitrickle || true ;;
      77) menu_change_language; continue ;;
      88) menu_remove || true ;;
      99) update_self || true ;;
      00|0|"")
        info "$LBL_00."
        exit 0
        ;;
      *) warn "Invalid menu item" ;;
    esac

    echo
    ask "$LBL_BACK"
    read -r _
  done
}

# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------
case "$0" in
  /*) SCRIPT_PATH="$0" ;;
  *)  SCRIPT_PATH="$(pwd)/$0" ;;
esac
if [ ! -f "$SCRIPT_PATH" ]; then
  for a in "$0" "$@"; do
    case "$a" in
      *.sh)
        if [ -f "$a" ]; then
          case "$a" in /*) SCRIPT_PATH="$a" ;; *) SCRIPT_PATH="$(pwd)/$a" ;; esac
          break
        fi
        ;;
    esac
  done
fi
export SCRIPT_PATH

ensure_menu_symlink() {
  local target="/opt/nfqws-menu.sh" link="/opt/bin/menu" cur
  if [ ! -f "$target" ] && [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    case "$SCRIPT_PATH" in /opt/*) target="$SCRIPT_PATH" ;; esac
  fi
  [ -f "$target" ] || return 0
  [ -d /opt/bin ] || mkdir -p /opt/bin 2>/dev/null || return 0
  if [ -L "$link" ]; then
    cur=$(readlink "$link" 2>/dev/null || true)
    [ "$cur" = "$target" ] && return 0
  fi
  [ -e "$link" ] && [ ! -L "$link" ] && return 0
  ln -sf "$target" "$link" 2>/dev/null || true
  [ -L "$link" ] && chmod +x "$link" 2>/dev/null || true
}

ensure_menu_symlink

if ! command -v opkg >/dev/null 2>&1; then
  error "opkg не найден. Скрипт предназначен для Entware (Keenetic/Netcraze)."
  exit 1
fi

main_menu
