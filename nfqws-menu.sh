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

SCRIPT_VERSION="0.5.10"

REPO_URL="https://github.com/rndnaame/nfqws-menu"
RAW_BASE="https://raw.githubusercontent.com/rndnaame/nfqws-menu/main"
STRATEGIES_API="https://api.github.com/repos/rndnaame/nfqws-menu/contents/strategies"

# Цвета через printf (работает в busybox ash / Entware)
# Переменные содержат реальный ESC-символ, а не строку \033
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
# Язык / кодировка UI
# Файл предпочтения: /opt/etc/nfqws-menu.lang  (ru|en)
# Env: NFQWS_MENU_UTF8=1|0  или  NFQWS_MENU_LANG=ru|en
# Авто: SSH → ru (UTF-8), Telnet → en (ASCII)
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
    echo "ru"
    return
  fi
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) echo "ru"; return ;;
  esac
  echo "en"
}

ui_apply_lang() {
  # $1 = ru|en
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
  # мгновенное переключение ru <-> en без запросов
  if [ "$UI_LANG" = "ru" ]; then
    ui_apply_lang "en"
  else
    ui_apply_lang "ru"
  fi
  mkdir -p /opt/etc 2>/dev/null || true
  echo "$UI_LANG" > "$UI_LANG_FILE" 2>/dev/null || true
  return 0
}

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[x]${NC} $*"; }
ask()   { printf '%s' "${CYAN}[?]${NC} $*"; }

# ---------------------------------------------------------------------------
# Определение архитектуры
# ---------------------------------------------------------------------------
ARCH=""
ARCH_RAW=""

detect_arch() {
  # кэш: не дергать opkg на каждом redraw меню
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
# Проверка установленных пакетов
# ---------------------------------------------------------------------------
# Кэши на одну отрисовку меню
OPKG_INSTALLED_CACHE=""
PROC_CACHE=""
PORT90_CACHE=""

refresh_opkg_cache() {
  OPKG_INSTALLED_CACHE=$(opkg list-installed 2>/dev/null)
}

# Один снимок процессов на всю отрисовку (вместо кучи pidof/pgrep)
refresh_proc_cache() {
  PROC_CACHE=$(ps w 2>/dev/null || ps 2>/dev/null || true)
}

is_installed() {
  [ -n "$OPKG_INSTALLED_CACHE" ] || refresh_opkg_cache
  printf '%s\n' "$OPKG_INSTALLED_CACHE" | grep -q "^$1 "
}

pkg_version() {
  # формат list-installed: "name - version" → только version
  [ -n "$OPKG_INSTALLED_CACHE" ] || refresh_opkg_cache
  printf '%s\n' "$OPKG_INSTALLED_CACHE" | grep "^$1 - " | head -1 | sed "s/^$1 - //"
}

# Быстрая проверка порта (без nc)
port_is_open() {
  local port="$1"
  if [ "$port" = "90" ] && [ -n "$PORT90_CACHE" ]; then
    [ "$PORT90_CACHE" = "1" ]
    return $?
  fi
  local ok=1
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]" && ok=0
  elif command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]" && ok=0
  elif [ -r /proc/net/tcp ]; then
    local hex
    hex=$(printf '%04X' "$port")
    grep -q ":${hex} " /proc/net/tcp 2>/dev/null && ok=0
  fi
  if [ "$port" = "90" ]; then
    if [ "$ok" -eq 0 ]; then PORT90_CACHE=1; else PORT90_CACHE=0; fi
  fi
  return "$ok"
}

# Проверка процесса по кэшу ps (подстрока имени)
proc_running() {
  local name="$1"
  [ -n "$PROC_CACHE" ] || refresh_proc_cache
  printf '%s\n' "$PROC_CACHE" | grep -q "$name"
}

service_status() {
  # $1 = тип: nfqws | nfqws2 | web
  case "$1" in
    nfqws)
      if proc_running nfqws; then echo "запущен"; else echo "остановлен"; fi
      ;;
    nfqws2)
      if proc_running nfqws2; then echo "запущен"; else echo "остановлен"; fi
      ;;
    web)
      if port_is_open 90; then
        echo "запущен (:90)"
      elif proc_running lighttpd; then
        echo "запущен"
      else
        echo "остановлен"
      fi
      ;;
    *)
      echo "неизвестно"
      ;;
  esac
}

print_pkg_info() {
  local name="$1"
  local kind="$2"
  if is_installed "$name"; then
    local ver status mark=""
    ver=$(pkg_version "$name")
    [ -z "$ver" ] && ver="?"
    status=$(service_status "$kind")
    case "$status" in
      запущен*) mark="$RUN_MARK" ;;
    esac
    printf '  %s%-22s%s %s%s\n' "$GREEN" "$name" "$NC" "$ver" "$mark"
    return 0
  fi
  return 1
}

print_tool_info() {
  # $1 = отображаемое имя, $2 = доп.инфо (версия/путь/статус)
  printf '  %s%-22s%s %s\n' "$GREEN" "$1" "$NC" "$2"
}

show_installed() {
  local shown=0
  # снимки на всю отрисовку: opkg + ps (без повторных вызовов)
  PORT90_CACHE=""
  refresh_opkg_cache
  refresh_proc_cache

  echo
  printf '%s\n' "${BOLD}${LBL_INSTALLED}${NC}"

  print_pkg_info "nfqws-keenetic"     "nfqws"  && shown=1
  print_pkg_info "nfqws2-keenetic"    "nfqws2" && shown=1
  print_pkg_info "nfqws-keenetic-web" "web"    && shown=1

  if [ -x /opt/bin/dpi-detector ] || command -v dpi-detector >/dev/null 2>&1; then
    local dpi_bin="" dpi_ver=""
    if [ -x /opt/bin/dpi-detector ]; then
      dpi_bin="/opt/bin/dpi-detector"
    else
      dpi_bin=$(command -v dpi-detector)
    fi
    # --version обычно быстрый; один вызов
    dpi_ver=$("$dpi_bin" --version 2>/dev/null | head -1 | sed -n 's/.*dpi-detector[[:space:]]\+\([^[:space:]]*\).*/\1/p')
    if [ -n "$dpi_ver" ]; then
      print_tool_info "dpi-detector" "$dpi_ver"
    else
      print_tool_info "dpi-detector" "ok"
    fi
    shown=1
  fi

  if is_installed "awg-manager" || [ -d /opt/etc/awg-manager ]; then
    local awg_name="awg-manager"
    local awg_info="ok"
    # наличие sing-box — метка в имени, без запуска бинарника
    if [ -x /opt/etc/awg-manager/singbox/sing-box ] || [ -f /opt/etc/awg-manager/singbox/sing-box ]; then
      awg_name="awg-manager [+SB]"
    fi
    if is_installed "awg-manager"; then
      local av
      av=$(pkg_version awg-manager)
      [ -n "$av" ] && awg_info="$av"
    fi
    print_tool_info "$awg_name" "$awg_info"
    shown=1
  fi

  if [ -f /opt/keenkit.sh ]; then
    local kk_ver=""
    kk_ver=$(grep -E '^SCRIPT_VERSION=' /opt/keenkit.sh 2>/dev/null | head -1 | sed -n 's/^SCRIPT_VERSION="\([^"]*\)".*/\1/p')
    [ -z "$kk_ver" ] && kk_ver=$(grep -E "^SCRIPT_VERSION='" /opt/keenkit.sh 2>/dev/null | head -1 | sed -n "s/^SCRIPT_VERSION='\\([^']*\\)'.*/\\1/p")
    if [ -n "$kk_ver" ]; then
      print_tool_info "KeenKit" "$kk_ver"
    else
      print_tool_info "KeenKit" "ok"
    fi
    shown=1
  fi

  # Прочие сервисы с init-скриптами в /opt/etc/init.d/
  # (не дублируем уже показанные nfqws / nfqws2 / lighttpd)
  if [ -d /opt/etc/init.d ]; then
    local f base svc ver
    for f in /opt/etc/init.d/S[0-9][0-9]*; do
      [ -f "$f" ] || continue
      [ -x "$f" ] || continue
      base=$(basename "$f")
      # S51nfqws -> nfqws, S99awg-manager -> awg-manager
      svc=$(echo "$base" | sed 's/^S[0-9][0-9]//')
      [ -n "$svc" ] || continue
      case "$svc" in
        nfqws|nfqws2|lighttpd)
          continue
          ;;
      esac
      # awg-manager уже выведен отдельной строкой выше
      if [ "$svc" = "awg-manager" ]; then
        if is_installed "awg-manager" || [ -d /opt/etc/awg-manager ]; then
          continue
        fi
      fi

      ver=$(pkg_version "$svc")
      if proc_running "$svc"; then
        if [ -n "$ver" ]; then
          printf '  %s%-22s%s %s%s\n' "$GREEN" "$svc" "$NC" "$ver" "$RUN_MARK"
        else
          printf '  %s%-22s%s%s\n' "$GREEN" "$svc" "$NC" "$RUN_MARK"
        fi
      else
        if [ -n "$ver" ]; then
          printf '  %s%-22s%s %s\n' "$GREEN" "$svc" "$NC" "$ver"
        else
          printf '  %s%-22s%s\n' "$GREEN" "$svc" "$NC"
        fi
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
# Зависимости
# ---------------------------------------------------------------------------
install_deps() {
  info "Установка зависимостей..."
  opkg update
  opkg install ca-certificates wget-ssl 2>/dev/null || true
  opkg remove wget-nossl 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1. Установка NFQWS / NFQWS2
# ---------------------------------------------------------------------------
install_nfqws1() {
  info "Установка nfqws-keenetic (версия 1)..."
  install_deps
  mkdir -p /opt/etc/opkg
  echo "src/gz nfqws-keenetic https://nfqws.github.io/nfqws-keenetic/$ARCH" > /opt/etc/opkg/nfqws-keenetic.conf
  opkg update
  opkg install nfqws-keenetic
  info "nfqws-keenetic установлен."
  ask_web_install
}

install_nfqws2() {
  info "Установка nfqws2-keenetic (версия 2)..."
  if is_installed "nfqws-keenetic"; then
    warn "Обнаружен nfqws-keenetic. Рекомендуется удалить его перед установкой nfqws2."
    ask "Удалить nfqws-keenetic и веб-интерфейс? [y/N]: "
    read -r ans
    case "$ans" in
      y|Y|д|Д) opkg remove --autoremove nfqws-keenetic-web nfqws-keenetic 2>/dev/null || true ;;
    esac
  fi
  install_deps
  mkdir -p /opt/etc/opkg
  # Универсальный репозиторий (рекомендуется официальной документацией)
  echo "src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/$ARCH" > /opt/etc/opkg/nfqws2-keenetic.conf
  opkg update
  opkg install nfqws2-keenetic
  info "nfqws2-keenetic установлен."
  ask_web_install
}

ask_web_install() {
  echo
  ask "Установить веб-интерфейс nfqws-keenetic-web? [y/N]: "
  read -r ans
  case "$ans" in
    y|Y|д|Д) install_web ;;
  esac
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

# ---------------------------------------------------------------------------
# 2. Установка веб-интерфейса
# ---------------------------------------------------------------------------
install_web() {
  info "Установка nfqws-keenetic-web..."
  install_deps
  mkdir -p /opt/etc/opkg
  echo "src/gz nfqws-keenetic-web https://nfqws.github.io/nfqws-keenetic-web/all" > /opt/etc/opkg/nfqws-keenetic-web.conf
  opkg update
  opkg install nfqws-keenetic-web
  info "Веб-интерфейс установлен."
  info "Адрес: http://<IP-роутера>:90"
  info "Логин/пароль — учётные данные Entware (по умолчанию root / keenetic)"
}

# ---------------------------------------------------------------------------
# 3. Установка стратегии
# ---------------------------------------------------------------------------
# Получить список .conf файлов из каталога strategies/nfqws1 или nfqws2 через GitHub API
list_strategies() {
  local ver="$1"   # nfqws1 или nfqws2
  local url="${STRATEGIES_API}/${ver}"
  # Используем wget/curl; выводим только имена .conf
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" 2>/dev/null | grep -o '"name": *"[^"]*\.conf"' | sed 's/.*"\([^"]*\)".*/\1/'
  else
    wget -qO- "$url" 2>/dev/null | grep -o '"name": *"[^"]*\.conf"' | sed 's/.*"\([^"]*\)".*/\1/'
  fi
}

# Определить интерфейс провайдера из default route
detect_isp_interface() {
  local iface=""
  # ip route (предпочтительно)
  if command -v ip >/dev/null 2>&1; then
    iface=$(ip route 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  fi
  # fallback: route
  if [ -z "$iface" ]; then
    iface=$(route -n 2>/dev/null | awk '/^0\.0\.0\.0/ {print $8; exit}')
  fi
  if [ -z "$iface" ]; then
    iface=$(route 2>/dev/null | awk '/^default/ {print $NF; exit}')
  fi
  echo "$iface"
}

# Установить ISP_INTERFACE в конфиге
fix_isp_interface() {
  local conf="$1"
  local detected current
  detected=$(detect_isp_interface)
  if [ -z "$detected" ]; then
    warn "Не удалось определить интерфейс провайдера (route/ip route)."
    return 1
  fi
  current=$(grep -E '^ISP_INTERFACE=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
  info "Интерфейс провайдера (default route): $detected"
  if [ -n "$current" ]; then
    info "В конфиге сейчас: ISP_INTERFACE=\"$current\""
  fi
  if [ "$current" = "$detected" ]; then
    info "ISP_INTERFACE уже совпадает с интерфейсом провайдера."
    return 0
  fi
  ask "Установить ISP_INTERFACE=\"$detected\"? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) warn "ISP_INTERFACE не изменён."; return 0 ;;
  esac
  if grep -qE '^ISP_INTERFACE=' "$conf" 2>/dev/null; then
    sed -i "s|^ISP_INTERFACE=.*|ISP_INTERFACE=\"$detected\"|" "$conf"
  else
    # вставить в начало после возможных комментариев
    printf 'ISP_INTERFACE="%s"\n' "$detected" | cat - "$conf" > "${conf}.new" && mv "${conf}.new" "$conf"
  fi
  info "ISP_INTERFACE=\"$detected\" записан в $conf"
}

# Извлечь пути к blob-файлам из конфига
# Учитывает:
#   --blob=name:@/path/to/file.bin
#   --dpi-desync-fake-tls=/path/file.bin
#   --dpi-desync-fake-quic=/path/file.bin
#   любые абсолютные пути *.bin в значении переменных
extract_blob_paths() {
  local conf="$1"
  grep -vE '^[[:space:]]*#' "$conf" 2>/dev/null | \
  tr ' \t' '\n' | \
  sed -n \
    -e 's/.*@\(\/[^[:space:]"]*\.bin\).*/\1/p' \
    -e 's/.*=\(\/[^[:space:]"]*\.bin\).*/\1/p' | \
  sort -u
}

# Извлечь пути к .list из конфига
# --hostlist=, --hostlist-auto=, --hostlist-exclude=, --ipset=, --ipset-exclude=
# и любые абсолютные пути *.list
extract_list_paths() {
  local conf="$1"
  grep -vE '^[[:space:]]*#' "$conf" 2>/dev/null | \
  tr ' \t' '\n' | \
  sed -n \
    -e 's/.*[=:]\(\/[^[:space:]"]*\.list\).*/\1/p' \
    -e 's/^\(\/[^[:space:]"]*\.list\)$/\1/p' | \
  sort -u
}

download_file() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$url" -o "$dest"
  else
    wget -qO "$dest" --no-cache "$url" 2>/dev/null || wget -qO "$dest" "$url"
  fi
}

# Проверка blobs, реально используемых в конфиге
check_blobs() {
  local ver="$1"
  local conf="$2"
  local missing=0
  local paths path name
  local missing_list=""

  if [ ! -f "$conf" ]; then
    warn "Конфиг $conf не найден — проверка blobs пропущена."
    return 1
  fi

  paths=$(extract_blob_paths "$conf")
  if [ -z "$paths" ]; then
    info "В конфиге нет ссылок на .bin blobs — проверка не требуется."
    return 0
  fi

  info "Blobs, указанные в конфиге:"
  for path in $paths; do
    if [ -f "$path" ]; then
      info "  OK  $path"
    else
      warn "  нет $path"
      missing=1
      missing_list="$missing_list $path"
    fi
  done

  if [ "$missing" -eq 0 ]; then
    info "Все используемые blobs на месте."
    return 0
  fi

  warn "Часть blobs отсутствует. Стратегии с fake-пакетами могут не работать."
  ask "Скачать отсутствующие blobs из strategies/blobs/? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) return 0 ;;
  esac

  for path in $missing_list; do
    name=$(basename "$path")
    info "Скачивание $name → $path"
    if download_file "${RAW_BASE}/strategies/blobs/${name}" "$path"; then
      info "  готово"
    else
      warn "  не удалось скачать $name (нет в репозитории?)"
    fi
  done
}

# Проверка .list, реально используемых в конфиге
check_lists() {
  local ver="$1"
  local conf="$2"
  local missing=0
  local paths path name
  local missing_list=""

  if [ ! -f "$conf" ]; then
    warn "Конфиг $conf не найден — проверка lists пропущена."
    return 1
  fi

  paths=$(extract_list_paths "$conf")
  if [ -z "$paths" ]; then
    info "В конфиге нет ссылок на .list — проверка не требуется."
    return 0
  fi

  info "Lists, указанные в конфиге:"
  for path in $paths; do
    if [ -f "$path" ]; then
      info "  OK  $path"
    else
      warn "  нет $path"
      missing=1
      missing_list="$missing_list $path"
    fi
  done

  if [ "$missing" -eq 0 ]; then
    info "Все используемые lists на месте."
    return 0
  fi

  warn "Часть lists отсутствует."
  ask "Скачать/создать отсутствующие lists? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) return 0 ;;
  esac

  for path in $missing_list; do
    name=$(basename "$path")
    mkdir -p "$(dirname "$path")"
    # auto.list наполняется демоном — достаточно создать пустой файл
    case "$name" in
      auto.list)
        touch "$path"
        info "  создан пустой $path (заполняется демоном)"
        ;;
      *)
        info "Скачивание $name → $path"
        if download_file "${RAW_BASE}/strategies/lists/${name}" "$path"; then
          info "  готово"
        else
          # если в репозитории нет — создать пустой, чтобы сервис не падал
          touch "$path"
          warn "  нет в репозитории — создан пустой $path"
        fi
        ;;
    esac
  done
}

# Обновление lists из репозитория (принудительно все)
update_lists() {
  local ver="$1"
  local dest_dir base name
  if [ "$ver" = "1" ]; then
    dest_dir="/opt/etc/nfqws"
  else
    dest_dir="/opt/etc/nfqws2/lists"
  fi
  base="${RAW_BASE}/strategies/lists"
  mkdir -p "$dest_dir"

  for name in user.list exclude.list ipset.list ipset_exclude.list; do
    info "Обновление $name ..."
    if download_file "${base}/${name}" "${dest_dir}/${name}"; then
      info "  → ${dest_dir}/${name}"
    else
      warn "  не удалось скачать $name (пропуск)"
    fi
  done
  # auto.list не трогаем — наполняется демоном
  info "Списки обновлены (auto.list не изменялся)."
}

apply_strategy() {
  local ver="$1"      # 1 или 2
  local conf_name="$2"
  local conf_path conf_dest

  if [ "$ver" = "1" ]; then
    conf_dest="/opt/etc/nfqws/nfqws.conf"
    if [ "$conf_name" = "default" ]; then
      conf_path="https://raw.githubusercontent.com/nfqws/nfqws-keenetic/master/etc/nfqws/nfqws.conf"
    else
      conf_path="${RAW_BASE}/strategies/nfqws1/${conf_name}"
    fi
  else
    conf_dest="/opt/etc/nfqws2/nfqws2.conf"
    if [ "$conf_name" = "default" ]; then
      conf_path="https://raw.githubusercontent.com/nfqws/nfqws2-keenetic/master/etc/nfqws2/nfqws2.conf"
    else
      conf_path="${RAW_BASE}/strategies/nfqws2/${conf_name}"
    fi
  fi

  if [ ! -f "$conf_dest" ]; then
    error "Конфиг $conf_dest не найден. Сначала установите соответствующий пакет."
    return 1
  fi

  info "Скачивание стратегии: $conf_name"
  info "URL: $conf_path"
  local tmp="/tmp/nfqws-strategy-$$.conf"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$conf_path" -o "$tmp" || { error "Не удалось скачать $conf_path"; return 1; }
  else
    wget -qO "$tmp" "$conf_path" || { error "Не удалось скачать $conf_path"; return 1; }
  fi

  # Бэкап текущего конфига
  cp -a "$conf_dest" "${conf_dest}.bak.$(date +%Y%m%d%H%M%S)"
  info "Создан бэкап: ${conf_dest}.bak.*"

  # Если скачанный файл — полный конфиг, заменяем; иначе подставляем только стратегию
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
  ask "Принудительно обновить все lists (user/exclude/ipset) из репозитория? [y/N]: "
  read -r ans
  case "$ans" in
    y|Y|д|Д) update_lists "$ver" ;;
    *) info "Принудительное обновление lists пропущено." ;;
  esac

  # Перезапуск сервиса
  echo
  if [ "$ver" = "1" ]; then
    /opt/etc/init.d/S51nfqws restart 2>/dev/null || true
  else
    /opt/etc/init.d/S51nfqws2 restart 2>/dev/null || true
  fi
  info "Сервис перезапущен."
}

# Определить текущую стратегию по маркеру в конфиге
# Ищем строку вида:  #  general (ALT13).bat  ->  nfqws2
# Возвращаем имя в нижнем регистре без расширения (alt13)
detect_current_strategy() {
  local conf="$1"
  [ -f "$conf" ] || return 0
  # взять содержимое скобок из строк с general
  grep -iE 'general[[:space:]]*\(' "$conf" 2>/dev/null | \
    sed -n 's/.*(\([^)]*\)).*/\1/p' | \
    head -1 | \
    tr '[:upper:]' '[:lower:]' | \
    tr -d '[:space:]'
}

menu_strategy() {
  local has1=0 has2=0
  is_installed "nfqws-keenetic"  && has1=1
  is_installed "nfqws2-keenetic" && has2=1

  if [ "$has1" -eq 0 ] && [ "$has2" -eq 0 ]; then
    warn "Ни одна версия NFQWS не установлена."
    ask "Перейти к установке? [Y/n]: "
    read -r ans
    case "$ans" in
      n|N|н|Н) return ;;
      *) menu_install_nfqws; return ;;
    esac
  fi

  local ver=""
  if [ "$has1" -eq 1 ] && [ "$has2" -eq 1 ]; then
    echo
    echo "Установлены обе версии. Для какой ставим стратегию?"
    echo "  1) nfqws-keenetic  (v1)"
    echo "  2) nfqws2-keenetic (v2)"
    ask "Выбор [1/2]: "
    read -r c
    case "$c" in
      1) ver=1 ;;
      2) ver=2 ;;
      *) return ;;
    esac
  elif [ "$has1" -eq 1 ]; then
    ver=1
  else
    ver=2
  fi

  local conf_dest
  if [ "$ver" = "1" ]; then
    conf_dest="/opt/etc/nfqws/nfqws.conf"
  else
    conf_dest="/opt/etc/nfqws2/nfqws2.conf"
  fi

  local current_id
  current_id=$(detect_current_strategy "$conf_dest")
  if [ -n "$current_id" ]; then
    info "Текущая стратегия в конфиге: $current_id"
  fi

  local dir="nfqws${ver}"
  echo
  info "Доступные стратегии ($dir):"
  local list
  list=$(list_strategies "$dir")

  # Пункт 1 всегда — default (стандартный конфиг из официального репозитория)
  local i=1
  local files="default"
  if [ -z "$current_id" ]; then
    printf "  %s%2d) default  (стандартная из репозитория nfqws)  <-- текущая?%s\n" "$GREEN$BOLD" "$i" "$NC"
  else
    printf "  %2d) default  (стандартная из репозитория nfqws)\n" "$i"
  fi
  i=2

  local f base
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

  local idx=1
  local selected=""
  for f in $files; do
    if [ "$idx" = "$num" ]; then
      selected="$f"
      break
    fi
    idx=$((idx + 1))
  done

  if [ -z "$selected" ]; then
    warn "Неверный номер"
    return
  fi

  apply_strategy "$ver" "$selected"
}

# ---------------------------------------------------------------------------
# 4. Обновление IPSet List
# ---------------------------------------------------------------------------
IPSET_SOURCE_URL="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt"

update_ipset_list() {
  local has1=0 has2=0
  is_installed "nfqws-keenetic"  && has1=1
  is_installed "nfqws2-keenetic" && has2=1

  if [ "$has1" -eq 0 ] && [ "$has2" -eq 0 ]; then
    warn "Ни одна версия NFQWS не установлена."
    ask "Перейти к установке? [Y/n]: "
    read -r ans
    case "$ans" in
      n|N|н|Н) return ;;
      *) menu_install_nfqws; return ;;
    esac
  fi

  local ver=""
  if [ "$has1" -eq 1 ] && [ "$has2" -eq 1 ]; then
    echo
    echo "Установлены обе версии. Для какой обновить ipset.list?"
    echo "  1) nfqws-keenetic  (v1)  → /opt/etc/nfqws/ipset.list"
    echo "  2) nfqws2-keenetic (v2)  → /opt/etc/nfqws2/lists/ipset.list"
    echo "  a) Обе"
    ask "Выбор [1/2/a]: "
    read -r c
    case "$c" in
      1) ver=1 ;;
      2) ver=2 ;;
      a|A|а|А) ver=both ;;
      *) return ;;
    esac
  elif [ "$has1" -eq 1 ]; then
    ver=1
  else
    ver=2
  fi

  local tmp="/tmp/nfqws-ipset-$$.txt"
  info "Скачивание IPSet с Flowseal/zapret-discord-youtube ..."
  info "URL: $IPSET_SOURCE_URL"
  if ! download_file "$IPSET_SOURCE_URL" "$tmp"; then
    error "Не удалось скачать список."
    rm -f "$tmp"
    return 1
  fi

  # убрать пустые строки и комментарии в начале, оставить IP/CIDR
  local cleaned="/tmp/nfqws-ipset-clean-$$.txt"
  grep -vE '^[[:space:]]*(#|;|$)' "$tmp" | sed 's/[[:space:]]*$//' | grep -vE '^$' > "$cleaned" || true
  local count
  count=$(wc -l < "$cleaned" 2>/dev/null | tr -d ' ')
  if [ -z "$count" ] || [ "$count" = "0" ]; then
    error "Скачанный файл пуст или не содержит записей."
    rm -f "$tmp" "$cleaned"
    return 1
  fi
  info "Записей в списке: $count"

  write_ipset() {
    local dest="$1"
    local dir
    dir=$(dirname "$dest")
    mkdir -p "$dir"
    if [ -f "$dest" ]; then
      cp -a "$dest" "${dest}.bak.$(date +%Y%m%d%H%M%S)"
      info "Бэкап: ${dest}.bak.*"
    fi
    cp "$cleaned" "$dest"
    info "Записано: $dest ($count строк)"
  }

  case "$ver" in
    1)
      write_ipset "/opt/etc/nfqws/ipset.list"
      /opt/etc/init.d/S51nfqws restart 2>/dev/null || true
      info "Сервис nfqws перезапущен."
      ;;
    2)
      write_ipset "/opt/etc/nfqws2/lists/ipset.list"
      /opt/etc/init.d/S51nfqws2 restart 2>/dev/null || true
      info "Сервис nfqws2 перезапущен."
      ;;
    both)
      write_ipset "/opt/etc/nfqws/ipset.list"
      write_ipset "/opt/etc/nfqws2/lists/ipset.list"
      /opt/etc/init.d/S51nfqws restart 2>/dev/null || true
      /opt/etc/init.d/S51nfqws2 restart 2>/dev/null || true
      info "Сервисы перезапущены."
      ;;
  esac

  rm -f "$tmp" "$cleaned"
}

# ---------------------------------------------------------------------------
# 5. Обход блокировки DoT/DoH
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

menu_dot_doh() {
  if ! is_installed "nfqws2-keenetic"; then
    error "Пункт доступен только при установленном nfqws2-keenetic."
    return 1
  fi

  local conf="/opt/etc/nfqws2/nfqws2.conf"
  if [ ! -f "$conf" ]; then
    error "Конфиг $conf не найден."
    return 1
  fi

  echo
  ask "Добавить в NFQWS_ARGS_CUSTOM стратегию обхода блокировки DoT/DoH публичных DNS? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) info "Отменено."; return 0 ;;
  esac

  if grep -qE '#DNS|dot\.pub,doh\.pub' "$conf" 2>/dev/null; then
    warn "Похоже, стратегия DoT/DoH уже присутствует в конфиге."
    ask "Добавить повторно? [y/N]: "
    read -r ans
    case "$ans" in
      y|Y|д|Д) ;;
      *) info "Отменено."; return 0 ;;
    esac
  fi

  cp -a "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
  info "Бэкап: ${conf}.bak.*"

  local tmp="/tmp/nfqws2-conf-$$.tmp"
  local strat_tmp="/tmp/nfqws2-dot-$$.txt"
  # стратегия + перевод строки перед ней (и --new если в блоке уже есть контент)
  printf '%s\n' "$DOT_DOH_STRATEGY" > "$strat_tmp"

  # Вставка перед закрывающей " внутри NFQWS_ARGS_CUSTOM=" ... "
  # Форматы:
  #   NFQWS_ARGS_CUSTOM=""
  #   NFQWS_ARGS_CUSTOM="однострочный контент"
  #   NFQWS_ARGS_CUSTOM="
  #     многострочный
  #   "
  #   NFQWS_ARGS_CUSTOM="--filter-tcp=443
  #   --filter-l7=tls
  #   ...repeats=4"
  local found=0
  local in_block=0
  local has_content=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" -eq 0 ]; then
      case "$line" in
        NFQWS_ARGS_CUSTOM=\"\")
          # пустой однострочный
          found=1
          printf 'NFQWS_ARGS_CUSTOM="\n' >> "$tmp"
          cat "$strat_tmp" >> "$tmp"
          printf '"\n' >> "$tmp"
          ;;
        NFQWS_ARGS_CUSTOM=\")
          # открывающая кавычка одна на строке
          found=1
          in_block=1
          printf '%s\n' "$line" >> "$tmp"
          ;;
        NFQWS_ARGS_CUSTOM=\"*\")
          # закрыто на этой же строке: NFQWS_ARGS_CUSTOM="..."
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
          # открыто с контентом, кавычка НЕ закрыта на этой строке
          # NFQWS_ARGS_CUSTOM="--filter-tcp=443
          found=1
          in_block=1
          has_content=1
          printf '%s\n' "$line" >> "$tmp"
          ;;
        *)
          printf '%s\n' "$line" >> "$tmp"
          ;;
      esac
    else
      # внутри многострочного NFQWS_ARGS_CUSTOM
      # закрытие: строка только "  ИЛИ  строка контента, оканчивающаяся на "
      case "$line" in
        \"|[[:space:]]*\")
          if [ "$has_content" -eq 1 ]; then
            printf -- '--new\n' >> "$tmp"
          fi
          cat "$strat_tmp" >> "$tmp"
          printf '%s\n' "$line" >> "$tmp"
          in_block=0
          ;;
        *\")
          # контент + закрывающая кавычка в конце строки
          local body
          body=${line%\"}
          if [ -n "$(echo "$body" | tr -d '[:space:]\\')" ]; then
            printf '%s\n' "$body" >> "$tmp"
            has_content=1
          fi
          if [ "$has_content" -eq 1 ]; then
            printf -- '--new\n' >> "$tmp"
          fi
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
  info "Стратегия DoT/DoH добавлена в NFQWS_ARGS_CUSTOM (перед закрывающей \")."

  # Порт 853 (DoT) должен быть в TCP_PORTS и UDP_PORTS
  ensure_port_in_var() {
    local conf_file="$1"
    local var="$2"   # TCP_PORTS или UDP_PORTS
    local port="$3"  # 853
    local line val new_val

    line=$(grep -E "^${var}=" "$conf_file" 2>/dev/null | head -1)
    if [ -z "$line" ]; then
      # переменной нет — создать с нужным портом
      printf '%s=%s\n' "$var" "$port" >> "$conf_file"
      info "${var}: создано со значением $port"
      return 0
    fi

    val=${line#${var}=}
    val=$(echo "$val" | tr -d '"' | tr -d "'")

    # уже есть как отдельный порт (границы: начало/конец/запятая)
    if echo ",$val," | grep -qE ",${port},"; then
      info "${var}: порт $port уже есть ($val)"
      return 0
    fi

    if [ -z "$val" ]; then
      new_val="$port"
    else
      new_val="${val},${port}"
    fi

    sed -i "s|^${var}=.*|${var}=${new_val}|" "$conf_file"
    info "${var}: добавлен порт $port → ${new_val}"
  }

  echo
  info "=== Проверка портов 853 (DoT) ==="
  ensure_port_in_var "$conf" "TCP_PORTS" "853"
  ensure_port_in_var "$conf" "UDP_PORTS" "853"

  /opt/etc/init.d/S51nfqws2 restart 2>/dev/null || true
  info "Сервис nfqws2 перезапущен."
}

# ---------------------------------------------------------------------------
# 6. Управление DoT/DoH (Keenetic dns-proxy через ndmc)
# ---------------------------------------------------------------------------
# Полная интеграция функционала menu-dns.sh: просмотр, добавление DoT/DoH,
# привязка доменов, удаление upstream-ов через ndmc.

show_dns_servers() {
  if ! command -v ndmc >/dev/null 2>&1; then
    error "ndmc не найден. Функция доступна только на Keenetic/Netcraze OS."
    return 1
  fi

  ndmc -c show dns-proxy 2>/dev/null | awk -v c_reset="$NC" \
                                           -v c_bold="$BOLD" \
                                           -v c_cyan="$CYAN" \
                                           -v c_green="$GREEN" \
                                           -v c_yellow="$YELLOW" \
                                           -v c_magenta="$MAGENTA" \
                                           -v c_dim="$DIM" '
    BEGIN { dot_gen_cnt = 0; doh_gen_cnt = 0; dom_cnt = 0 }

    /server-tls:/ {
      if (in_dot && addr != "") {
        target = (sni != "") ? addr " " sni : addr
        if (domain == "") {
          dot_gen[dot_gen_cnt++] = "  " c_cyan "🔒" c_reset " " target
        } else {
          dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " target " " c_magenta "[DoT]" c_reset
        }
        if (target != "") dot_tot[target] = 1
      }
      in_dot=1; in_doh=0; addr=""; sni=""; domain=""; next
    }
    in_dot && /address:/ { addr=$2 }
    in_dot && /port:/ { if ($2 != "853") addr=addr ":" $2 }
    in_dot && /sni:/ { sni=$2 }
    in_dot && /domain:/ { domain=$2 }

    /server-https:/ {
      # Сначала сбросить незакрытый DoT-блок (иначе последний server-tls теряется)
      if (in_dot && addr != "") {
        target = (sni != "") ? addr " " sni : addr
        if (domain == "") {
          dot_gen[dot_gen_cnt++] = "  " c_cyan "🔒" c_reset " " target
        } else {
          dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " target " " c_magenta "[DoT]" c_reset
        }
        if (target != "") dot_tot[target] = 1
      }
      if (in_doh && uri != "") {
        gsub(/[ \t\r\n]/, "", uri)
        if (domain == "") {
          doh_gen[doh_gen_cnt++] = "  " c_green "⚡" c_reset " " uri
        } else {
          dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " uri " " c_cyan "[DoH]" c_reset
        }
        if (uri != "") doh_tot[uri] = 1
      }
      in_doh=1; in_dot=0; addr=""; sni=""; uri=""; domain=""; next
    }
    in_doh && /uri:/ { reading_uri=1; uri=$2; next }
    in_doh && reading_uri && (/format:/ || /spki:/ || /interface:/ || /domain:/) { reading_uri=0 }
    in_doh && reading_uri { uri=uri $1 }
    in_doh && /domain:/ { domain=$2 }

    END {
      if (in_dot && addr != "") {
        target = (sni != "") ? addr " " sni : addr
        if (domain == "") {
          dot_gen[dot_gen_cnt++] = "  " c_cyan "🔒" c_reset " " target
        } else {
          dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " target " " c_magenta "[DoT]" c_reset
        }
        if (target != "") dot_tot[target] = 1
      }
      if (in_doh && uri != "") {
        gsub(/[ \t\r\n]/, "", uri)
        if (domain == "") {
          doh_gen[doh_gen_cnt++] = "  " c_green "⚡" c_reset " " uri
        } else {
          dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " uri " " c_cyan "[DoH]" c_reset
        }
        if (uri != "") doh_tot[uri] = 1
      }

      for (k in dot_tot) dot_c++
      for (k in doh_tot) doh_c++

      print c_cyan "┌────────────────────────────────────────────────────────┐" c_reset
      print c_cyan "│" c_bold "          УПРАВЛЕНИЕ DNS СЕРВЕРАМИ KEENETIC             " c_cyan "│" c_reset
      print c_cyan "└────────────────────────────────────────────────────────┘" c_reset

      print "\n" c_bold c_magenta "  [ DoT Серверы ]" c_reset " " c_dim "[" dot_c+0 "/8]" c_reset
      delete printed
      if (dot_gen_cnt == 0) print "  " c_dim "— нет общих серверов —" c_reset
      for (i=0; i<dot_gen_cnt; i++) {
        if (!printed[dot_gen[i]]) { print dot_gen[i]; printed[dot_gen[i]] = 1 }
      }

      print "\n" c_bold c_cyan "  [ DoH Серверы ]" c_reset " " c_dim "[" doh_c+0 "/8]" c_reset
      delete printed
      if (doh_gen_cnt == 0) print "  " c_dim "— нет общих серверов —" c_reset
      for (i=0; i<doh_gen_cnt; i++) {
        if (!printed[doh_gen[i]]) { print doh_gen[i]; printed[doh_gen[i]] = 1 }
      }

      print "\n" c_bold c_yellow "  [ Персональные привязки к доменам ]" c_reset
      delete printed
      if (dom_cnt == 0) print "  " c_dim "— привязки отсутствуют —" c_reset
      for (i=0; i<dom_cnt; i++) {
        if (!printed[dom_list[i]]) { print dom_list[i]; printed[dom_list[i]] = 1 }
      }
      print "\n" c_dim "────────────────────────────────────────────────────────" c_reset
    }
  '
}

dns_save_config() {
  printf '%s' "Сохранение конфигурации..."
  if ndmc -c system configuration save > /dev/null 2>&1; then
    printf ' %s\n' "${GREEN}[ГОТОВО]${NC}"
  else
    printf ' %s\n' "${RED}[ОШИБКА]${NC}"
    warn "ndmc не смог сохранить конфигурацию"
  fi
  sleep 1
}

apply_dot() {
  ip="$1"
  sni="$2"
  domain="$3"
  port="$4"

  cmd="dns-proxy tls upstream $ip"
  [ -n "$port" ] && cmd="$cmd $port"
  [ -n "$sni" ] && cmd="$cmd sni $sni"
  [ -n "$domain" ] && cmd="$cmd domain $domain"

  printf '%s\n' "${CYAN}Применение DoT ($ip):${NC} ndmc -c \"$cmd\""
  ndmc -c "$cmd" > /dev/null 2>&1 || warn "ndmc вернул ошибку при добавлении DoT $ip"
}

apply_doh() {
  uri="$1"
  domain="$2"

  cmd="dns-proxy https upstream $uri"
  [ -n "$domain" ] && cmd="$cmd domain $domain"

  printf '%s\n' "${CYAN}Применение DoH ($uri):${NC} ndmc -c \"$cmd\""
  ndmc -c "$cmd" > /dev/null 2>&1 || warn "ndmc вернул ошибку при добавлении DoH $uri"
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
  clean_choices=$(echo "$raw_choices" | tr ',' ' ')

  added_any=0
  for choice in $clean_choices; do
    case $choice in
      1) apply_dot "77.88.8.8" "common.dot.dns.yandex.net" "$domain"; added_any=1 ;;
      2) apply_dot "77.88.8.1" "common.dot.dns.yandex.net" "$domain"; added_any=1 ;;
      3) apply_dot "1.1.1.1" "cloudflare-dns.com" "$domain"; added_any=1 ;;
      4) apply_dot "1.0.0.1" "cloudflare-dns.com" "$domain"; added_any=1 ;;
      5) apply_dot "1.1.1.2" "cloudflare-dns.com" "$domain"; added_any=1 ;;
      6) apply_dot "1.0.0.2" "cloudflare-dns.com" "$domain"; added_any=1 ;;
      7) apply_dot "1.1.1.3" "cloudflare-dns.com" "$domain"; added_any=1 ;;
      8) apply_dot "1.0.0.3" "cloudflare-dns.com" "$domain"; added_any=1 ;;
      9) apply_dot "9.9.9.9" "dns.quad9.net" "$domain"; added_any=1 ;;
      10) apply_dot "149.112.112.112" "dns.quad9.net" "$domain"; added_any=1 ;;
      11) apply_dot "185.228.168.9" "security-filter-dns.cleanbrowsing.org" "$domain" "853"; added_any=1 ;;
      12) apply_dot "185.228.169.9" "security-filter-dns2.cleanbrowsing.org" "$domain" "853"; added_any=1 ;;
      13) apply_dot "208.67.222.222" "dns.opendns.com" "$domain"; added_any=1 ;;
      14) apply_dot "208.67.220.220" "dns.opendns.com" "$domain"; added_any=1 ;;
      15) apply_dot "185.222.222.222" "dot.sb" "$domain"; added_any=1 ;;
      16) apply_dot "45.11.45.11" "dot.sb" "$domain"; added_any=1 ;;
      17) apply_dot "dns0.eu" "dns0.eu" "$domain"; added_any=1 ;;
      18) apply_dot "217.160.70.42" "ns1.opennameserver.org" "$domain"; added_any=1 ;;
      19) apply_dot "213.202.211.221" "ns2.opennameserver.org" "$domain"; added_any=1 ;;
      20) apply_dot "81.169.136.222" "ns3.opennameserver.org" "$domain"; added_any=1 ;;
      21) apply_dot "185.181.61.24" "ns4.opennameserver.org" "$domain"; added_any=1 ;;
      22) apply_dot "public.dns.iij.jp" "public.dns.iij.jp" "$domain"; added_any=1 ;;
      23) apply_dot "jp.tiar.app" "jp.tiar.app" "$domain"; added_any=1 ;;
      24) apply_dot "xbox-dns.ru" "xbox-dns.ru" "$domain"; added_any=1 ;;
      25) apply_dot "dns.comss.one" "dns.comss.one" "$domain"; added_any=1 ;;
      26) apply_dot "dns.malw.link" "dns.malw.link" "$domain"; added_any=1 ;;
      27) apply_dot "5u35p8m9i7.cloudflare-gateway.com" "5u35p8m9i7.cloudflare-gateway.com" "$domain"; added_any=1 ;;
      28) apply_dot "geohide.ru" "geohide.ru" "$domain"; added_any=1 ;;
      29) 
        ask "Введите IP/Хост: "
        read -r manual_ip
        ask "Введите Порт (по умолчанию 853, отмена - Enter): "
        read -r manual_port
        ask "Введите SNI (отмена - Enter): "
        read -r manual_sni
        if [ -n "$manual_ip" ]; then
          apply_dot "$manual_ip" "$manual_sni" "$domain" "$manual_port"
          added_any=1
        fi
        ;;
    esac
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
  echo "20) Ввести вручную (произвольный URI)"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices

  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  ask "Привязать выбранные к домену? (пусто для всех): "
  read -r domain
  clean_choices=$(echo "$raw_choices" | tr ',' ' ')

  added_any=0
  for choice in $clean_choices; do
    case $choice in
      1) apply_doh "https://77.88.8.8/dns-query" "$domain"; added_any=1 ;;
      2) apply_doh "https://77.88.8.1/dns-query" "$domain"; added_any=1 ;;
      3) apply_doh "https://cloudflare-dns.com/dns-query" "$domain"; added_any=1 ;;
      4) apply_doh "https://dns.quad9.net/dns-query" "$domain"; added_any=1 ;;
      5) apply_doh "https://doh.cleanbrowsing.org/doh/security-filter/" "$domain"; added_any=1 ;;
      6) apply_doh "https://doh.opendns.com/dns-query" "$domain"; added_any=1 ;;
      7) apply_doh "https://doh.dns.sb/dns-query" "$domain"; added_any=1 ;;
      8) apply_doh "https://dns0.eu/" "$domain"; added_any=1 ;;
      9) apply_doh "https://ns1.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
      10) apply_doh "https://ns2.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
      11) apply_doh "https://ns3.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
      12) apply_doh "https://ns4.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
      13) apply_doh "https://public.dns.iij.jp/dns-query" "$domain"; added_any=1 ;;
      14) apply_doh "https://jp.tiar.app/dns-query" "$domain"; added_any=1 ;;
      15) apply_doh "https://jp.tiarap.org/dns-query" "$domain"; added_any=1 ;;
      16) apply_doh "https://xbox-dns.ru/dns-query" "$domain"; added_any=1 ;;
      17) apply_doh "https://dns.comss.one/dns-query" "$domain"; added_any=1 ;;
      18) apply_doh "https://dns.malw.link/dns-query" "$domain"; added_any=1 ;;
      19) apply_doh "https://5u35p8m9i7.cloudflare-gateway.com/dns-query" "$domain"; added_any=1 ;;
      20) apply_doh "https://dns.geohide.ru/dns-query" "$domain"; added_any=1 ;;
      21)
        ask "Введите URI DoH сервера: "
        read -r manual_uri
        if [ -n "$manual_uri" ]; then
          apply_doh "$manual_uri" "$domain"
          added_any=1
        fi
        ;;
    esac
  done

  [ "$added_any" -eq 1 ] && dns_save_config
}

add_domain_menu() {
  echo
  printf '%s\n' "${BOLD}Быстрая привязка DNS к целевым доменам (можно несколько через запятую, напр. 1,3,4):${NC}"
  echo " 1) CleanBrowsing DoT (185.228.168.9 + SNI) ➔ instagram.com"
  echo " 2) CleanBrowsing DoH (doh.cleanbrowsing.org) ➔ instagram.com"
  echo " 3) sw.ext.io DoT ➔ rutor.is & rutor.info"
  echo " 4) Malw Link DoH (dns.malw.link) ➔ ntc.party"
  echo " 5) Ввести свой домен и выбрать сервер"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices

  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  clean_choices=$(echo "$raw_choices" | tr ',' ' ')
  added_any=0

  for choice in $clean_choices; do
    case $choice in
      1)
        apply_dot "185.228.168.9" "security-filter-dns.cleanbrowsing.org" "instagram.com" "853"
        added_any=1
        ;;
      2)
        apply_doh "https://doh.cleanbrowsing.org/doh/security-filter/" "instagram.com"
        added_any=1
        ;;
      3)
        apply_dot "sw.ext.io" "" "rutor.is"
        apply_dot "sw.ext.io" "" "rutor.info"
        added_any=1
        ;;
      4)
        apply_doh "https://dns.malw.link/dns-query" "ntc.party"
        added_any=1
        ;;
      5)
        ask "Введите домен (например: example.com): "
        read -r dom
        if [ -n "$dom" ]; then
          echo "Тип протокола: 1) DoT  2) DoH"
          ask "Выберите [1-2]: "
          read -r ptype
          if [ "$ptype" = "1" ]; then
            ask "Введите IP/Хост DoT: "
            read -r dot_ip
            ask "Введите SNI (необязательно): "
            read -r dot_sni
            ask "Введите порт (по умолчанию 853, Enter - пропустить): "
            read -r dot_port
            if [ -n "$dot_ip" ]; then
              apply_dot "$dot_ip" "$dot_sni" "$dom" "$dot_port"
              added_any=1
            fi
          elif [ "$ptype" = "2" ]; then
            ask "Введите URI DoH: "
            read -r doh_uri
            if [ -n "$doh_uri" ]; then
              apply_doh "$doh_uri" "$dom"
              added_any=1
            fi
          fi
        fi
        ;;
    esac
  done

  [ "$added_any" -eq 1 ] && dns_save_config
}

remove_dns_menu() {
  tmp_list="/tmp/dns_rem_list.txt"
  rm -f "$tmp_list"

  ndmc -c show dns-proxy 2>/dev/null | awk '
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
      # Сначала сбросить незакрытый DoT-блок (иначе последний server-tls теряется)
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
        a = parts[1]
        pt = parts[2]
        print idx " | dot | " a " | " pt " | " dot_doms[dot_addrs[i]]
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

  clean_choices=$(echo "$raw_choices" | tr ',' ' ')
  removed_any=0

  for choice in $clean_choices; do
    line=$(grep -E "^$choice \|" "$tmp_list")
    if [ -n "$line" ]; then
      type=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
      target=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
      port=$(echo "$line" | awk -F'|' '{print $4}' | xargs)

      cmd=""
      if [ "$type" = "dot" ]; then
        # Keenetic: для порта 853 (дефолт) в команде удаления порт указывать нельзя.
        # Иначе: "no such DNS-over-TLS server: x.x.x.x:853"
        if [ -n "$port" ] && [ "$port" != "853" ]; then
          cmd="no dns-proxy tls upstream $target $port"
        else
          cmd="no dns-proxy tls upstream $target"
        fi
      elif [ "$type" = "doh" ]; then
        cmd="no dns-proxy https upstream $target"
      fi

      printf '%s\n' "${RED}Удаление:${NC} ndmc -c \"$cmd\""
      if ndmc -c "$cmd" > /dev/null 2>&1; then
        removed_any=1
      else
        warn "ndmc не смог удалить: $target"
      fi
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
    case "$src" in
      /*) ;;
      *) src="$(pwd)/$src" ;;
    esac
  fi
  echo "$src"
}

# Извлечь SCRIPT_VERSION="x.y.z" из файла
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
# 10. dpi-detector (rust) — актуальная версия через install.sh
# ---------------------------------------------------------------------------
DPI_DETECTOR_INSTALL_URL="https://raw.githubusercontent.com/Runnin4ik/dpi-detector/rust/install.sh"

# Удалить дубликаты dpi-detector (оставить только /opt/bin, если он есть)
cleanup_dpi_detector_dupes() {
  local primary="" f
  if [ -x /opt/bin/dpi-detector ]; then
    primary="/opt/bin/dpi-detector"
  elif command -v dpi-detector >/dev/null 2>&1; then
    primary=$(command -v dpi-detector)
  fi

  for f in /tmp/dpi-detector /opt/root/dpi-detector "$HOME/dpi-detector"; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    # не трогать основной файл
    if [ -n "$primary" ] && [ "$f" = "$primary" ]; then
      continue
    fi
    # если primary есть — дубликат можно удалить
    if [ -n "$primary" ] && [ -f "$primary" ]; then
      rm -f "$f" && info "  удалён дубликат: $f"
    fi
  done

  # /tmp может содержать временные копии с суффиксами
  for f in /tmp/dpi-detector* /opt/root/dpi-detector*; do
    [ -f "$f" ] || continue
    if [ -n "$primary" ] && [ "$f" = "$primary" ]; then
      continue
    fi
    if [ -n "$primary" ] && [ -f "$primary" ]; then
      rm -f "$f" && info "  удалён дубликат: $f"
    fi
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

  # Уже установлен — сразу запуск без вопросов
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
  ask "Установить dpi-detector? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) info "Отменено."; return 0 ;;
  esac

  info "Запуск установщика..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$DPI_DETECTOR_INSTALL_URL" | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$DPI_DETECTOR_INSTALL_URL" | sh
  else
    error "Нужны curl или wget."
    return 1
  fi

  echo
  info "Очистка дубликатов dpi-detector (/tmp, /opt/root)..."
  cleanup_dpi_detector_dupes
  info "Установка dpi-detector завершена."
}

# ---------------------------------------------------------------------------
# 11. awg-manager (AmneziaWG compressed installer)
# ---------------------------------------------------------------------------
AWG_MANAGER_INSTALL_URL="https://raw.githubusercontent.com/rndnaame/awg-compressed/main/install-compressed.sh"

menu_awg_manager() {
  echo
  info "awg-manager — установка через awg-compressed"
  info "Источник: $AWG_MANAGER_INSTALL_URL"
  echo
  ask "Запустить установщик awg-manager? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) info "Отменено."; return 0 ;;
  esac

  info "Запуск установщика..."
  if command -v curl >/dev/null 2>&1; then
    curl -sL "$AWG_MANAGER_INSTALL_URL" | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$AWG_MANAGER_INSTALL_URL" | sh
  else
    error "Нужны curl или wget."
    return 1
  fi
  info "Установщик awg-manager завершил работу."
}

# ---------------------------------------------------------------------------
# 12. KeenKit
# ---------------------------------------------------------------------------
KEENKIT_INSTALL_URL="https://raw.githubusercontent.com/spatiumstas/KeenKit/main/install.sh"

menu_keenkit() {
  echo
  # Уже установлен — сразу запуск без скачивания
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
  ask "Запустить установщик KeenKit? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) info "Отменено."; return 0 ;;
  esac

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

# ---------------------------------------------------------------------------
# 88. Удаление пакетов
# ---------------------------------------------------------------------------
# Удаление резервных копий конфигов/списков (.bak.*, *-opkg)
remove_backups() {
  local dirs="/opt/etc/nfqws /opt/etc/nfqws2 /opt/etc/nfqws2/lists"
  local f count=0

  echo
  info "Поиск резервных копий (.bak.* , *.conf-opkg , *.list-opkg)..."
  local found=""
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
  ask "Удалить найденные файлы ($count шт.)? [y/N]: "
  read -r ans
  case "$ans" in
    y|Y|д|Д)
      for f in $found; do
        rm -f "$f" && info "  удалён: $f" || warn "  не удалось: $f"
      done
      info "Готово."
      ;;
    *) info "Отменено." ;;
  esac
}

is_dpi_detector_installed() {
  [ -x /opt/bin/dpi-detector ] || command -v dpi-detector >/dev/null 2>&1
}

remove_dpi_detector() {
  local paths="/opt/bin/dpi-detector /tmp/dpi-detector"
  local f found=0
  # также бинарник в $HOME, если ставили туда
  [ -n "$HOME" ] && paths="$paths $HOME/dpi-detector"

  for f in $paths; do
    if [ -f "$f" ]; then
      rm -f "$f" && info "  удалён: $f" && found=1
    fi
  done
  # копия из PATH
  f=$(command -v dpi-detector 2>/dev/null || true)
  if [ -n "$f" ] && [ -f "$f" ]; then
    rm -f "$f" && info "  удалён: $f" && found=1
  fi
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
  if [ -d /opt/etc/awg-manager ]; then
    rm -rf /opt/etc/awg-manager && info "  удалён каталог: /opt/etc/awg-manager"
  fi
  info "awg-manager удалён."
}

menu_remove() {
  echo
  printf '%s\n' "${BOLD}Удаление:${NC}"

  # Собираем список только установленных
  local items="" types=""
  is_installed "nfqws-keenetic"     && items="$items nfqws-keenetic"     && types="$types opkg"
  is_installed "nfqws2-keenetic"    && items="$items nfqws2-keenetic"    && types="$types opkg"
  is_installed "nfqws-keenetic-web" && items="$items nfqws-keenetic-web" && types="$types opkg"
  is_dpi_detector_installed         && items="$items dpi-detector"      && types="$types bin"
  is_awg_manager_installed          && items="$items awg-manager"       && types="$types opkg"

  local i=1
  local p
  if [ -n "$items" ]; then
    for p in $items; do
      printf "  %d) %s\n" "$i" "$p"
      i=$((i + 1))
    done
  else
    warn "Установленных пакетов не найдено."
  fi
  echo "  a) Удалить все пакеты NFQWS"
  echo "  b) Удалить резервные копии (.bak.* / *-opkg)"
  echo "  0) Назад"
  ask "Что удалить? (номер / a / b / 0): "
  read -r choice

  case "$choice" in
    0|"") return ;;
    b|B|б|Б)
      remove_backups
      ;;
    a|A|а|А)
      ask "Точно удалить все пакеты NFQWS (и dpi-detector, если есть)? [y/N]: "
      read -r ans
      case "$ans" in
        y|Y|д|Д)
          opkg remove --autoremove nfqws-keenetic-web nfqws2-keenetic nfqws-keenetic 2>/dev/null || true
          remove_dpi_detector
          info "Удаление завершено."
          ;;
      esac
      ;;
    *)
      local idx=1
      local target=""
      for p in $items; do
        if [ "$idx" = "$choice" ]; then
          target="$p"
          break
        fi
        idx=$((idx + 1))
      done
      if [ -z "$target" ]; then
        warn "Неверный выбор"
        return
      fi
      ask "Удалить $target? [y/N]: "
      read -r ans
      case "$ans" in
        y|Y|д|Д)
          if [ "$target" = "dpi-detector" ]; then
            remove_dpi_detector
          elif [ "$target" = "awg-manager" ]; then
            remove_awg_manager
          else
            opkg remove --autoremove "$target"
            info "$target удалён."
          fi
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
    echo "      5.  $LBL_5"
    echo "      6.  $LBL_6"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_UTILS}${NC}"
    echo "      10. dpi-detector"
    echo "      11. awg-manager"
    echo "      12. KeenKit"
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

    case "$choice" in
      1)   menu_install_nfqws ;;
      2)   install_web ;;
      3)   menu_strategy ;;
      4)   update_ipset_list ;;
      5)   menu_dot_doh ;;
      6)   menu_dns_manage ;;
      10)  menu_dpi_detector ;;
      11)  menu_awg_manager ;;
      12)  menu_keenkit ;;
      77)  menu_change_language; continue ;;
      88)  menu_remove ;;
      99)  update_self ;;
      00|0|"")
        info "$LBL_00."
        exit 0
        ;;
      *)  warn "Invalid menu item" ;;
    esac

    echo
    ask "$LBL_BACK"
    read -r _
  done
}

# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------
# Запомнить путь к скрипту (для пункта 99)
case "$0" in
  /*) SCRIPT_PATH="$0" ;;
  *)  SCRIPT_PATH="$(pwd)/$0" ;;
esac
# Если запущен как: sh /path/nfqws-menu.sh
if [ ! -f "$SCRIPT_PATH" ]; then
  for a in "$0" "$@"; do
    case "$a" in
      *.sh)
        if [ -f "$a" ]; then
          case "$a" in
            /*) SCRIPT_PATH="$a" ;;
            *)  SCRIPT_PATH="$(pwd)/$a" ;;
          esac
          break
        fi
        ;;
    esac
  done
fi
export SCRIPT_PATH

# Быстрый запуск: /opt/bin/menu → /opt/nfqws-menu.sh
ensure_menu_symlink() {
  local target="/opt/nfqws-menu.sh"
  local link="/opt/bin/menu"

  # предпочитаем канонический путь; иначе — текущий SCRIPT_PATH, если он в /opt
  if [ ! -f "$target" ] && [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    case "$SCRIPT_PATH" in
      /opt/*) target="$SCRIPT_PATH" ;;
    esac
  fi
  [ -f "$target" ] || return 0
  [ -d /opt/bin ] || mkdir -p /opt/bin 2>/dev/null || return 0

  # уже корректный symlink
  if [ -L "$link" ]; then
    local cur
    cur=$(readlink "$link" 2>/dev/null || true)
    [ "$cur" = "$target" ] && return 0
  fi

  # не затирать чужой обычный файл с именем menu
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    return 0
  fi

  ln -sf "$target" "$link" 2>/dev/null || true
  [ -L "$link" ] && chmod +x "$link" 2>/dev/null || true
}

ensure_menu_symlink

if ! command -v opkg >/dev/null 2>&1; then
  error "opkg не найден. Скрипт предназначен для Entware (Keenetic/Netcraze)."
  exit 1
fi

main_menu
