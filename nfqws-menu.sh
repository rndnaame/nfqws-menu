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

SCRIPT_VERSION="0.6.69"

REPO_URL="https://github.com/rndnaame/nfqws-menu"
RAW_BASE="https://raw.githubusercontent.com/rndnaame/nfqws-menu/main"
STRATEGIES_API="https://api.github.com/repos/rndnaame/nfqws-menu/contents/strategies"

# Туннели для fallback-скачивания, если основной канал недоступен (DPI и т.п.)
# Порядок = приоритет. opkgtun0 — usque; opgktun0 — на случай другого имени.
FALLBACK_IFACES="awg0 t2s0 nwg0 opkgtun0 opgktun0"

# Таймауты скачивания (сек). Чуть выше для сильного DPI, но не слишком —
# чтобы быстрее уходить на fallback/зеркало.
CURL_CONNECT_TIMEOUT=10
CURL_MAX_TIME=30
CURL_MAX_TIME_LARGE=180   # rkn.list ~2 МБ и подобные
WGET_TIMEOUT=25

# LD_LIBRARY_PATH не экспортируем глобально: /opt ломает ndmc (OpenSSL),
# system-only ломает Entware wget/curl. Для ndmc — отдельная обёртка.
# Нужно при запуске через CLI Keenetic (exec sh / telnet) и OPKG hooks,
# где LD_LIBRARY_PATH=/opt/lib:/opt/usr/lib:/lib:/usr/lib.
ndmc_cli() {
  # системные libs первыми; иначе ndmc тянет OpenSSL из Entware → system failed
  LD_LIBRARY_PATH=/lib:/usr/lib command ndmc -c "$@"
}

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
# Язык UI  (/opt/etc/nfqws-menu/nfqws-menu.lang, env NFQWS_MENU_LANG / NFQWS_MENU_UTF8)
# Миграция со старого пути /opt/etc/nfqws-menu.lang
# Авто: SSH → ru, иначе en
# ---------------------------------------------------------------------------
UI_LANG_FILE="/opt/etc/nfqws-menu/nfqws-menu.lang"
if [ ! -f "$UI_LANG_FILE" ] && [ -f /opt/etc/nfqws-menu.lang ]; then
  mkdir -p /opt/etc/nfqws-menu 2>/dev/null || true
  mv /opt/etc/nfqws-menu.lang "$UI_LANG_FILE" 2>/dev/null || \
    cp /opt/etc/nfqws-menu.lang "$UI_LANG_FILE" 2>/dev/null || true
fi

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
      LBL_S="Сервисные утилиты"
      LBL_S1="Сжать bin/sbin (UPX)"
      LBL_S2="Dropbear fix"
      LBL_U="Обновить все пакеты"
      LBL_1="Установить NFQWS/NFQWS2"
      LBL_2="Установить веб-интерфейс"
      LBL_3="Выбор стратегии"
      LBL_4="Обновить IPSet List"
      LBL_5="Загрузить rkn.list (125k+ доменов)"
      LBL_6="Обход блокировки DoT/DoH"
      LBL_7="Смена активных fake:blob"
      LBL_8="Обновление hosts"
      LBL_9="Управление DoT/DoH"
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
      LBL_S="Service utilities"
      LBL_S1="Compress bin/sbin (UPX)"
      LBL_S2="Dropbear fix"
      LBL_U="Upgrade all packages"
      LBL_1="Install NFQWS/NFQWS2"
      LBL_2="Install web UI"
      LBL_3="Select strategy"
      LBL_4="Update IPSet List"
      LBL_5="Download rkn.list (125k+ domains)"
      LBL_6="Bypass DoT/DoH blocks"
      LBL_7="Change active fake:blob"
      LBL_8="Update hosts"
      LBL_9="Manage DoT/DoH"
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
  mkdir -p /opt/etc/nfqws-menu 2>/dev/null || true
  echo "$UI_LANG" > "$UI_LANG_FILE" 2>/dev/null || true
}

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[x]${NC} $*"; }
ask()   { printf '%s' "${CYAN}[?]${NC} $*"; }

# ---------------------------------------------------------------------------
# Общие хелперы
# ---------------------------------------------------------------------------

# Обычный read (без stty и без /dev/tty — иначе ломается Backspace у SSH-клиентов).
# Использование: read_menu varname
read_menu() {
  read -r "$1"
}

# Сбросить буфер stdin, чтобы «Enter» от установщика не проглатывал следующий read.
drain_stdin() {
  local _ds
  while read -r -t 0 _ds 2>/dev/null; do
    read -r _ds 2>/dev/null || break
  done
}

# confirm_yes: Y/n — да по умолчанию. confirm_no: y/N — нет по умолчанию.
confirm_yes() {
  ask "${1:-Continue?} [Y/n]: "
  # Ответ обнуляем перед чтением: если read не получит строки (конец ввода),
  # прежнее значение не должно означать «да» — иначе долгий подбор запускается
  # сам, а на экране при этом «[Y/n]: n».
  ans=''
  read_menu ans || return 1
  case "$ans" in n|N|н|Н) return 1 ;; esac
  return 0
}

confirm_no() {
  ask "${1:-Continue?} [y/N]: "
  read_menu ans
  case "$ans" in y|Y|д|Д) return 0 ;; esac
  return 1
}

# Интерфейсы из FALLBACK_IFACES, которые есть в системе и не в состоянии down.
# WireGuard/Amnezia часто дают operstate=unknown — их тоже берём.
list_up_fallback_ifaces() {
  local iface oper
  for iface in $FALLBACK_IFACES; do
    [ -d "/sys/class/net/$iface" ] || continue
    oper=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo down)
    case "$oper" in
      down) continue ;;
    esac
    echo "$iface"
  done
}

# Локальный кэш загрузок (offline / при блокировке GitHub)
CACHE_DIR="/opt/etc/nfqws-menu"

cache_strategy_path() {
  # $1=ver(1|2) $2=имя.conf или default
  local ver="$1" name="$2"
  echo "${CACHE_DIR}/strategies/nfqws${ver}/${name}"
}

save_strategy_cache() {
  # $1=ver $2=name $3=src_file
  local ver="$1" name="$2" src="$3" dest
  [ -f "$src" ] && [ -s "$src" ] || return 1
  dest=$(cache_strategy_path "$ver" "$name")
  mkdir -p "$(dirname "$dest")" 2>/dev/null || true
  cp "$src" "$dest" 2>/dev/null || return 1
  return 0
}

list_strategies_from_cache() {
  local ver="$1" d
  d="${CACHE_DIR}/strategies/nfqws${ver}"
  [ -d "$d" ] || return 1
  # только *.conf, не default (его показываем отдельно)
  ls -1 "$d"/*.conf 2>/dev/null | while read -r f; do
    [ -f "$f" ] && [ -s "$f" ] || continue
    basename "$f"
  done
}

# Альтернативные URL для raw.githubusercontent.com / api.github.com (зеркала CDN).
# Печатает по одному URL на строку; исходный — первым.
github_alt_urls() {
  local url="$1" rest owner repo ref path_rest
  printf '%s\n' "$url"

  # raw.githubusercontent.com/OWNER/REPO/REF/PATH
  case "$url" in
    https://raw.githubusercontent.com/*)
      rest="${url#https://raw.githubusercontent.com/}"
      owner="${rest%%/*}"; rest="${rest#*/}"
      repo="${rest%%/*}"; rest="${rest#*/}"
      ref="${rest%%/*}"; path_rest="${rest#*/}"
      if [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$ref" ] && [ -n "$path_rest" ]; then
        # refs/heads/main → main для jsDelivr
        case "$ref" in
          refs/heads/*) ref="${ref#refs/heads/}" ;;
          refs/tags/*)  ref="${ref#refs/tags/}" ;;
        esac
        printf '%s\n' "https://cdn.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path_rest}"
        printf '%s\n' "https://fastly.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path_rest}"
        printf '%s\n' "https://ghproxy.net/https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path_rest}"
      fi
      ;;
    https://api.github.com/*)
      printf '%s\n' "https://ghproxy.net/${url}"
      ;;
  esac
}

# Одна попытка HTTP GET в stdout
_http_get_stdout() {
  local url="$1" iface="${2:-}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$iface" ]; then
      curl -fsSL --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        --interface "$iface" "$url" 2>/dev/null
    else
      curl -fsSL --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        "$url" 2>/dev/null
    fi
  elif [ -z "$iface" ] && command -v wget >/dev/null 2>&1; then
    wget -qO- -T "$WGET_TIMEOUT" "$url" 2>/dev/null
  else
    return 1
  fi
}

# Одна попытка HTTP GET в файл
_http_get_file() {
  local url="$1" dest="$2" iface="${3:-}"
  rm -f "$dest"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$iface" ]; then
      curl -fsSL --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        --interface "$iface" \
        -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
        "$url" -o "$dest" 2>/dev/null
    else
      curl -fsSL --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
        "$url" -o "$dest" 2>/dev/null
    fi
  elif [ -z "$iface" ] && command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" -T "$WGET_TIMEOUT" --no-cache "$url" 2>/dev/null || \
      wget -qO "$dest" -T "$WGET_TIMEOUT" "$url" 2>/dev/null
  else
    return 1
  fi
  [ -f "$dest" ] && [ -s "$dest" ]
}

# Скачивание с прогрессом (для больших файлов: rkn.list и т.п.)
# curl: progress-bar; wget: обычный индикатор (без -q).
_http_get_file_progress() {
  local url="$1" dest="$2" iface="${3:-}"
  rm -f "$dest"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$iface" ]; then
      curl -fL --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        --interface "$iface" --progress-bar -o "$dest" "$url"
    else
      curl -fL --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        --progress-bar -o "$dest" "$url"
    fi
  elif [ -z "$iface" ] && command -v wget >/dev/null 2>&1; then
    # без -q — показывает % / скорость
    wget -O "$dest" -T "$WGET_TIMEOUT" --no-cache "$url" || \
      wget -O "$dest" -T "$WGET_TIMEOUT" "$url"
  else
    return 1
  fi
  [ -f "$dest" ] && [ -s "$dest" ]
}

# Как download_file, но с отображением хода (stderr).
download_file_progress() {
  local url="$1" dest="$2" alt iface
  mkdir -p "$(dirname "$dest")" 2>/dev/null || true
  rm -f "$dest"

  for alt in $(github_alt_urls "$url"); do
    if [ "$alt" != "$url" ]; then
      info "Зеркало: $alt" >&2
    fi
    if _http_get_file_progress "$alt" "$dest"; then
      [ "$alt" != "$url" ] && info "Скачано через зеркало" >&2
      return 0
    fi
    rm -f "$dest"
  done

  if command -v curl >/dev/null 2>&1; then
    for iface in $(list_up_fallback_ifaces); do
      warn "Основной канал недоступен, пробуем через $iface ..." >&2
      for alt in $(github_alt_urls "$url"); do
        if _http_get_file_progress "$alt" "$dest" "$iface"; then
          info "Скачано через $iface" >&2
          return 0
        fi
        rm -f "$dest"
      done
    done
  fi

  rm -f "$dest"
  return 1
}

# Скачать URL в stdout: прямой → зеркала GitHub → туннели (--interface).
fetch_url() {
  local url="$1" alt iface body
  # 1) оригинал + CDN-зеркала
  for alt in $(github_alt_urls "$url"); do
    if body=$(_http_get_stdout "$alt"); then
      if [ -n "$body" ]; then
        [ "$alt" != "$url" ] && info "Скачано через зеркало" >&2
        printf '%s' "$body"
        return 0
      fi
    fi
  done
  # 2) туннели
  if command -v curl >/dev/null 2>&1; then
    for iface in $(list_up_fallback_ifaces); do
      warn "Основной канал недоступен, пробуем через $iface ..." >&2
      for alt in $(github_alt_urls "$url"); do
        if body=$(_http_get_stdout "$alt" "$iface"); then
          if [ -n "$body" ]; then
            info "Скачано через $iface" >&2
            printf '%s' "$body"
            return 0
          fi
        fi
      done
    done
  fi
  return 1
}

# Скачать URL в файл: прямой → зеркала → туннели. Пустые/битые не оставляем.
download_file() {
  local url="$1" dest="$2" alt iface
  mkdir -p "$(dirname "$dest")" 2>/dev/null || true
  rm -f "$dest"

  for alt in $(github_alt_urls "$url"); do
    if _http_get_file "$alt" "$dest"; then
      [ "$alt" != "$url" ] && info "Скачано через зеркало" >&2
      return 0
    fi
    rm -f "$dest"
  done

  if command -v curl >/dev/null 2>&1; then
    for iface in $(list_up_fallback_ifaces); do
      warn "Основной канал недоступен, пробуем через $iface ..." >&2
      for alt in $(github_alt_urls "$url"); do
        if _http_get_file "$alt" "$dest" "$iface"; then
          info "Скачано через $iface" >&2
          return 0
        fi
        rm -f "$dest"
      done
    done
  fi

  rm -f "$dest"
  return 1
}


# ---------------------------------------------------------------------------
# SHA256 для blobs (strategies/blobs/SHA256SUMS)
# ---------------------------------------------------------------------------
BLOBS_SHA256SUMS_URL="${RAW_BASE}/strategies/blobs/SHA256SUMS"
BLOBS_SHA256SUMS_CACHE="/tmp/nfqws-blobs-SHA256SUMS"

# 0 = есть sha256sum или openssl
have_sha256() {
  command -v sha256sum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1
}

# SHA256 файла → stdout (только хеш). При ошибке return 1.
file_sha256() {
  local f="$1"
  [ -f "$f" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}'
  else
    return 1
  fi
}

# Скачать/обновить кэш SHA256SUMS (TTL ~1ч). Не фатально при ошибке сети.
ensure_blobs_sha256sums() {
  local ttl=3600 now age
  now=$(date +%s 2>/dev/null || echo 0)
  if [ -f "$BLOBS_SHA256SUMS_CACHE" ] && [ -s "$BLOBS_SHA256SUMS_CACHE" ]; then
    # mtime кэша
    if age=$(stat -c %Y "$BLOBS_SHA256SUMS_CACHE" 2>/dev/null); then
      if [ $((now - age)) -lt "$ttl" ]; then
        return 0
      fi
    elif age=$(date -r "$BLOBS_SHA256SUMS_CACHE" +%s 2>/dev/null); then
      if [ $((now - age)) -lt "$ttl" ]; then
        return 0
      fi
    else
      # нет stat — считаем кэш свежим, пока файл есть
      return 0
    fi
  fi
  if download_file "$BLOBS_SHA256SUMS_URL" "$BLOBS_SHA256SUMS_CACHE"; then
    return 0
  fi
  # старый кэш лучше, чем ничего
  [ -s "$BLOBS_SHA256SUMS_CACHE" ] && return 0
  return 1
}

# Ожидаемый SHA256 для basename из кэша SUMS (пусто если нет)
blob_expected_sha256() {
  local name="$1"
  [ -s "$BLOBS_SHA256SUMS_CACHE" ] || return 0
  # формат: <hash>  <filename>  (два пробела) или hash + пробелы + name
  awk -v n="$name" '
    $2 == n { print $1; exit }
    NF >= 2 {
      # путь мог быть strategies/blobs/name
      bn = $2
      sub(/.*\//, "", bn)
      if (bn == n) { print $1; exit }
    }
  ' "$BLOBS_SHA256SUMS_CACHE" 2>/dev/null
}

# Скачать install.sh во временный файл и запустить на реальном tty.
# curl|sh отдаёт установщику stdin=pipe → интерактивное меню (awg и др.) не открывается.
run_remote_sh() {
  local url="$1" tmp rc=0
  tmp="/tmp/nfqws-remote-$$.sh"
  rm -f "$tmp"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp" 2>/dev/null || rm -f "$tmp"
  fi
  if [ ! -s "$tmp" ] && command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url" 2>/dev/null || rm -f "$tmp"
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    error "Не удалось скачать: $url"
    return 1
  fi
  # Полный tty: stdin+stdout+stderr — иначе awg-menu / интерактив не поднимается
  if [ -c /dev/tty ]; then
    sh "$tmp" < /dev/tty > /dev/tty 2>&1 || rc=$?
  else
    sh "$tmp" || rc=$?
  fi
  rm -f "$tmp"
  drain_stdin
  return "$rc"
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
  local f="$1" dest
  [ -f "$f" ] || return 0
  dest="${f}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "$f" "$dest" && info "Бэкап: $dest"
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
  # -- и -F: имя может начинаться с '-' (Sxx-xxx → svc=-xxx) → иначе grep видит опцию
  printf '%s\n' "$PROC_CACHE" | grep -qF -- "$name"
}

# Как proc_running, но имя команды должно совпасть целиком: tg-ws-proxy-rs
# содержит "tg-ws-proxy" подстрокой, и поиск фиксированной строки даёт ложный ⚡
# у Go-сборки, когда запущена Rust.
proc_running_exact() {
  local name="$1"
  [ -n "$PROC_CACHE" ] || refresh_proc_cache
  printf '%s\n' "$PROC_CACHE" | grep -qE "(^|[ /])${name}( |\$)"
}

# kind → «запущен?» (по процессу / порту)
service_is_up() {
  case "$1" in
    nfqws|nfqws2|usque|magitrickle|awg-manager) proc_running "$1" ;;
    # tg-ws-proxy-rs содержит "tg-ws-proxy" подстрокой, поэтому у Go-сборки
    # совпадение по целому имени команды, а у Rust — по своей строке.
    tg-ws-proxy)    proc_running_exact "tg-ws-proxy" ;;
    tg-ws-proxy-rs) proc_running "tg-ws-proxy-rs" ;;
    web)
      port_is_open 90 || proc_running lighttpd
      ;;
    # awg-manager: сам демон, либо sing-box из его каталога, либо amneziawg
    awg)
      proc_running "awg-manager" && return 0
      proc_running "amneziawg" && return 0
      # sing-box часто общий; учитываем только если он из комплекта awg-manager
      if [ -x /opt/etc/awg-manager/singbox/sing-box ] || [ -f /opt/etc/awg-manager/singbox/sing-box ]; then
        proc_running "sing-box" && return 0
      fi
      return 1
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

# $1=имя $2=версия/инфо [$3=kind для ⚡, опционально]
print_tool_info() {
  local name="$1" info="$2" kind="${3:-}" mark=""
  [ -n "$kind" ] && service_is_up "$kind" && mark="$RUN_MARK"
  printf '  %s%-22s%s %s%s\n' "$GREEN" "$name" "$NC" "$info" "$mark"
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
  if is_tg_ws_proxy_rs_installed; then
    local rs_ver
    rs_ver=$(tg_ws_proxy_rs_version)
    print_tool_info "tg-ws-proxy-rs" "${rs_ver:-ok}" "tg-ws-proxy-rs"
    shown=1
  fi
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
    print_tool_info "$awg_name" "$awg_info" "awg"
    shown=1
  fi

  if [ -f /opt/keenkit.sh ]; then
    local kk_ver
    kk_ver=$(grep -E '^SCRIPT_VERSION=' /opt/keenkit.sh 2>/dev/null | head -1 | \
      sed -n 's/^SCRIPT_VERSION=["'\'']\([^"'\'']*\)["'\''].*/\1/p')
    print_tool_info "KeenKit" "${kk_ver:-ok}"
    shown=1
  fi

  if [ -x /opt/usr/bin/telemt ] || [ -x /opt/etc/init.d/S99telemt ] || [ -d /opt/etc/telemt ]; then
    print_tool_info "telemt" "ok" "telemt"
    shown=1
  fi
  if [ -x /opt/sbin/telemt-panel ] || [ -x /opt/etc/init.d/S99telemt-panel ] || [ -d /opt/etc/telemt-panel ]; then
    print_tool_info "telemt-panel" "ok" "telemt-panel"
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
        nfqws|nfqws2|lighttpd|usque|tg-ws-proxy|tg-ws-proxy-rs|magitrickle|telemt|telemt-panel) continue ;;
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
  read_menu choice
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

# ---------------------------------------------------------------------------
# Корневой SHA256SUMS (список strategies/nfqwsN/*.conf без GitHub API)
# ---------------------------------------------------------------------------
REPO_SHA256SUMS_URL="${RAW_BASE}/SHA256SUMS"
REPO_SHA256SUMS_CACHE="/tmp/nfqws-repo-SHA256SUMS"

ensure_repo_sha256sums() {
  local ttl=3600 now age
  now=$(date +%s 2>/dev/null || echo 0)
  if [ -f "$REPO_SHA256SUMS_CACHE" ] && [ -s "$REPO_SHA256SUMS_CACHE" ]; then
    if age=$(stat -c %Y "$REPO_SHA256SUMS_CACHE" 2>/dev/null); then
      [ $((now - age)) -lt "$ttl" ] && return 0
    elif age=$(date -r "$REPO_SHA256SUMS_CACHE" +%s 2>/dev/null); then
      [ $((now - age)) -lt "$ttl" ] && return 0
    else
      return 0
    fi
  fi
  if download_file "$REPO_SHA256SUMS_URL" "$REPO_SHA256SUMS_CACHE"; then
    return 0
  fi
  [ -s "$REPO_SHA256SUMS_CACHE" ] && return 0
  return 1
}

# Имена *.conf из strategies/<ver>/ по корневому SHA256SUMS
list_strategies_from_sums() {
  local ver="$1"
  [ -s "$REPO_SHA256SUMS_CACHE" ] || return 1
  awk -v pref="strategies/${ver}/" '
    NF >= 2 {
      p = $2
      # только strategies/nfqwsN/name.conf (без подкаталогов)
      if (index(p, pref) != 1) next
      rest = substr(p, length(pref) + 1)
      if (rest ~ /\//) next
      if (rest ~ /\.conf$/) print rest
    }
  ' "$REPO_SHA256SUMS_CACHE" | sort -u
}

list_strategies() {
  # 1) SHA256SUMS  2) GitHub API  3) локальный кэш (offline)
  local ver="$1"
  local list="" url cache_list

  if ensure_repo_sha256sums; then
    list=$(list_strategies_from_sums "$ver" || true)
  fi
  if [ -z "$list" ]; then
    url="${STRATEGIES_API}/${ver}"
    list=$(fetch_url "$url" 2>/dev/null | grep -o '"name": *"[^"]*\.conf"' | sed 's/.*"\([^"]*\)".*/\1/' || true)
  fi

  cache_list=$(list_strategies_from_cache "$ver" 2>/dev/null || true)
  if [ -n "$cache_list" ]; then
    list=$(printf '%s\n%s\n' "$list" "$cache_list" | grep -E '\.conf$' | sort -u)
  fi

  if [ -n "$list" ]; then
    printf '%s\n' "$list" | grep -E '\.conf$' || true
    return 0
  fi
  return 1
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

# Проверка глобального IPv6 (2a00::/12) на интерфейсе.
# Возвращает 0 (успех) если найден адрес вида 2a00*, иначе 1.
iface_has_global_ipv6() {
  local iface="$1"
  [ -z "$iface" ] && return 1
  if command -v ip >/dev/null 2>&1; then
    # ip -6: "inet6 2a00:...." scope global
    ip -6 addr show dev "$iface" 2>/dev/null | grep -qE 'inet6[[:space:]]+2a00'
    return $?
  fi
  # fallback: ifconfig (BusyBox) — "inet6 addr: 2a00:...."
  ifconfig "$iface" 2>/dev/null | grep -qiE 'inet6[[:space:]]+addr:[[:space:]]*2a00'
  return $?
}

fix_isp_interface() {
  local conf="$1" detected current ipv6_val current_ipv6
  detected=$(detect_isp_interface)
  if [ -z "$detected" ]; then
    warn "Не удалось определить интерфейс провайдера (route/ip route)."
    return 1
  fi
  # tr -d '\r"' — иначе CRLF из .conf даёт \r и ломает вывод (" переезжает в начало строки)
  current=$(grep -E '^ISP_INTERFACE=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  info "Интерфейс провайдера (default route): $detected"
  [ -n "$current" ] && info "В конфиге сейчас: ISP_INTERFACE=\"$current\""
  if [ "$current" = "$detected" ]; then
    info "ISP_INTERFACE уже совпадает с интерфейсом провайдера."
  else
    if ! confirm_yes "Установить ISP_INTERFACE=\"$detected\"?"; then
      warn "ISP_INTERFACE не изменён."
    else
      if grep -qE '^ISP_INTERFACE=' "$conf" 2>/dev/null; then
        sed -i "s|^ISP_INTERFACE=.*|ISP_INTERFACE=\"$detected\"|" "$conf"
      else
        printf 'ISP_INTERFACE="%s"\n' "$detected" | cat - "$conf" > "${conf}.new" && mv "${conf}.new" "$conf"
      fi
      info "ISP_INTERFACE=\"$detected\" записан в $conf"
    fi
  fi

  # --- IPV6_ENABLED: наличие глобального IPv6 (2a00*) на интерфейсе провайдера ---
  echo
  info "=== Проверка IPv6 на $detected ==="
  if iface_has_global_ipv6 "$detected"; then
    ipv6_val=1
    info "Найден глобальный IPv6-адрес (2a00*) на $detected → IPV6_ENABLED=1"
  else
    ipv6_val=0
    info "Глобальный IPv6 (2a00*) на $detected не найден → IPV6_ENABLED=0"
  fi

  current_ipv6=$(grep -E '^IPV6_ENABLED=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ "$current_ipv6" = "$ipv6_val" ]; then
    info "IPV6_ENABLED уже = $ipv6_val — без изменений."
  else
    if grep -qE '^IPV6_ENABLED=' "$conf" 2>/dev/null; then
      sed -i "s|^IPV6_ENABLED=.*|IPV6_ENABLED=$ipv6_val|" "$conf"
    else
      # добавляем после ISP_INTERFACE, если есть, иначе в начало
      if grep -qE '^ISP_INTERFACE=' "$conf" 2>/dev/null; then
        sed -i "/^ISP_INTERFACE=/a IPV6_ENABLED=$ipv6_val" "$conf"
      else
        printf 'IPV6_ENABLED=%s\n' "$ipv6_val" | cat - "$conf" > "${conf}.new" && mv "${conf}.new" "$conf"
      fi
    fi
    info "IPV6_ENABLED=$ipv6_val записан в $conf"
  fi
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
    # auto.list заполняется демоном — пустой допустим только для него
    if [ "$repo_sub" = "lists" ] && [ "$name" = "auto.list" ]; then
      touch "$path"
      info "  создан пустой $path (заполняется демоном)"
      continue
    fi
    info "Скачивание $name → $path"
    if download_file "${RAW_BASE}/strategies/${repo_sub}/${name}" "$path"; then
      info "  готово"
    else
      rm -f "$path"
      warn "  нет в репозитории / ошибка загрузки — файл не создан ($name)"
    fi
  done
}

# Проверка blobs: наличие + SHA256 (по strategies/blobs/SHA256SUMS).
# Устаревшие/битые и отсутствующие предлагается скачать.
# $1=ver (не используется, совместимость) $2=conf
check_blobs() {
  local conf="$2"
  local paths path name missing=0 missing_list="" expected local_sha sums_ok=0

  if [ ! -f "$conf" ]; then
    warn "Конфиг $conf не найден — проверка blobs пропущена."
    return 1
  fi

  paths=$(extract_blob_paths "$conf")
  if [ -z "$paths" ]; then
    info "В конфиге нет ссылок на blobs — проверка не требуется."
    return 0
  fi

  if ensure_blobs_sha256sums; then
    sums_ok=1
    info "Эталон SHA256SUMS загружен (кэш: $BLOBS_SHA256SUMS_CACHE)."
  else
    warn "SHA256SUMS недоступен — проверка только по наличию файлов."
  fi

  info "blobs, указанные в конфиге:"
  for path in $paths; do
    name=$(basename "$path")
    if [ ! -f "$path" ]; then
      warn "  нет $path"
      missing=1
      missing_list="$missing_list $path"
      continue
    fi

    if [ "$sums_ok" -eq 1 ] && have_sha256; then
      expected=$(blob_expected_sha256 "$name")
      if [ -n "$expected" ]; then
        local_sha=$(file_sha256 "$path" || true)
        if [ -n "$local_sha" ] && [ "$local_sha" = "$expected" ]; then
          info "  OK  $path  (sha256)"
        else
          warn "  устарел/повреждён $path"
          [ -n "$local_sha" ] && info "    local  $local_sha"
          info "    expect $expected"
          missing=1
          missing_list="$missing_list $path"
        fi
      else
        info "  OK  $path  (нет в SHA256SUMS)"
      fi
    else
      info "  OK  $path"
    fi
  done

  [ "$missing" -eq 0 ] && { info "Все используемые blobs на месте и актуальны."; return 0; }

  warn "Часть blobs отсутствует или не совпадает с репозиторием."
  confirm_yes "Скачать отсутствующие/устаревшие blobs из strategies/blobs/?" || return 0

  for path in $missing_list; do
    name=$(basename "$path")
    mkdir -p "$(dirname "$path")"
    info "Скачивание $name → $path"
    if ! download_file "${RAW_BASE}/strategies/blobs/${name}" "$path"; then
      rm -f "$path"
      warn "  нет в репозитории / ошибка загрузки — файл не создан ($name)"
      continue
    fi
    # пост-проверка SHA при наличии эталона
    if [ "$sums_ok" -eq 1 ] && have_sha256; then
      expected=$(blob_expected_sha256 "$name")
      if [ -n "$expected" ]; then
        local_sha=$(file_sha256 "$path" || true)
        if [ -n "$local_sha" ] && [ "$local_sha" = "$expected" ]; then
          info "  готово (sha256 OK)"
        else
          warn "  скачан, но sha256 не совпал — удаляю $path"
          [ -n "$local_sha" ] && info "    local  $local_sha"
          info "    expect $expected"
          rm -f "$path"
        fi
      else
        info "  готово (нет эталона в SHA256SUMS)"
      fi
    else
      info "  готово"
    fi
  done
}

check_lists() { check_conf_files "lists" "$2" extract_list_paths "lists" "Скачать отсутствующие lists из strategies/lists/?"; }

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

# Восстановить строку VAR=… в конфиге (полная строка как была, без CRLF).
# $1=conf  $2=имя переменной (POLICY_NAME)  $3=сохранённая строка целиком (POLICY_NAME="nfqws")
restore_conf_var_line() {
  local conf="$1" var="$2" line="$3"
  [ -n "$line" ] || return 0
  line=$(printf '%s' "$line" | tr -d '\r')
  if grep -qE "^${var}=" "$conf" 2>/dev/null; then
    sed -i "s|^${var}=.*|${line}|" "$conf"
  elif grep -qE '^(POLICY_|ISP_INTERFACE=)' "$conf" 2>/dev/null; then
    # вставить после последней строки POLICY_* / ISP_INTERFACE
    awk -v line="$line" '
      { buf[NR] = $0; if ($0 ~ /^(POLICY_|ISP_INTERFACE=)/) last = NR }
      END {
        n = NR
        for (i = 1; i <= n; i++) {
          print buf[i]
          if (i == last) print line
        }
        if (!last) print line
      }
    ' "$conf" > "${conf}.new" && mv "${conf}.new" "$conf"
  else
    printf '%s\n' "$line" >> "$conf"
  fi
}

apply_strategy() {
  local ver="$1" conf_name="$2" conf_path conf_dest tmp had_rkn=0 rkn_path
  local saved_policy_name="" saved_policy_exclude="" had_policy=0
  local pn_val pe_val policy_nondefault=0
  local init_script stopped_svc=0 cache_file

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

  # Запоминаем привязку rkn.list в MODE_LIST — стратегия перезапишет весь конфиг
  if conf_has_rkn_hostlist "$conf_dest" "$ver"; then
    had_rkn=1
    info "В текущем конфиге есть привязка rkn.list — будет восстановлена после смены стратегии."
  fi

  # Сохранить POLICY_NAME / POLICY_EXCLUDE (стратегия обычно их затирает).
  # Стандарт: POLICY_NAME="nfqws" POLICY_EXCLUDE=0 — без лишних сообщений в лог.
  if grep -qE '^POLICY_NAME=' "$conf_dest" 2>/dev/null; then
    saved_policy_name=$(grep -E '^POLICY_NAME=' "$conf_dest" 2>/dev/null | head -1 | tr -d '\r')
    had_policy=1
  fi
  if grep -qE '^POLICY_EXCLUDE=' "$conf_dest" 2>/dev/null; then
    saved_policy_exclude=$(grep -E '^POLICY_EXCLUDE=' "$conf_dest" 2>/dev/null | head -1 | tr -d '\r')
    had_policy=1
  fi

  info "Скачивание стратегии: $conf_name"
  info "URL: $conf_path"
  tmp="/tmp/nfqws-strategy-$$.conf"
  init_script=$(nfqws_init_path "$ver")

  if ! download_file "$conf_path" "$tmp"; then
    # default: запасной branch main
    if [ "$conf_name" = "default" ] && echo "$conf_path" | grep -q '/master/'; then
      conf_path=$(echo "$conf_path" | sed 's|/master/|/main/|')
      info "Пробуем branch main: $conf_path"
      download_file "$conf_path" "$tmp" || true
    fi
  fi

  # Сеть/DPI мешают — остановить nfqws и повторить (сервис может ломать загрузку)
  if [ ! -s "$tmp" ] && [ -x "$init_script" ]; then
    warn "Скачивание не удалось — останавливаем $(basename "$init_script") и пробуем снова..."
    "$init_script" stop 2>/dev/null || true
    stopped_svc=1
    sleep 1
    download_file "$conf_path" "$tmp" || true
  fi

  if [ ! -s "$tmp" ]; then
    # offline: локальный кэш
    cache_file=$(cache_strategy_path "$ver" "$conf_name")
    if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
      warn "Сеть недоступна — берём из кэша: $cache_file"
      cp "$cache_file" "$tmp"
    else
      error "Не удалось скачать $conf_path (и нет кэша offline)"
      [ "$stopped_svc" -eq 1 ] && service_restart "$init_script"
      return 1
    fi
  else
    save_strategy_cache "$ver" "$conf_name" "$tmp" 2>/dev/null || true
  fi

  # CRLF → LF: иначе source конфига даёт «: not found» и ломает порты в iptables
  if tr -d '\r' < "$tmp" > "${tmp}.lf" 2>/dev/null; then
    mv "${tmp}.lf" "$tmp"
  else
    rm -f "${tmp}.lf"
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

  # POLICY_*: стандарт (nfqws / 0) не трогаем; нестандартные — только по y/N
  if [ "$had_policy" -eq 1 ]; then
    pn_val=$(printf '%s' "${saved_policy_name#POLICY_NAME=}" | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    pe_val=$(printf '%s' "${saved_policy_exclude#POLICY_EXCLUDE=}" | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    policy_nondefault=0
    [ -n "$saved_policy_name" ] && [ "$pn_val" != "nfqws" ] && policy_nondefault=1
    [ -n "$saved_policy_exclude" ] && [ "$pe_val" != "0" ] && policy_nondefault=1

    if [ "$policy_nondefault" -eq 1 ]; then
      echo
      info "Сохранённые POLICY_* отличаются от стандартных (nfqws / 0):"
      [ -n "$saved_policy_name" ] && info "  $saved_policy_name"
      [ -n "$saved_policy_exclude" ] && info "  $saved_policy_exclude"
      if confirm_no "Восстановить эти POLICY_NAME / POLICY_EXCLUDE?"; then
        [ -n "$saved_policy_name" ] && restore_conf_var_line "$conf_dest" "POLICY_NAME" "$saved_policy_name"
        [ -n "$saved_policy_exclude" ] && restore_conf_var_line "$conf_dest" "POLICY_EXCLUDE" "$saved_policy_exclude"
        info "POLICY_* восстановлены."
      else
        info "Восстановление POLICY_* пропущено."
      fi
    fi
  fi

  echo
  info "=== Проверка ISP_INTERFACE / IPV6_ENABLED ==="
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

  # Восстановить привязку rkn.list в MODE_LIST, если она была до смены стратегии
  if [ "$had_rkn" -eq 1 ]; then
    echo
    info "=== Восстановление rkn.list в MODE_LIST ==="
    # skip_backup=1 — бэкап уже сделан перед заменой конфига стратегией
    if inject_rkn_into_mode_list "$ver" "$conf_dest" 1; then
      rkn_path=$(rkn_list_path "$ver" 2>/dev/null || true)
      if [ -n "$rkn_path" ] && [ ! -f "$rkn_path" ]; then
        warn "Файл $rkn_path отсутствует — скачайте через пункт меню «rkn.list»."
      fi
    fi
  fi

  echo
  service_restart "$(nfqws_init_path "$ver")"
  info "Сервис перезапущен."
}

# Метка стратегии из комментария: # general (SIMPLE FAKE ALT).bat -> nfqws2
# Возвращает текст в скобках как есть (для отображения).
detect_current_strategy() {
  local conf="$1"
  [ -f "$conf" ] || return 0
  grep -iE 'general[[:space:]]*\(' "$conf" 2>/dev/null | \
    sed -n 's/.*(\([^)]*\)).*/\1/p' | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Нормализация для сравнения: "SIMPLE FAKE ALT" / simple_fake_alt → simplefakealt
strategy_id_norm() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]_-'
}

# Восстановление конфига из .bak.* (nfqws.conf.bak.YYYYMMDDHHMMSS / nfqws2.conf.bak.…)
restore_conf_from_backup() {
  local ver="$1"
  local conf_dest conf_dir conf_base bak_list i f num selected count=0

  conf_dest=$(nfqws_conf_path "$ver")
  conf_dir=$(dirname "$conf_dest")
  conf_base=$(basename "$conf_dest")

  echo
  info "Резервные копии конфига ($conf_base) — NFQWS V${ver}:"
  # от свежего к старому (timestamp в имени: .bak.YYYYMMDDHHMMSS)
  bak_list=$(
    for f in "$conf_dir"/"$conf_base".bak.*; do
      [ -f "$f" ] || continue
      echo "$f"
    done | sort -r
  )
  count=0
  for f in $bak_list; do
    count=$((count + 1))
    # стратегия из комментария вида: #  general (ALT11).bat  ->  nfqws2
    strat=$(grep -iE 'general[[:space:]]*\(' "$f" 2>/dev/null | \
      sed -n 's/.*(\([^)]*\)).*/\1/p' | head -1 | tr -d '[:space:]')
    if [ -n "$strat" ]; then
      tag=" ($strat)"
    else
      tag=""
    fi
    if [ "$count" -eq 1 ]; then
      printf "  %s%2d) %s%s%s\n" "$YELLOW$BOLD" "$count" "$(basename "$f")" "$tag" "$NC"
    else
      printf "  %2d) %s%s\n" "$count" "$(basename "$f")" "$tag"
    fi
  done

  if [ "$count" -eq 0 ]; then
    warn "Резервные копии не найдены в $conf_dir"
    return 0
  fi

  echo "   0) Назад"
  ask "Номер файла для восстановления: "
  read -r num
  [ -z "$num" ] || [ "$num" = "0" ] && return 0

  i=1
  selected=""
  for f in $bak_list; do
    if [ "$i" = "$num" ]; then
      selected="$f"
      break
    fi
    i=$((i + 1))
  done
  [ -z "$selected" ] && { warn "Неверный номер"; return 1; }

  echo
  info "Восстановление из: $(basename "$selected")"
  info "В текущий конфиг:  $conf_dest"
  if ! confirm_yes "Восстановить этот бэкап?"; then
    info "Отменено."
    return 0
  fi

  if ! cp -a "$selected" "$conf_dest"; then
    error "Не удалось скопировать $selected → $conf_dest"
    return 1
  fi
  info "Конфиг восстановлен из $(basename "$selected")"

  echo
  info "=== Проверка ISP_INTERFACE / IPV6_ENABLED ==="
  fix_isp_interface "$conf_dest"

  echo
  service_restart "$(nfqws_init_path "$ver")"
  info "Сервис перезапущен."
}

menu_strategy() {
  need_nfqws_installed || return
  pick_nfqws_ver 0 || return

  local conf_dest current_id dir list i files f base num idx selected
  local cache_file has_cache
  conf_dest=$(nfqws_conf_path "$NFQWS_VER")
  current_id=$(detect_current_strategy "$conf_dest")
  [ -n "$current_id" ] && info "Текущая стратегия в конфиге: $current_id"

  dir="nfqws${NFQWS_VER}"
  echo
  info "Доступные стратегии ($dir):"
  list=$(list_strategies "$dir" || true)
  if [ -z "$list" ]; then
    warn "Не удалось получить список стратегий (сеть / GitHub)."
    warn "Пробуем зеркала CDN и offline-кэш; default — из nfqws или кэша."
  fi

  i=1
  files="default"
  cache_file=$(cache_strategy_path "$NFQWS_VER" "default")
  has_cache=0
  [ -f "$cache_file" ] && [ -s "$cache_file" ] && has_cache=1
  if [ -z "$current_id" ]; then
    printf "  %s%2d) default  (стандартная из репозитория nfqws)  <-- текущая?%s\n" "$GREEN$BOLD" "$i" "$NC"
  elif [ "$has_cache" -eq 1 ]; then
    printf "  %s%2d) default  (стандартная из репозитория nfqws)%s\n" "$CYAN" "$i" "$NC"
  else
    printf "  %2d) default  (стандартная из репозитория nfqws)\n" "$i"
  fi
  i=2

  # shellcheck disable=SC2086
  for f in $list; do
    base=$(echo "$f" | sed 's/\.conf$//' | tr '[:upper:]' '[:lower:]')
    cache_file=$(cache_strategy_path "$NFQWS_VER" "$f")
    has_cache=0
    [ -f "$cache_file" ] && [ -s "$cache_file" ] && has_cache=1
    # SIMPLE FAKE ALT ↔ simple_fake_alt (пробелы/подчёркивания не учитываем)
    if [ -n "$current_id" ] && [ "$(strategy_id_norm "$base")" = "$(strategy_id_norm "$current_id")" ]; then
      printf "  %s%2d) %s  <-- текущая%s\n" "$GREEN$BOLD" "$i" "$f" "$NC"
    elif [ "$has_cache" -eq 1 ]; then
      printf "  %s%2d) %s%s\n" "$CYAN" "$i" "$f" "$NC"
    else
      printf "  %2d) %s\n" "$i" "$f"
    fi
    files="$files $f"
    i=$((i + 1))
  done
  printf '  %s99) Восстановление из backup%s\n' "${YELLOW}${BOLD}" "$NC"
  echo "   0) Назад"
  ask "Номер стратегии: "
  read -r num
  [ -z "$num" ] || [ "$num" = "0" ] && return

  if [ "$num" = "99" ]; then
    restore_conf_from_backup "$NFQWS_VER"
    return
  fi

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
# 5. rkn.list (zapret4rocket) → lists + MODE_LIST (nfqws v1 / nfqws2)
# ---------------------------------------------------------------------------
RKN_LIST_URL="https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/master/extra_strats/TCP/RKN/List.txt"
# Зеркало (как в zapret4rocket/z4r) — если GitHub raw режется DPI
RKN_LIST_MIRROR_URL="http://mizulina.shit.vc:666/IndeecFOX/zapret4rocket/master/extra_strats/TCP/RKN/List.txt"

# Аргумент --hostlist=.../rkn.list для указанной версии nfqws
rkn_hostlist_arg() {
  case "$1" in
    1) echo "--hostlist=/opt/etc/nfqws/rkn.list" ;;
    2) echo "--hostlist=/opt/etc/nfqws2/lists/rkn.list" ;;
    *) return 1 ;;
  esac
}

# Путь к rkn.list для версии
rkn_list_path() {
  case "$1" in
    1) echo "/opt/etc/nfqws/rkn.list" ;;
    2) echo "/opt/etc/nfqws2/lists/rkn.list" ;;
    *) return 1 ;;
  esac
}

# Есть ли в конфиге привязка rkn.list (MODE_LIST / hostlist)
conf_has_rkn_hostlist() {
  local conf="$1" ver="$2" arg
  arg=$(rkn_hostlist_arg "$ver") || return 1
  [ -f "$conf" ] || return 1
  grep -qF -- "$arg" "$conf" 2>/dev/null
}

# Вставить --hostlist=.../rkn.list в MODE_LIST конфига (идемпотентно).
# Возвращает 0 если уже было / успешно добавлено, 1 при ошибке.
# $1=ver  $2=conf (опционально; по умолчанию nfqws_conf_path)
# $3=1 — не делать backup (уже сделан, напр. в apply_strategy)
inject_rkn_into_mode_list() {
  local ver="$1" conf="${2:-}" skip_backup="${3:-0}" hostlist_arg user_list tmp_conf
  hostlist_arg=$(rkn_hostlist_arg "$ver") || return 1
  [ -z "$conf" ] && conf=$(nfqws_conf_path "$ver")
  [ -f "$conf" ] || { warn "Конфиг не найден: $conf — MODE_LIST не обновлён."; return 1; }

  case "$ver" in
    1) user_list="/opt/etc/nfqws/user.list" ;;
    2) user_list="/opt/etc/nfqws2/lists/user.list" ;;
  esac

  # уже есть
  if grep -qF -- "$hostlist_arg" "$conf" 2>/dev/null; then
    info "MODE_LIST уже содержит $hostlist_arg"
    return 0
  fi

  if grep -qE '^[[:space:]]*MODE_LIST=' "$conf" 2>/dev/null; then
    [ "$skip_backup" = "1" ] || backup_file "$conf"
    # Вставляем --hostlist=...rkn.list перед закрывающей кавычкой.
    # awk надёжнее busybox sed (пробелы, пустые кавычки, CRLF, single quotes).
    tmp_conf="/tmp/nfqws-mode-$$.conf"
    awk -v arg="$hostlist_arg" '
      BEGIN { done=0 }
      /^[[:space:]]*MODE_LIST=/ && !done {
        line=$0
        sub(/\r$/, "", line)
        # MODE_LIST="content"  → MODE_LIST="content arg"  (или пустые кавычки)
        if (match(line, /^[[:space:]]*MODE_LIST="/)) {
          prefix = substr(line, 1, RSTART+RLENGTH-1)  # включая открывающую "
          rest = substr(line, RSTART+RLENGTH)
          if (match(rest, /"/)) {
            content = substr(rest, 1, RSTART-1)
            gsub(/[ \t]+$/, "", content)
            if (content == "")
              print prefix arg "\""
            else
              print prefix content " " arg "\""
          } else {
            print line " " arg
          }
        } else {
          print line " " arg
        }
        done=1
        next
      }
      { print }
    ' "$conf" > "$tmp_conf" && mv "$tmp_conf" "$conf"
    if grep -qF -- "$hostlist_arg" "$conf" 2>/dev/null; then
      info "В MODE_LIST добавлено: $hostlist_arg"
      return 0
    fi
    warn "Не удалось изменить MODE_LIST автоматически — добавьте вручную:"
    warn "  MODE_LIST=\"... $hostlist_arg\""
    rm -f "$tmp_conf"
    return 1
  fi

  # MODE_LIST отсутствует — создаём с user.list + rkn
  [ "$skip_backup" = "1" ] || backup_file "$conf"
  printf '\nMODE_LIST="--hostlist=%s %s"\n' "$user_list" "$hostlist_arg" >> "$conf"
  info "MODE_LIST создан с user.list и rkn.list"
  return 0
}

update_rkn_list() {
  need_nfqws_installed || return
  pick_nfqws_ver 1 || return

  local tmp="/tmp/nfqws-rkn-$$.txt" cleaned="/tmp/nfqws-rkn-clean-$$.txt" count
  local skip_download=0

  # Проверяем существующие файлы (любая из выбранных версий)
  local check_dest=""
  case "$NFQWS_VER" in
    1)   check_dest="/opt/etc/nfqws/rkn.list" ;;
    2)   check_dest="/opt/etc/nfqws2/lists/rkn.list" ;;
    both) check_dest="/opt/etc/nfqws2/lists/rkn.list"
          [ -f "/opt/etc/nfqws/rkn.list" ] && check_dest="/opt/etc/nfqws/rkn.list"
          ;;
  esac

  if [ -n "$check_dest" ] && [ -f "$check_dest" ]; then
    # Не считаем 125k строк через grep — на роутере это долго.
    # Размер в КБ (мгновенно); точный count — только после скачивания.
    local existing_kb
    existing_kb=$(wc -c < "$check_dest" 2>/dev/null | tr -d ' ')
    if [ -n "$existing_kb" ] && [ "$existing_kb" -gt 0 ] 2>/dev/null; then
      existing_kb=$((existing_kb / 1024))
    else
      existing_kb="?"
    fi
    info "Файл уже существует: $check_dest (${existing_kb} КБ)"
    if ! confirm_no "Обновить rkn.list?"; then
      info "Обновление списка пропущено."
      skip_download=1
    fi
  fi

  if [ "$skip_download" -eq 0 ]; then
    info "Скачивание rkn.list (zapret4rocket, ~2 МБ) ..."
    # Большой файл: сначала зеркала (часто быстрее при DPI), увеличенный таймаут
    local _old_max="$CURL_MAX_TIME" _old_wget="$WGET_TIMEOUT" _ok=0 _u
    CURL_MAX_TIME="${CURL_MAX_TIME_LARGE:-180}"
    WGET_TIMEOUT="$CURL_MAX_TIME"
    for _u in \
      "$RKN_LIST_MIRROR_URL" \
      "https://cdn.jsdelivr.net/gh/IndeecFOX/zapret4rocket@master/extra_strats/TCP/RKN/List.txt" \
      "https://fastly.jsdelivr.net/gh/IndeecFOX/zapret4rocket@master/extra_strats/TCP/RKN/List.txt" \
      "https://ghproxy.net/https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/master/extra_strats/TCP/RKN/List.txt" \
      "$RKN_LIST_URL"
    do
      [ -n "$_u" ] || continue
      info "URL: $_u"
      if download_file_progress "$_u" "$tmp"; then
        # sanity: rkn.list должен быть заметного размера (>100 КБ)
        local _sz
        _sz=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
        if [ -n "$_sz" ] && [ "$_sz" -gt 100000 ] 2>/dev/null; then
          info "Получено: $((_sz / 1024)) КБ"
          _ok=1
          break
        fi
        warn "Скачано слишком мало байт ($_sz) — пробуем следующий источник..."
        rm -f "$tmp"
      else
        warn "Не удалось с этого URL — следующий источник..."
      fi
    done
    CURL_MAX_TIME="$_old_max"
    WGET_TIMEOUT="$_old_wget"
    if [ "$_ok" -ne 1 ]; then
      error "Не удалось скачать rkn.list (все источники недоступны или таймаут)."
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
  fi

  # Применить к выбранной версии (или обеим)
  apply_rkn_for_ver() {
    local ver="$1"
    local dest init_script conf need_restart=0 had_rkn=0

    dest=$(rkn_list_path "$ver") || return 1
    init_script=$(nfqws_init_path "$ver")
    conf=$(nfqws_conf_path "$ver")

    if [ "$skip_download" -eq 0 ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$cleaned" "$dest"
      info "Записано: $dest ($count строк)"
      need_restart=1
    fi

    # Была ли привязка до inject (чтобы не перезапускать зря)
    conf_has_rkn_hostlist "$conf" "$ver" && had_rkn=1

    inject_rkn_into_mode_list "$ver" "$conf" || true

    # Перезапуск: обновили файл списка ИЛИ только что добавили в MODE_LIST
    if [ "$need_restart" -eq 1 ] || [ "$had_rkn" -eq 0 ]; then
      # had_rkn=0 → inject мог добавить (или conf отсутствовал) → restart
      if [ "$had_rkn" -eq 0 ] && conf_has_rkn_hostlist "$conf" "$ver"; then
        need_restart=1
      fi
    fi

    if [ "$need_restart" -eq 1 ]; then
      service_restart "$init_script"
      info "Сервис перезапущен ($init_script)."
    else
      info "Изменений нет — перезапуск сервиса не требуется (v$ver)."
    fi
  }

  case "$NFQWS_VER" in
    1)   apply_rkn_for_ver 1 ;;
    2)   apply_rkn_for_ver 2 ;;
    both)
      apply_rkn_for_ver 1
      apply_rkn_for_ver 2
      ;;
  esac

  rm -f "$tmp" "$cleaned"
}

# ---------------------------------------------------------------------------
# 6. DoT/DoH bypass strategy в NFQWS_ARGS_CUSTOM
# ---------------------------------------------------------------------------
DOT_DOH_STRATEGY='               #DNS
                    --filter-tcp=443,853 --filter-l7=http,tls
                    --hostlist-domains=dot.pub,doh.pub,controld.com,opendns.com,anycast.censurfridns.dk,dns.alidns.com,libredns.gr,cloudflare-dns.com,one.one.one.one,opennameserver.org,cleanbrowsing.org,dns.adguard-dns.com,dns.comss.one,dns.nextdns.io,freedns.controld.com,dns10.quad9.net,dns.google
                    --out-range=-d10
                    --payload=tls_client_hello,http_req
                    --lua-desync=multisplit:pos=sniext+4,midsld-1:seqovl=4
                    --lua-desync=fake:blob=tls_google:tcp_seq=-10000:tcp_md5:tls_mod=rnd,dupsid,sni=ozon.ru:repeats=3
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

  ndmc_cli "show dns-proxy" 2>/dev/null | awk -v c_reset="$NC" \
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
  if ndmc_cli "system configuration save" > /dev/null 2>&1; then
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
  ndmc_cli "$cmd" > /dev/null 2>&1 || warn "ndmc вернул ошибку при добавлении DoT $ip"
}

apply_doh() {
  local uri="$1" domain="$2" cmd
  cmd="dns-proxy https upstream $uri"
  [ -n "$domain" ] && cmd="$cmd domain $domain"
  printf '%s\n' "${CYAN}Применение DoH ($uri):${NC} ndmc -c \"$cmd\""
  ndmc_cli "$cmd" > /dev/null 2>&1 || warn "ndmc вернул ошибку при добавлении DoH $uri"
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
9|Google Primary|8.8.8.8|dns.google|
10|Google Secondary|8.8.4.4|dns.google|
11|Quad9 Primary|9.9.9.9|dns.quad9.net|
12|Quad9 Secondary|149.112.112.112|dns.quad9.net|
13|CleanBrowsing Sec Filter 1|185.228.168.9|security-filter-dns.cleanbrowsing.org|853
14|CleanBrowsing Sec Filter 2|185.228.169.9|security-filter-dns2.cleanbrowsing.org|853
15|OpenDNS Primary|208.67.222.222|dns.opendns.com|
16|OpenDNS Secondary|208.67.220.220|dns.opendns.com|
17|AdGuard Default|94.140.14.14|dns.adguard-dns.com|
18|AdGuard Family|94.140.14.15|family.adguard-dns.com|
19|ControlD Free|p0.freedns.controld.com|p0.freedns.controld.com|
20|DNS.SB Primary|185.222.222.222|dot.sb|
21|DNS.SB Secondary|45.11.45.11|dot.sb|
22|dns0.eu|dns0.eu|dns0.eu|
23|DNS4EU Protective|protective.joindns4.eu|protective.joindns4.eu|
24|DNS4EU Unfiltered|unfiltered.joindns4.eu|unfiltered.joindns4.eu|
25|OpenNameServer ns1|217.160.70.42|ns1.opennameserver.org|
26|OpenNameServer ns2|213.202.211.221|ns2.opennameserver.org|
27|OpenNameServer ns3|81.169.136.222|ns3.opennameserver.org|
28|OpenNameServer ns4|185.181.61.24|ns4.opennameserver.org|
29|IIJ Japan|public.dns.iij.jp|public.dns.iij.jp|
30|Alibaba DNS|dns.alidns.com|dns.alidns.com|
31|DNSPod|dot.pub|dot.pub|
32|Xbox-DNS|xbox-dns.ru|xbox-dns.ru|
33|Comss DNS|dns.comss.one|dns.comss.one|
34|Malw Link|dns.malw.link|dns.malw.link|
35|NullsProxy|dns.nullsproxy.com|dns.nullsproxy.com|
36|Cloudflare Gateway|5u35p8m9i7.cloudflare-gateway.com|5u35p8m9i7.cloudflare-gateway.com|
37|Geo Hide|geohide.ru|geohide.ru|
EOF
}

# Data-driven DoH: N|label|uri
doh_servers_data() {
  cat <<'EOF'
1|Yandex Primary|https://77.88.8.8/dns-query
2|Yandex Secondary|https://77.88.8.1/dns-query
3|Cloudflare|https://cloudflare-dns.com/dns-query
4|Google|https://dns.google/dns-query
5|Quad9|https://dns.quad9.net/dns-query
6|CleanBrowsing|https://doh.cleanbrowsing.org/doh/security-filter/
7|OpenDNS|https://doh.opendns.com/dns-query
8|AdGuard Default|https://dns.adguard-dns.com/dns-query
9|AdGuard Family|https://family.adguard-dns.com/dns-query
10|ControlD Free|https://freedns.controld.com/p0
11|DNS.SB|https://doh.dns.sb/dns-query
12|dns0.eu|https://dns0.eu/
13|DNS4EU Protective|https://protective.joindns4.eu/dns-query
14|DNS4EU Unfiltered|https://unfiltered.joindns4.eu/dns-query
15|OpenNameServer ns1|https://ns1.opennameserver.org/dns-query
16|OpenNameServer ns2|https://ns2.opennameserver.org/dns-query
17|OpenNameServer ns3|https://ns3.opennameserver.org/dns-query
18|OpenNameServer ns4|https://ns4.opennameserver.org/dns-query
19|IIJ Japan|https://public.dns.iij.jp/dns-query
20|Alibaba DNS|https://dns.alidns.com/dns-query
21|DNSPod|https://doh.pub/dns-query
22|Xbox-DNS|https://xbox-dns.ru/dns-query
23|Comss DNS|https://dns.comss.one/dns-query
24|Malw Link|https://dns.malw.link/dns-query
25|NullsProxy|https://dns.nullsproxy.com/dns-query
26|Cloudflare Gateway|https://5u35p8m9i7.cloudflare-gateway.com/dns-query
27|Geo Hide|https://dns.geohide.ru/dns-query
EOF
}

print_dns_menu_header() {
  # $1 = section markers: lines "N|section_title" before item N
  :
}

add_dot_menu() {
  echo
  printf '%s\n' "${BOLD}Выбор DoT серверов (можно несколько через запятую, напр. 1,3,20):${NC}"
  printf '%s\n' " ${YELLOW}--- Яндекс & Cloudflare & Google ---${NC}"
  echo " 1) Yandex Primary (77.88.8.8)"
  echo " 2) Yandex Secondary (77.88.8.1)"
  echo " 3) Cloudflare Standard Primary (1.1.1.1)"
  echo " 4) Cloudflare Standard Secondary (1.0.0.1)"
  echo " 5) Cloudflare Malware Primary (1.1.1.2)"
  echo " 6) Cloudflare Malware Secondary (1.0.0.2)"
  echo " 7) Cloudflare Malware+Adult Primary (1.1.1.3)"
  echo " 8) Cloudflare Malware+Adult Secondary (1.0.0.3)"
  echo " 9) Google Primary (8.8.8.8)"
  echo "10) Google Secondary (8.8.4.4)"
  printf '%s\n' " ${YELLOW}--- Безопасность & Приватность ---${NC}"
  echo "11) Quad9 Primary (9.9.9.9)"
  echo "12) Quad9 Secondary (149.112.112.112)"
  echo "13) CleanBrowsing Sec Filter 1 (185.228.168.9)"
  echo "14) CleanBrowsing Sec Filter 2 (185.228.169.9)"
  echo "15) OpenDNS Primary (208.67.222.222)"
  echo "16) OpenDNS Secondary (208.67.220.220)"
  echo "17) AdGuard Default (94.140.14.14)"
  echo "18) AdGuard Family (94.140.14.15)"
  echo "19) ControlD Free (p0.freedns.controld.com)"
  echo "20) DNS.SB Primary (185.222.222.222)"
  echo "21) DNS.SB Secondary (45.11.45.11)"
  echo "22) dns0.eu (dns0.eu)"
  echo "23) DNS4EU Protective (protective.joindns4.eu)"
  echo "24) DNS4EU Unfiltered (unfiltered.joindns4.eu)"
  printf '%s\n' " ${YELLOW}--- OpenNameServer ---${NC}"
  echo "25) OpenNameServer ns1 (217.160.70.42)"
  echo "26) OpenNameServer ns2 (213.202.211.221)"
  echo "27) OpenNameServer ns3 (81.169.136.222)"
  echo "28) OpenNameServer ns4 (185.181.61.24)"
  printf '%s\n' " ${YELLOW}--- Япония & Китай ---${NC}"
  echo "29) IIJ Japan (public.dns.iij.jp)"
  echo "30) Alibaba DNS (dns.alidns.com)"
  echo "31) DNSPod (dot.pub)"
  printf '%s\n' " ${GREEN}--- Proxy-DNS (Обход блокировок) ---${NC}"
  echo "32) Xbox-DNS (xbox-dns.ru)"
  echo "33) Comss DNS (dns.comss.one)"
  echo "34) Malw Link (dns.malw.link)"
  echo "35) NullsProxy (dns.nullsproxy.com)"
  echo "36) Cloudflare Gateway (5u35p8m9i7.cloudflare-gateway.com)"
  echo "37) Geo Hide (geohide.ru)"
  printf '%s\n' " ${YELLOW}--- Свой вариант ---${NC}"
  echo "38) Ввести вручную (IP / Port / SNI)"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  ask "Привязать выбранные к домену? (пусто для всех): "
  read -r domain

  local added_any=0 choice num label ip sni port
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    if [ "$choice" = "38" ]; then
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
  printf '%s\n' " ${YELLOW}--- Яндекс & Cloudflare & Google ---${NC}"
  echo " 1) Yandex Primary (https://77.88.8.8/dns-query)"
  echo " 2) Yandex Secondary (https://77.88.8.1/dns-query)"
  echo " 3) Cloudflare (https://cloudflare-dns.com/dns-query)"
  echo " 4) Google (https://dns.google/dns-query)"
  printf '%s\n' " ${YELLOW}--- Безопасность & Приватность ---${NC}"
  echo " 5) Quad9 (https://dns.quad9.net/dns-query)"
  echo " 6) CleanBrowsing (https://doh.cleanbrowsing.org/doh/security-filter/)"
  echo " 7) OpenDNS (https://doh.opendns.com/dns-query)"
  echo " 8) AdGuard Default (https://dns.adguard-dns.com/dns-query)"
  echo " 9) AdGuard Family (https://family.adguard-dns.com/dns-query)"
  echo "10) ControlD Free (https://freedns.controld.com/p0)"
  echo "11) DNS.SB (https://doh.dns.sb/dns-query)"
  echo "12) dns0.eu (https://dns0.eu/)"
  echo "13) DNS4EU Protective (https://protective.joindns4.eu/dns-query)"
  echo "14) DNS4EU Unfiltered (https://unfiltered.joindns4.eu/dns-query)"
  printf '%s\n' " ${YELLOW}--- OpenNameServer ---${NC}"
  echo "15) OpenNameServer ns1 (https://ns1.opennameserver.org/dns-query)"
  echo "16) OpenNameServer ns2 (https://ns2.opennameserver.org/dns-query)"
  echo "17) OpenNameServer ns3 (https://ns3.opennameserver.org/dns-query)"
  echo "18) OpenNameServer ns4 (https://ns4.opennameserver.org/dns-query)"
  printf '%s\n' " ${YELLOW}--- Япония & Китай ---${NC}"
  echo "19) IIJ Japan (https://public.dns.iij.jp/dns-query)"
  echo "20) Alibaba DNS (https://dns.alidns.com/dns-query)"
  echo "21) DNSPod (https://doh.pub/dns-query)"
  printf '%s\n' " ${GREEN}--- Proxy-DNS (Обход блокировок) ---${NC}"
  echo "22) Xbox-DNS (https://xbox-dns.ru/dns-query)"
  echo "23) Comss DNS Keenetic/MikroTik (https://dns.comss.one/dns-query)"
  echo "24) Malw Link (https://dns.malw.link/dns-query)"
  echo "25) NullsProxy (https://dns.nullsproxy.com/dns-query)"
  echo "26) Cloudflare Gateway (https://5u35p8m9i7.cloudflare-gateway.com/dns-query)"
  echo "27) Geo Hide (https://dns.geohide.ru/dns-query)"
  printf '%s\n' " ${YELLOW}--- Свой вариант ---${NC}"
  echo "28) Ввести вручную (произвольный URI)"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  ask "Привязать выбранные к домену? (пусто для всех): "
  read -r domain

  local added_any=0 choice line uri
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    if [ "$choice" = "28" ]; then
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
  echo " 3) CleanBrowsing DoT (185.228.168.9 + SNI) ➔ cdninstagram.com"
  echo " 4) CleanBrowsing DoH (doh.cleanbrowsing.org) ➔ cdninstagram.com"
  echo " 5) sw.ext.io DoT ➔ rutor.is & rutor.info"
  echo " 6) Malw Link DoH (dns.malw.link) ➔ ntc.party"
  echo " 7) Xbox-DNS DoT ➔ gql.twitch.tv & usher.ttvnw.net"
  echo " 8) Xbox-DNS DoH ➔ gql.twitch.tv & usher.ttvnw.net"
  echo " 9) NullsProxy DoT ➔ Supercell (Brawl/CoC/CR)"
  echo "10) NullsProxy DoH ➔ Supercell (Brawl/CoC/CR)"
  echo "11) Ввести свой домен и выбрать сервер"
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
      3) apply_dot "185.228.168.9" "security-filter-dns.cleanbrowsing.org" "cdninstagram.com" "853"; added_any=1 ;;
      4) apply_doh "https://doh.cleanbrowsing.org/doh/security-filter/" "cdninstagram.com"; added_any=1 ;;
      5)
        apply_dot "sw.ext.io" "" "rutor.is"
        apply_dot "sw.ext.io" "" "rutor.info"
        added_any=1
        ;;
      6) apply_doh "https://dns.malw.link/dns-query" "ntc.party"; added_any=1 ;;
      7)
        apply_dot "xbox-dns.ru" "xbox-dns.ru" "gql.twitch.tv"
        apply_dot "xbox-dns.ru" "xbox-dns.ru" "usher.ttvnw.net"
        added_any=1
        ;;
      8)
        apply_doh "https://xbox-dns.ru/dns-query" "gql.twitch.tv"
        apply_doh "https://xbox-dns.ru/dns-query" "usher.ttvnw.net"
        added_any=1
        ;;
      9)
        # Supercell via NullsProxy DoT
        apply_dot "dns.nullsproxy.com" "dns.nullsproxy.com" "supercell.com"
        apply_dot "dns.nullsproxy.com" "dns.nullsproxy.com" "supercellid.com"
        apply_dot "dns.nullsproxy.com" "dns.nullsproxy.com" "brawlstarsgame.com"
        apply_dot "dns.nullsproxy.com" "dns.nullsproxy.com" "clashofclans.com"
        apply_dot "dns.nullsproxy.com" "dns.nullsproxy.com" "clashroyaleapp.com"
        added_any=1
        ;;
      10)
        # Supercell via NullsProxy DoH
        apply_doh "https://dns.nullsproxy.com/dns-query" "supercell.com"
        apply_doh "https://dns.nullsproxy.com/dns-query" "supercellid.com"
        apply_doh "https://dns.nullsproxy.com/dns-query" "brawlstarsgame.com"
        apply_doh "https://dns.nullsproxy.com/dns-query" "clashofclans.com"
        apply_doh "https://dns.nullsproxy.com/dns-query" "clashroyaleapp.com"
        added_any=1
        ;;
      11)
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

  ndmc_cli "show dns-proxy" 2>/dev/null | awk '
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
    if ndmc_cli "$cmd" > /dev/null 2>&1; then
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
# 8. Обновление hosts (статические записи ip host через ndmc)
# ---------------------------------------------------------------------------
menu_update_hosts() {
  if ! command -v ndmc >/dev/null 2>&1; then
    error "ndmc не найден. Функция доступна только на Keenetic/Netcraze OS."
    return 1
  fi

  local hosts_url="${RAW_BASE}/hosts"
  local tmp="/tmp/nfqws-hosts-$$.txt"
  local sec_file="/tmp/nfqws-hosts-sec-$$.txt"

  info "Загрузка hosts..."
  if ! download_file "$hosts_url" "$tmp"; then
    error "Не удалось загрузить $hosts_url"
    return 1
  fi

  # Секции = строки, начинающиеся с # (без пустых)
  awk '/^#/ {
    name = $0
    sub(/^#+[ \t]*/, "", name)
    gsub(/[ \t\r]+$/, "", name)
    if (name != "") print name
  }' "$tmp" > "$sec_file"

  if [ ! -s "$sec_file" ]; then
    error "В файле hosts нет секций (комментариев #...)"
    rm -f "$tmp" "$sec_file"
    return 1
  fi

  local n_sec
  n_sec=$(wc -l < "$sec_file" | tr -d ' ')

  echo
  printf '%s\n' "${BOLD}Какие записи добавить в hosts (можно несколько через запятую или все)?${NC}"
  local i=1
  while IFS= read -r sec || [ -n "$sec" ]; do
    printf ' %s) #%s\n' "$i" "$sec"
    i=$((i + 1))
  done < "$sec_file"
  local all_num=$i
  printf ' %s) Все\n' "$all_num"
  printf ' %s88) Удалить записи%s\n' "$RED" "$NC"
  printf ' %s99) Просмотреть записи%s\n' "$YELLOW" "$NC"
  printf ' 0) Отмена\n'
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices

  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && {
    rm -f "$tmp" "$sec_file"
    return 0
  }

  # 99 — просмотреть текущие записи ip host на роутере
  local want_view=0
  for c in $(echo "$raw_choices" | tr ',;' '  '); do
    [ "$c" = "99" ] && want_view=1 && break
  done
  if [ "$want_view" -eq 1 ]; then
    echo
    printf '%s\n' "${BOLD}${YELLOW}Текущие записи ip host на роутере:${NC}"
    printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
    local view_out view_cnt=0 line
    # Keenetic 4.2+: show running-config / show run содержат строки «ip host DOMAIN IP»
    view_out=$(ndmc_cli "show running-config" 2>/dev/null) || view_out=""
    if [ -z "$view_out" ]; then
      view_out=$(ndmc_cli "show run" 2>/dev/null) || view_out=""
    fi
    if [ -n "$view_out" ]; then
      view_cnt=$(printf '%s\n' "$view_out" | grep -cE '^[[:space:]]*ip host[[:space:]]' || true)
      printf '%s\n' "$view_out" | grep -E '^[[:space:]]*ip host[[:space:]]' | while IFS= read -r line || [ -n "$line" ]; do
        set -- $line
        if [ "$1" = "ip" ] && [ "$2" = "host" ] && [ -n "$3" ] && [ -n "$4" ]; then
          printf '  %s%-40s%s %s➔%s %s\n' "$CYAN" "$3" "$NC" "$DIM" "$NC" "$4"
        else
          printf '  %s\n' "$line"
        fi
      done
    fi
    if [ -z "$view_out" ] || [ "${view_cnt:-0}" -eq 0 ]; then
      printf '  %s— записей ip host нет —%s\n' "$DIM" "$NC"
    else
      printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
      info "Всего: $view_cnt"
    fi
    rm -f "$tmp" "$sec_file"
    return 0
  fi

  # 88 — удалить все домены из hosts-файла
  local want_delete=0
  for c in $(echo "$raw_choices" | tr ',;' '  '); do
    [ "$c" = "88" ] && want_delete=1 && break
  done
  if [ "$want_delete" -eq 1 ]; then
    local domains="/tmp/nfqws-hosts-dom-$$.txt"
    awk '
      /^#/ { next }
      NF >= 2 {
        domain = $2
        if (domain == "" || domain == "." || domain ~ /^\.+$/) next
        if (!(domain in seen)) {
          seen[domain] = 1
          print domain
        }
      }
    ' "$tmp" > "$domains"

    if [ ! -s "$domains" ]; then
      warn "В файле hosts нет доменов для удаления."
      rm -f "$tmp" "$sec_file" "$domains"
      return 0
    fi

    if ! confirm_no "Удалить все домены из hosts ($(wc -l < "$domains" | tr -d ' ') шт.)?"; then
      rm -f "$tmp" "$sec_file" "$domains"
      return 0
    fi

    local removed=0 failed=0 domain cmd
    while IFS= read -r domain || [ -n "$domain" ]; do
      [ -z "$domain" ] && continue
      cmd="no ip host $domain"
      printf '%s\n' "${CYAN}  ndmc -c \"$cmd\"${NC}"
      if ndmc_cli "$cmd" > /dev/null 2>&1; then
        removed=$((removed + 1))
      else
        warn "  ошибка: $domain"
        failed=$((failed + 1))
      fi
    done < "$domains"

    info "Удалено: $removed, ошибок: $failed"
    if [ "$removed" -gt 0 ] || [ "$failed" -gt 0 ]; then
      dns_save_config
    fi
    rm -f "$tmp" "$sec_file" "$domains"
    info "Готово."
    return 0
  fi

  # Нормализуем выбор: запятые/пробелы → список номеров
  local choices selected_all=0
  choices=$(echo "$raw_choices" | tr ',;' '  ' | tr -s ' ')

  for c in $choices; do
    case "$c" in
      "$all_num"|all|все|ALL) selected_all=1; break ;;
    esac
  done

  # Список выбранных имён секций
  local selected_secs=""
  if [ "$selected_all" -eq 1 ]; then
    selected_secs=$(cat "$sec_file")
  else
    for c in $choices; do
      case "$c" in
        *[!0-9]*) continue ;;
      esac
      [ "$c" -ge 1 ] 2>/dev/null && [ "$c" -le "$n_sec" ] 2>/dev/null || continue
      local name
      name=$(sed -n "${c}p" "$sec_file")
      [ -n "$name" ] && selected_secs="$selected_secs
$name"
    done
  fi

  selected_secs=$(printf '%s\n' "$selected_secs" | sed '/^$/d')
  if [ -z "$selected_secs" ]; then
    warn "Ничего не выбрано."
    rm -f "$tmp" "$sec_file"
    return 0
  fi

  local pairs="/tmp/nfqws-hosts-pairs-$$.txt"
  : > "$pairs"

  # Собираем IP\tDOMAIN: только IPv4, валидный домен (Keenetic ip host ≈64 записей)
  local sec
  for sec in $selected_secs; do
    [ -z "$sec" ] && continue
    info "Секция: #$sec"
    awk -v sec="$sec" '
      BEGIN { insec=0 }
      /^#/ {
        name = $0
        sub(/^#+[ \t]*/, "", name)
        gsub(/[ \t\r]+$/, "", name)
        insec = (name == sec) ? 1 : 0
        next
      }
      insec && NF >= 2 {
        ip = $1
        domain = $2
        # IPv6 не поддерживается командой ip host
        if (ip ~ /:/) next
        # битые/пустые домены (objects..com, .com, my..org)
        if (domain == "" || domain ~ /^\./ || domain ~ /\.\./ || domain !~ /\./) next
        print ip "\t" domain
      }
    ' "$tmp" >> "$pairs"
  done

  if [ ! -s "$pairs" ]; then
    warn "В выбранных секциях нет валидных записей IPv4 DOMAIN."
    rm -f "$tmp" "$sec_file" "$pairs"
    return 0
  fi

  # Один IP на домен (последний) — ip host хранит одну запись на имя
  local pairs_uniq="/tmp/nfqws-hosts-uniq-$$.txt"
  awk -F '\t' '{ dom[$2] = $1 } END { for (d in dom) print dom[d] "\t" d }' "$pairs" > "$pairs_uniq"

  local n_pairs
  n_pairs=$(wc -l < "$pairs_uniq" | tr -d ' ')
  if [ "$n_pairs" -gt 64 ]; then
    warn "Keenetic допускает до 64 записей ip host (сейчас $n_pairs). Часть может не добавиться."
  fi

  local added=0 failed=0
  local ip domain cmd
  while IFS="$(printf '\t')" read -r ip domain || [ -n "$ip" ]; do
    [ -z "$ip" ] || [ -z "$domain" ] && continue
    cmd="ip host $domain $ip"
    printf '%s\n' "${CYAN}  ndmc -c \"$cmd\"${NC}"
    if ndmc_cli "$cmd" > /dev/null 2>&1; then
      added=$((added + 1))
    else
      warn "  ошибка: $domain → $ip"
      failed=$((failed + 1))
    fi
  done < "$pairs_uniq"

  info "Добавлено: $added, ошибок: $failed (уникальных доменов: $n_pairs)"
  if [ "$added" -gt 0 ] || [ "$failed" -gt 0 ]; then
    dns_save_config
  fi

  rm -f "$tmp" "$sec_file" "$pairs" "$pairs_uniq"
  info "Готово."
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
  # путь основного бинарника не печатаем здесь — его уже показывает menu_dpi_detector
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
  info "Запуск установщика..."
  if command -v curl >/dev/null 2>&1; then
    curl -L -s "$KEENKIT_INSTALL_URL" > /tmp/keenkit-install.sh || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO /tmp/keenkit-install.sh "$KEENKIT_INSTALL_URL" || return 1
  else
    error "Нужны curl или wget."
    return 1
  fi
  if [ -c /dev/tty ]; then
    sh /tmp/keenkit-install.sh < /dev/tty > /dev/tty 2>&1 || true
  else
    sh /tmp/keenkit-install.sh || true
  fi
  rm -f /tmp/keenkit-install.sh 2>/dev/null || true
  drain_stdin
  info "Установщик KeenKit завершил работу."
}

# Feedly opkg-архитектура для tg-ws-proxy (spatiumstas/feedly)
# aarch64-3.10 | armv7-3.2 | mips-3.4 | mipsel-3.4
feedly_arch() {
  local raw
  raw=$(opkg print-architecture 2>/dev/null | sort -k3 -nr | awk '$2!="all"{print $2;exit}')
  case "$raw" in
    aarch64-3.10|armv7-3.2|mips-3.4|mipsel-3.4) echo "$raw" ;;
    aarch64*|arm64*) echo "aarch64-3.10" ;;
    armv7*|arm*)     echo "armv7-3.2" ;;
    mipsel*)         echo "mipsel-3.4" ;;
    mips*)           echo "mips-3.4" ;;
    *)               echo "" ;;
  esac
}

menu_tg_ws_proxy() {
  echo
  info "TG WS Proxy Go (tg-ws-proxy)"
  if is_installed "tg-ws-proxy"; then
    opkg_install_or_upgrade tg-ws-proxy
  else
    info "Пакет не установлен — установка..."
    local farch
    farch=$(feedly_arch)
    if [ -z "$farch" ]; then
      error "Неподдерживаемая архитектура для tg-ws-proxy (нужны: aarch64-3.10, armv7-3.2, mips-3.4, mipsel-3.4)."
      error "Определено: $(opkg print-architecture 2>/dev/null | tr '\n' ' ')"
      return 1
    fi
    info "Архитектура feedly: $farch"
    # Репозиторий spatiumstas/feedly (тот же, что add-repo.sh)
    ensure_opkg_repo "feedly_${farch}" "https://spatiumstas.github.io/feedly/${farch}" || {
      error "Не удалось добавить репозиторий feedly. Проверьте доступ к github.io (DPI?)."
      return 1
    }
    if ! opkg install tg-ws-proxy; then
      error "opkg install tg-ws-proxy не удался."
      warn "Проверьте: opkg update && opkg list | grep tg-ws"
      warn "Или установите вручную IPK из https://github.com/spatiumstas/tg-ws-proxy-go/releases"
      warn "  (файл вида tg-ws-proxy_*-entware_${farch}.ipk)"
      return 1
    fi
    refresh_opkg_cache
    if is_installed "tg-ws-proxy"; then
      info "Установка завершена: $(pkg_version tg-ws-proxy)"
    else
      error "Пакет после установки не найден в opkg list-installed."
      return 1
    fi
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

# ---------------------------------------------------------------------------
# TG WS Proxy (Rust) — установка, подбор параметров и сквозная проверка
# ---------------------------------------------------------------------------
# В opkg этого пакета нет: это релизный бинарь с GitHub, и ставит его штатный
# install.sh проекта — он же пишет config.conf и Entware-инициализацию под
# rc.unslung. Меню добавляет то, чего у установщика быть не может: замер этой
# сети, подбор параметров под неё и проверку, что выданная ссылка работает
# целиком, а не «порт открыт».

TG_WS_PROXY_RS_BIN="/opt/bin/tg-ws-proxy-rs"
TG_WS_PROXY_RS_INIT="/opt/etc/init.d/S99tg-ws-proxy-rs"
TG_WS_PROXY_RS_CONF_DIR="/opt/etc/tg-ws-proxy-rs"
TG_WS_PROXY_RS_CONF="$TG_WS_PROXY_RS_CONF_DIR/config.conf"
TG_WS_PROXY_RS_SECRET="$TG_WS_PROXY_RS_CONF_DIR/secret.conf"
TG_WS_PROXY_GO_CONF_DIR="/opt/etc/tg-ws-proxy"
TG_WS_PROXY_GO_INIT="/opt/etc/init.d/S99tg-ws-proxy"
TG_WS_PROXY_RS_LOG="/opt/var/log/tg-ws-proxy-rs.log"
TG_WS_PROXY_RS_REPO="valnesfjord/tg-ws-proxy-rs"
TG_WS_PROXY_RS_DC_TARGETS="2:149.154.167.220,4:149.154.167.220"
TG_WS_PROXY_RS_TOP_DOMAINS=4
TG_WS_PROXY_RS_FRONTING_DOMAIN="sprinthost.ru"
# Латентность последней пробы, результаты перебора вариантов и выбор
# пользователя.  Результаты — строками «индекс|ms|вердикт|описание».
TG_WS_PROXY_RS_LAST_MS=""
TG_WS_PROXY_RS_RESULTS=""
TG_WS_PROXY_RS_PICK=""
TG_WS_PROXY_RS_BEST_IDX=""

is_tg_ws_proxy_rs_installed() { [ -x "$TG_WS_PROXY_RS_BIN" ]; }

tg_ws_proxy_rs_version() {
  "$TG_WS_PROXY_RS_BIN" --version 2>/dev/null | head -1 | \
    sed -n 's/.*[[:space:]]\([0-9][0-9.]*\)[[:space:]]*$/\1/p'
}

# config.conf — шелл-присваивания, читаем их sed-ом (так же делает инсталлер).
tg_ws_proxy_rs_conf_get() {
  sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" "$TG_WS_PROXY_RS_CONF" 2>/dev/null \
    | tr -d '\r' | head -1
}

# Записать ключ, сохранив остальные строки и комментарии. awk, а не sed:
# значение приходит из сети и может содержать /, & и кавычки.
tg_ws_proxy_rs_conf_set() {
  local key="$1" val="$2" tmp="$TG_WS_PROXY_RS_CONF.tmp.$$"
  [ -f "$TG_WS_PROXY_RS_CONF" ] || return 1
  awk -v k="$key" -v v="$val" '
    $0 ~ "^" k "=" { print k "=\"" v "\""; seen = 1; next }
    { print }
    END { if (!seen) print k "=\"" v "\"" }
  ' "$TG_WS_PROXY_RS_CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 0600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$TG_WS_PROXY_RS_CONF"
}

# Секрет до установки: свой не трогаем, чужой (из Go-установки) переносим, а если
# нет ни того ни другого — генерируем сами.
#
# Генерировать приходится здесь: инсталлер делает это через `od -An -tx1`, а
# `od` в BusyBox — и в прошивке Keenetic, и в самом Entware (`/opt/bin/od` —
# симлинк на busybox) — такого ключа не знает, и установка падает на
# `invalid option -- 'A'`. Свой генератор берёт из /dev/urandom только
# hex-символы: каждый отобранный символ равновероятен из шестнадцати, то есть
# те же 128 бит, что и у инсталлера.
tg_ws_proxy_rs_ensure_secret() {
  local s
  s=$(sed -n 's/^SECRET=["]\{0,1\}\([^"]*\)["]\{0,1\}[[:space:]]*$/\1/p' "$TG_WS_PROXY_RS_SECRET" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$s" ] && return 0

  s=$(sed -n 's/^SECRET=["]\{0,1\}\([^"]*\)["]\{0,1\}[[:space:]]*$/\1/p' "$TG_WS_PROXY_GO_CONF_DIR/secret.conf" 2>/dev/null | tr -d '\r' | head -1)
  if [ -n "$s" ]; then
    mkdir -p "$TG_WS_PROXY_RS_CONF_DIR" || return 1
    printf 'SECRET=%s\n' "$s" > "$TG_WS_PROXY_RS_SECRET"
    chmod 0600 "$TG_WS_PROXY_RS_SECRET" 2>/dev/null || true
    info "Секрет взят из Go-установки — прежние ссылки tg:// продолжат работать."
    return 0
  fi

  s=$(tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 32)
  case "$s" in
    ????????????????????????????????) ;;
    *)
      warn "Не удалось сгенерировать секрет (/dev/urandom или tr недоступны)."
      return 1
      ;;
  esac
  mkdir -p "$TG_WS_PROXY_RS_CONF_DIR" || return 1
  printf 'SECRET=%s\n' "$s" > "$TG_WS_PROXY_RS_SECRET"
  chmod 0600 "$TG_WS_PROXY_RS_SECRET" 2>/dev/null || true
  info "Секрет сгенерирован."
  return 0
}

# Бэкапы конфига копятся с каждым подбором (по одному на прогон), поэтому
# держим последние три — так же, как инсталлер поступает со своими.
tg_ws_proxy_rs_prune_backups() {
  local dir="$TG_WS_PROXY_RS_CONF_DIR" keep=3 old
  [ -d "$dir" ] || return 0
  # shellcheck disable=SC2012 # имена однотипные: config.conf.bak.<дата>
  for old in $(ls -1 "$dir"/config.conf.bak.* 2>/dev/null | sort -r | tail -n +$((keep + 1))); do
    rm -f "$old"
  done
  return 0
}

# Проба своего слушателя появилась в 2.4.5 — у более старого бинаря её нет.
tg_ws_proxy_rs_supports_check_listener() {
  "$TG_WS_PROXY_RS_BIN" --help 2>&1 | grep -q -- '--check-listener'
}

# Свободный порт для пробного запуска: сервис держит свой, а проба поднимает
# собственный слушатель. Начинаем с порта сервиса + 1.
tg_ws_proxy_rs_free_port() {
  local base port
  base=$(tg_ws_proxy_rs_conf_get PORT); [ -n "$base" ] || base=1443
  port=$((base + 1))
  while [ "$port" -lt $((base + 20)) ]; do
    port_is_open "$port" || { echo "$port"; return 0; }
    port=$((port + 1))
  done
  return 1
}

# Имя релизного архива — то, что инсталлер скачает и распакует. Меню нужно оно
# до установки, чтобы показать размер, поэтому здесь повторены и источник
# архитектуры (opkg print-architecture), и таблица entware_binary_target из
# install.sh. Новую архитектуру придётся добавить в обоих местах.
tg_ws_proxy_rs_target() {
  local arch best='' best_pri='' name pri
  arch=$(opkg print-architecture 2>/dev/null) || return 1
  while read -r _keyword name pri; do
    [ -n "$name" ] || continue
    [ "$name" = all ] && continue
    if [ -z "$best_pri" ] || [ "$pri" -gt "$best_pri" ] 2>/dev/null; then
      best="$name"; best_pri="$pri"
    fi
  done <<EOF
$arch
EOF
  case "$best" in
    aarch64|aarch64-[0-9]*) printf '%s' aarch64-unknown-linux-musl ;;
    armv7|armv7-[0-9]*) printf '%s' armv7-unknown-linux-musleabihf ;;
    mipsel|mipsel-[0-9]*) printf '%s' mipsel-unknown-linux-musl ;;
    mips|mips-[0-9]*) printf '%s' mips-unknown-linux-musl ;;
    x64|x64-[0-9]*) printf '%s' x86_64-unknown-linux-musl ;;
    *) return 1 ;;
  esac
}

tg_ws_proxy_rs_mb() {  # $1 = байты, $2 = знаков после точки (1 или 2)
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  # %.2f и %.1f заданы буквально: в BusyBox awk нет формы с «*».
  if [ "${2:-2}" = "1" ]; then
    awk -v b="$1" 'BEGIN{printf "%.1f МБ", b/1048576}'
  else
    awk -v b="$1" 'BEGIN{printf "%.2f МБ", b/1048576}'
  fi
}

# Размер распакованного бинаря: релиз кладёт его в .tar.gz, и на флеш ложится
# заметно больше архива (у обычной сборки — примерно вдвое). Числа сняты с
# релиза v2.4.5 (каждый архив скачан и распакован), поэтому обновлять их надо
# вместе с ним — иначе меню покажет устаревший размер. Формат:
# <target> <обычная> <upx>.
TG_WS_PROXY_RS_BIN_SIZES="
aarch64-unknown-linux-musl 3846224 1441272
armv7-unknown-linux-musleabihf 3687132 1347496
mipsel-unknown-linux-musl 4930100 1471168
mips-unknown-linux-musl 4909616 1447848
x86_64-unknown-linux-musl 4588192 1707600
"

# Размер бинаря для цели; пусто — цели нет в таблице (показываем только архив).
tg_ws_proxy_rs_bin_size() {
  local size
  size=$(printf '%s\n' "$TG_WS_PROXY_RS_BIN_SIZES" | awk -v t="$1" -v v="$2" '$1==t{print (v=="upx")?$3:$2}')
  case "$size" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$size"
}

# Потребление памяти: RSS сразу после старта сервиса, без трафика. Замерено на
# mipsel с релизом v2.4.5 (разброс между прогонами ±0.2 МБ). Формат:
# <target> <обычная> <upx>, в килобайтах. Цель без строки — память покажем
# словами, без чисел, чтобы не выдумывать чужие замеры.
TG_WS_PROXY_RS_RAM_SIZES="
mipsel-unknown-linux-musl 2688 3248
"

tg_ws_proxy_rs_ram_size() {  # $1 = target, $2 = plain|upx
  local size
  size=$(printf '%s\n' "$TG_WS_PROXY_RS_RAM_SIZES" | awk -v t="$1" -v v="$2" '$1==t{print (v=="upx")?$3:$2}')
  case "$size" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$size"
}

# Обычная сборка или компактная. Разница — флеш против ОЗУ: UPX-бинарь
# распаковывается в память целиком, и вытеснить её ядро не может (у обычного
# кода страницы файловые, их ядро освобождает под давлением, а на роутере нет
# даже свопа). Поэтому по умолчанию — обычная, а компактная для тех боксов, где
# флеша в обрез.
tg_ws_proxy_rs_choose_variant() {
  local target plain_bin upx_bin plain_ram upx_ram answer image tries
  local plain_flash plain_mem plain_evict upx_flash upx_mem upx_evict
  TG_WS_PROXY_RS_UPX=0
  target=$(tg_ws_proxy_rs_target 2>/dev/null) || target=''
  plain_bin=''; upx_bin=''; plain_ram=''; upx_ram=''
  if [ -n "$target" ]; then
    plain_bin=$(tg_ws_proxy_rs_bin_size "$target" plain 2>/dev/null) || plain_bin=''
    upx_bin=$(tg_ws_proxy_rs_bin_size "$target" upx 2>/dev/null) || upx_bin=''
    plain_ram=$(tg_ws_proxy_rs_ram_size "$target" plain 2>/dev/null) || plain_ram=''
    upx_ram=$(tg_ws_proxy_rs_ram_size "$target" upx 2>/dev/null) || upx_ram=''
    # Таблица в килобайтах (как /proc), форматтер ждёт байты.
    [ -n "$plain_ram" ] && plain_ram=$((plain_ram * 1024))
    [ -n "$upx_ram" ] && upx_ram=$((upx_ram * 1024))
  fi
  # Ячейки таблицы — только ASCII, а «МБ» стоит в заголовке: printf в BusyBox
  # считает ширину в байтах, и кириллица в ячейке сломала бы выравнивание.
  plain_flash='—'; plain_mem='—'; plain_evict='код вытесняемый'
  upx_flash='—'; upx_mem='—'; upx_evict='образ в ОЗУ, не вытесняется'
  if [ -n "$plain_bin" ]; then
    plain_flash=$(tg_ws_proxy_rs_mb "$plain_bin"); plain_flash="${plain_flash% МБ}"
  fi
  if [ -n "$upx_bin" ]; then
    upx_flash=$(tg_ws_proxy_rs_mb "$upx_bin"); upx_flash="${upx_flash% МБ}"
  fi
  if [ -n "$plain_ram" ]; then
    plain_mem=$(tg_ws_proxy_rs_mb "$plain_ram" 1); plain_mem="~${plain_mem% МБ}"
    plain_evict='1.6 МБ — код читается с флеша'
  fi
  if [ -n "$upx_ram" ]; then
    upx_mem=$(tg_ws_proxy_rs_mb "$upx_ram" 1); upx_mem="~${upx_mem% МБ}+"
    upx_evict='нет — образ распакован в ОЗУ'
  elif [ -n "$plain_bin" ]; then
    upx_evict="образ ≈$(tg_ws_proxy_rs_mb "$plain_bin") в ОЗУ, не вытесняется"
  fi
  echo
  info "Какую сборку поставить?"
  echo
  echo "                      флеш, МБ память, МБ вытесняемых"
  printf '  1) Обычная          %-9s%-11s%s\n' "$plain_flash" "$plain_mem" "$plain_evict"
  printf '  2) Компактная (UPX) %-9s%-11s%s\n' "$upx_flash" "$upx_mem" "$upx_evict"
  echo
  echo "  Рекомендуется обычная сборка; компактная — если флеш-памяти мало."
  # Ответ не из списка не принимаем молча: сюда легко попасть нажатием «n» на
  # предыдущий вопрос, и тогда на экране «n», а поставлено будет что-то другое.
  tries=0
  while [ "$tries" -lt 3 ]; do
    ask "Выбор [1/2, Enter = 1]: "
    read_menu answer || break
    case "$answer" in
      1|"") TG_WS_PROXY_RS_UPX=0; break ;;
      2) TG_WS_PROXY_RS_UPX=1; break ;;
      *) warn "Ответ не распознан — введите 1 или 2." ;;
    esac
    tries=$((tries + 1))
  done
  if [ "$TG_WS_PROXY_RS_UPX" = "1" ]; then
    image=''
    [ -n "$plain_bin" ] && image=" (≈$(tg_ws_proxy_rs_mb "$plain_bin"))"
    info "Компактная сборка: образ$image распаковывается в ОЗУ целиком и не вытесняется — флеш экономится за счёт постоянной памяти."
  fi
  return 0
}

tg_ws_proxy_rs_install() {
  local url="https://raw.githubusercontent.com/${TG_WS_PROXY_RS_REPO}/main/install.sh"
  local script="/tmp/tgws-install.$$.sh" out rc upx_arg='' bin_size size_text
  tg_ws_proxy_rs_choose_variant || return 1
  [ "$TG_WS_PROXY_RS_UPX" = "1" ] && upx_arg='--upx'
  if ! download_file "$url" "$script"; then
    error "Не удалось скачать install.sh — проверьте доступ к GitHub."
    return 1
  fi
  tg_ws_proxy_rs_ensure_secret || return 1
  info "Установка из релиза…"
  # --platform entware: у установщика отдельная ветка для OpenWrt/LuCI, а на
  # Keenetic нужен путь Entware (/opt + rc.unslung).
  # Вывод показываем под отступом и без строк, которые дальше повторяет меню:
  # ссылку оно печатает само (и только после проверки связи), а «Rollback
  # backup» дублирует «Backup» тем же путём.
  out=$(sh "$script" --platform entware $upx_arg 2>&1)
  rc=$?
  rm -f "$script"
  # Инсталлер красит вывод ANSI-кодами, поэтому сначала снимаем цвет (меню
  # красит само), затем убираем строки, которые дальше повторяет меню: ссылку
  # оно печатает само и только после проверки связи, а «Rollback backup»
  # дублирует «Backup» тем же путём.
  esc=$(printf '\033')
  printf '%s\n' "$out" \
    | sed "s/${esc}\[[0-9;]*m//g" \
    | grep -v -e '^Proxy link:' -e '^Rollback backup:' \
    | sed 's/^/    /'
  if [ "$rc" -ne 0 ]; then
    error "install.sh завершился с ошибкой."
    return 1
  fi
  is_tg_ws_proxy_rs_installed || { error "Бинарь не найден: $TG_WS_PROXY_RS_BIN"; return 1; }
  bin_size=$(wc -c < "$TG_WS_PROXY_RS_BIN" 2>/dev/null | tr -d ' \r\n') || bin_size=''
  size_text=$(tg_ws_proxy_rs_mb "$bin_size" 2>/dev/null) || size_text=''
  if [ -n "$size_text" ]; then
    info "Установлено: $(tg_ws_proxy_rs_version), $size_text"
  else
    info "Установлено: $(tg_ws_proxy_rs_version)"
  fi
  tg_ws_proxy_rs_disable_go_init || true
  return 0
}

# Перезапуск без вывода init-скрипта: в этом пункте он только шумит, а факт
# перезапуска сообщает одна строка.
tg_ws_proxy_rs_restart() {
  [ -x "$TG_WS_PROXY_RS_INIT" ] || return 0
  if "$TG_WS_PROXY_RS_INIT" restart >/dev/null 2>&1; then
    info "Сервис перезапущен."
    return 0
  fi
  warn "Сервис не перезапустился — смотрите лог: $TG_WS_PROXY_RS_LOG"
  return 1
}

# Прежний Go-сервис выключается на автозапуск, а не удаляется: два прокси на
# одном порту после перезагрузки поднимутся оба, и один не сможет занять порт.
# Инсталлер делает это сам, только если процесс Go ещё держал порт — если его
# остановили раньше (как делает этот пункт), бит остаётся выставленным.
tg_ws_proxy_rs_disable_go_init() {
  [ -x "$TG_WS_PROXY_GO_INIT" ] || return 0
  chmod -x "$TG_WS_PROXY_GO_INIT" || return 1
  info "Go-сервис выключен из автозапуска: $TG_WS_PROXY_GO_INIT (вернуть — chmod +x)."
  return 0
}

# Замер CF-доменов: --check печатает строку на домен, но WARN-строки лога
# влезают в ту же строку, поэтому результат берём из [OK ] в строке.
# На выходе «ms домен» по возрастанию, только ответившие.
tg_ws_proxy_rs_measure_domains() {
  "$TG_WS_PROXY_RS_BIN" --check --default-domains 2>&1 | while IFS= read -r line; do
    case "$line" in
      *"[OK ]"*) ;;
      *) continue ;;
    esac
    dom=$(printf '%s' "$line" | sed -n 's/^ *kws2\.\([^ ]*\) .*/\1/p')
    ms=$(printf '%s' "$line" | sed -n 's/.*\[OK \] *\([0-9][0-9]*\)ms.*/\1/p')
    [ -n "$dom" ] && [ -n "$ms" ] && printf '%s %s\n' "$ms" "$dom"
  done | sort -n | awk '!seen[$2]++ { print $2 }'
}

# Сквозная проверка штатной пробой бинаря: он поднимает слушатель на свободном
# порту с тем же секретом, маршрутами и тирами, что и сервис, и требует resPQ от
# DC Telegram. Конфиг читается так же, как его читает init-скрипт — через
# переменные окружения (с той же чисткой CR, что и там: файл мог побывать в
# редакторе на Windows).
tg_ws_proxy_rs_probe() {
  local port out section verdict
  port=$(tg_ws_proxy_rs_free_port) || {
    warn "Нет свободного порта для проверки (заняты порты рядом с сервисным)."
    return 1
  }

  out=$(
    scrub_and_source() {
      tr -d '\r' < "$1" > "/tmp/tgws-conf.$$" && . "/tmp/tgws-conf.$$"
      rm -f "/tmp/tgws-conf.$$"
    }
    scrub_and_source "$TG_WS_PROXY_RS_CONF" 2>/dev/null
    scrub_and_source "$TG_WS_PROXY_RS_SECRET" 2>/dev/null

    [ -n "$HOST" ] && export TG_HOST="$HOST"
    [ -n "$LINK_IP" ] && export TG_LINK_IP="$LINK_IP"
    export TG_SECRET="$SECRET"
    # Community-список доменов здесь не включаем намеренно: он добавляет около
    # 27 секунд на каждый прогон (31 с против 4 с в замере), а варианту лестницы
    # не нужен — домены замеряются отдельно, один раз, до перебора.
    [ -n "$CF_DOMAIN" ] && export TG_CF_DOMAIN="$CF_DOMAIN"
    [ -n "$CF_WORKER_DOMAIN" ] && export TG_CF_WORKER_DOMAIN="$CF_WORKER_DOMAIN"
    [ -n "$MTPROTO_PROXY" ] && export TG_MTPROTO_PROXY="$MTPROTO_PROXY"

    # shellcheck disable=SC2086 # EXTRA_ARGS — список аргументов, как его пишет инсталлер
    "$TG_WS_PROXY_RS_BIN" --port "$port" --check-listener $EXTRA_ARGS 2>&1
  )

  # В том же прогоне проверяются и CF-домены из конфига, поэтому вердикт берём
  # из секции своего слушателя, а не из кода выхода. Заодно запоминаем её
  # латентность — по ней ищется быстрейший вариант лестницы.
  section=$(printf '%s\n' "$out" | sed -n '/Own listener/,/^=\{10,\}/p')
  verdict=$(printf '%s\n' "$section" | grep -o '\[\(OK \|FAIL\|SKIP\)\]' | head -1)
  TG_WS_PROXY_RS_LAST_MS=$(printf '%s\n' "$section" | grep -o '[0-9][0-9]*ms' | head -1 | tr -d 'ms')
  [ "$verdict" = "[OK ]" ]
}

# Варианты лестницы: индекс → DC_IP | EXTRA_ARGS | описание.
# Порядок здесь — порядок перебора; в списке для пользователя они сортируются
# по замеру.
tg_ws_proxy_rs_variant() {
  case "$1" in
    1) printf '%s|%s|%s\n' "$TG_WS_PROXY_RS_DC_TARGETS" \
         "--pinned-upstream ws,cfproxy,tcp" "прямой WebSocket (ws → cfproxy → tcp)" ;;
    2) printf '%s|%s|%s\n' "$TG_WS_PROXY_RS_DC_TARGETS" \
         "--pinned-upstream ws,cfproxy,tcp --fronting-domain $TG_WS_PROXY_RS_FRONTING_DOMAIN" \
         "прямой WebSocket с фронтингом SNI" ;;
    3) printf '%s|%s|%s\n' "" "" "лестница по умолчанию (cfproxy → tcp)" ;;
    4) printf '%s|%s|%s\n' "" "--cf-disable-tls" \
         "cfproxy поверх ws:// (порт 80 вместо 443)" ;;
    *) return 1 ;;
  esac
}

# Проверяет каждый вариант пробой и складывает результат в
# TG_WS_PROXY_RS_RESULTS строками «индекс|ms|вердикт|описание».
# Сервис не перезапускается: проба поднимает собственный слушатель и читает
# конфиг с диска.
tg_ws_proxy_rs_probe_variants() {
  local i row dc args label ms
  TG_WS_PROXY_RS_RESULTS=""
  info "Проверяю варианты (по одному прогону на каждый, это самая долгая часть)…"
  i=1
  while :; do
    row=$(tg_ws_proxy_rs_variant "$i") || break
    dc=$(printf '%s' "$row" | cut -d'|' -f1)
    args=$(printf '%s' "$row" | cut -d'|' -f2)
    label=$(printf '%s' "$row" | cut -d'|' -f3)

    # Ничего не печатаем: итог покажет список ниже, а строка на каждый вариант
    # его же и дублировала.
    tg_ws_proxy_rs_conf_set DC_IP "$dc"
    tg_ws_proxy_rs_conf_set EXTRA_ARGS "$args"
    if tg_ws_proxy_rs_probe; then
      ms="$TG_WS_PROXY_RS_LAST_MS"; [ -n "$ms" ] || ms=0
      TG_WS_PROXY_RS_RESULTS="$TG_WS_PROXY_RS_RESULTS$i|$ms|OK|$label
"
    else
      TG_WS_PROXY_RS_RESULTS="$TG_WS_PROXY_RS_RESULTS$i|999999|FAIL|$label
"
    fi
    i=$((i + 1))
  done
  return 0
}

# Печатает список проверенных путей: обычные — с временем и пометкой быстрейшего,
# запасной режим TLS-MITM — отдельной строкой ниже: он для сломанного TLS, а не
# для скорости, и часто оказывается быстрее всех просто потому, что идёт по
# открытому HTTP.
tg_ws_proxy_rs_show_variants() {
  local rows normal fallback
  rows=$(printf '%s' "$TG_WS_PROXY_RS_RESULTS" | grep -v '^$')
  [ -n "$rows" ] || return 1
  normal=$(printf '%s\n' "$rows" | awk -F'|' '$1 != 4')
  fallback=$(printf '%s\n' "$rows" | awk -F'|' '$1 == 4')

  TG_WS_PROXY_RS_BEST_IDX=$(printf '%s\n' "$normal" \
    | awk -F'|' '$3 == "OK" { print $2 " " $1 }' \
    | sort -n | awk 'NR == 1 { print $2 }')

  echo
  printf '%s\n' "${BOLD}Проверенные пути:${NC}"
  printf '%s\n' "$normal" | awk -F'|' -v best="$TG_WS_PROXY_RS_BEST_IDX" '
    {
      n++
      mark = ($1 == best) ? "   <- быстрейший" : ""
      if ($3 == "OK") printf "  [%d] OK   %5sms  %s%s\n", n, $2, $4, mark
      else            printf "  [%d] FAIL         %s\n", n, $4
    }'
  if [ -n "$fallback" ]; then
    echo
    printf '%s\n' "  запасной режим (TLS-MITM, метаданные идут открыто):"
    printf '%s\n' "$fallback" | awk -F'|' '
      {
        if ($3 == "OK") printf "  [%d] OK   %5sms  %s\n", $1, $2, $4
        else            printf "  [%d] FAIL         %s\n", $1, $4
      }'
  fi
  return 0
}

# Спрашивает, какой путь взять. Пишет индекс в TG_WS_PROXY_RS_PICK;
# пустая строка означает «оставить как было».
tg_ws_proxy_rs_ask_variant() {
  local rows pick row verdict tries=0
  # Список печатается в том же порядке, поэтому номер в ответе — это строка
  # результатов, а не отдельная нумерация.
  rows=$(printf '%s' "$TG_WS_PROXY_RS_RESULTS" | grep -v '^$')
  TG_WS_PROXY_RS_PICK=""

  while [ "$tries" -lt 3 ]; do
    if [ -n "$TG_WS_PROXY_RS_BEST_IDX" ]; then
      ask "Какой путь взять? [Enter = быстрейший, 0 = не менять]: "
    else
      ask "Ни один путь не ответил. [Enter = не менять]: "
    fi
    read -r pick

    case "$pick" in
      "")
        [ -n "$TG_WS_PROXY_RS_BEST_IDX" ] && TG_WS_PROXY_RS_PICK="$TG_WS_PROXY_RS_BEST_IDX"
        return 0
        ;;
      0) return 0 ;;
      *[!0-9]*) warn "Нужен номер из списка." ;;
      *)
        row=$(printf '%s\n' "$rows" | awk -F'|' -v n="$pick" '$1 == n')
        if [ -z "$row" ]; then
          warn "Нет такого номера."
        else
          verdict=$(printf '%s' "$row" | cut -d'|' -f3)
          if [ "$verdict" = "OK" ]; then
            TG_WS_PROXY_RS_PICK=$(printf '%s' "$row" | cut -d'|' -f1)
            return 0
          fi
          warn "Этот путь не ответил — выберите другой."
        fi
        ;;
    esac
    tries=$((tries + 1))
  done
  return 0
}

# Отвечал ли вариант с такими параметрами: по нему решается, считать ли
# оставленный конфиг проверенным.
tg_ws_proxy_rs_variant_ok_for() {
  local i row
  i=1
  while :; do
    row=$(tg_ws_proxy_rs_variant "$i") || return 1
    if [ "$(printf '%s' "$row" | cut -d'|' -f1)" = "$1" ] &&
       [ "$(printf '%s' "$row" | cut -d'|' -f2)" = "$2" ]; then
      printf '%s' "$TG_WS_PROXY_RS_RESULTS" | grep -q "^$i|.*|OK|"
      return $?
    fi
    i=$((i + 1))
  done
}

# Подбор параметров под сеть: CF-домены по замеру, затем перебор вариантов
# лестницы с пробой каждого — список с результатами отдаётся пользователю,
# какой путь взять, решает он.
tg_ws_proxy_rs_tune() {
  local domains best orig_dc orig_args
  # Проба по ходу перебора пишет варианты в конфиг, поэтому исходные значения
  # сохраняем: «не менять» должно вернуть именно их.
  orig_dc=$(tg_ws_proxy_rs_conf_get DC_IP)
  orig_args=$(tg_ws_proxy_rs_conf_get EXTRA_ARGS)
  TG_WS_PROXY_RS_RESULTS=""
  TG_WS_PROXY_RS_PICK=""
  TG_WS_PROXY_RS_BEST_IDX=""
  info "Замер CF-доменов…"
  domains=$(tg_ws_proxy_rs_measure_domains | head -"$TG_WS_PROXY_RS_TOP_DOMAINS")
  if [ -z "$domains" ]; then
    warn "Ни один CF-домен не ответил — оставляем список по умолчанию."
  else
    best=$(printf '%s\n' "$domains" | tr '\n' ',' | sed 's/,$//')
    tg_ws_proxy_rs_conf_set CF_DOMAIN "$best"
    info "CF-домены: $best"
  fi

  # Все варианты проверяются пробой, а затем список отдаётся пользователю:
  # какой путь взять — его решение, замер лишь показывает цену каждого.
  tg_ws_proxy_rs_probe_variants
  tg_ws_proxy_rs_show_variants
  tg_ws_proxy_rs_ask_variant

  if [ -n "$TG_WS_PROXY_RS_PICK" ]; then
    row=$(tg_ws_proxy_rs_variant "$TG_WS_PROXY_RS_PICK")
    tg_ws_proxy_rs_conf_set DC_IP "$(printf '%s' "$row" | cut -d'|' -f1)"
    tg_ws_proxy_rs_conf_set EXTRA_ARGS "$(printf '%s' "$row" | cut -d'|' -f2)"
    tg_ws_proxy_rs_restart
    info "Путь: $(printf '%s' "$row" | cut -d'|' -f3)"
    return 0
  fi

  # Ничего не выбрано (или ни один путь не ответил) — возвращаем то, что было
  # до подбора: перебор по ходу писал варианты в конфиг.
  tg_ws_proxy_rs_conf_set DC_IP "$orig_dc"
  tg_ws_proxy_rs_conf_set EXTRA_ARGS "$orig_args"
  tg_ws_proxy_rs_restart

  if tg_ws_proxy_rs_variant_ok_for "$orig_dc" "$orig_args"; then
    info "Оставлены прежние параметры — этот путь отвечает."
    return 0
  fi
  warn "Путь не изменён, но прежние параметры в списке не отвечали."
  return 1
}

tg_ws_proxy_rs_print_link() {
  local link
  echo
  link=$(sed -n 's/.*\(tg:\/\/proxy?[^ ]*\).*/\1/p' "$TG_WS_PROXY_RS_LOG" 2>/dev/null | tail -1)
  if [ -n "$link" ]; then
    printf '%s\n' "${BOLD}Ссылка для клиентов:${NC}"
    printf '%s\n' "${BOLD}  $link${NC}"
  else
    warn "Ссылки в логе нет — сервис, похоже, не запущен."
    [ -x "$TG_WS_PROXY_RS_INIT" ] && "$TG_WS_PROXY_RS_INIT" status
  fi
  echo
  printf '%s\n' "  config: $TG_WS_PROXY_RS_CONF_DIR/config.conf (секрет — secret.conf рядом)"
  printf '%s\n' "  init:   $TG_WS_PROXY_RS_INIT"
}

menu_tg_ws_proxy_rs() {
  local fresh=0
  echo

  if is_tg_ws_proxy_rs_installed; then
    info "TG WS Proxy Rust — установлено $(tg_ws_proxy_rs_version)"
    if confirm_yes "Переустановить/обновить из последнего релиза?"; then
      tg_ws_proxy_rs_install || return 1
    fi
  else
    info "TG WS Proxy Rust (tg-ws-proxy-rs)"
    # Порт занимает прежний Go-прокси: пока его сервис запущен, Rust не сможет
    # занять тот же порт. Секрет при этом переносится, ссылки не меняются.
    if is_installed "tg-ws-proxy" && service_is_up tg-ws-proxy; then
      warn "Go-прокси (tg-ws-proxy) сейчас занимает порт."
      if confirm_yes "Остановить Go-прокси? Секрет перенесём, ссылки не изменятся."; then
        [ -x "$TG_WS_PROXY_GO_INIT" ] && "$TG_WS_PROXY_GO_INIT" stop 2>/dev/null
      fi
    fi
    confirm_yes "Установить tg-ws-proxy-rs?" || return 0
    tg_ws_proxy_rs_install || return 1
    fresh=1
  fi

  echo
  if ! tg_ws_proxy_rs_supports_check_listener; then
    warn "У этого бинаря нет пробы своего слушателя — нужна версия 2.4.5 или новее."
    warn "Обновить: перезапустите этот пункт и подтвердите переустановку."
    tg_ws_proxy_rs_print_link
    return 0
  fi

  # На чистой установке подбор не спрашивают: только что поставили — незачем
  # оставлять прокси невыверенным. Спрашиваем при повторном заходе.
  if [ "$fresh" = "1" ] || confirm_yes "Подобрать параметры и проверить?"; then
    backup_file "$TG_WS_PROXY_RS_CONF"
    tg_ws_proxy_rs_prune_backups
    if tg_ws_proxy_rs_tune; then
      echo
      info "Связь проверена: resPQ от DC Telegram."
    else
      echo
      warn "Связь не подтвердилась. Последние строки лога:"
      tail -n 8 "$TG_WS_PROXY_RS_LOG" 2>/dev/null | sed 's/^/    /'
    fi
  fi

  tg_ws_proxy_rs_print_link
}

remove_tg_ws_proxy_rs() {
  is_tg_ws_proxy_rs_installed || { warn "tg-ws-proxy-rs не установлен."; return 0; }
  [ -x "$TG_WS_PROXY_RS_INIT" ] && "$TG_WS_PROXY_RS_INIT" stop 2>/dev/null
  rm -f "$TG_WS_PROXY_RS_INIT" "$TG_WS_PROXY_RS_BIN"
  info "tg-ws-proxy-rs удалён (конфиг и секрет оставлены в $TG_WS_PROXY_RS_CONF_DIR)."
  return 0
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
# 16. telemt / telemt-panel  (https://github.com/augin/telemt_script)
# ---------------------------------------------------------------------------
TELEMT_INSTALL_URL="https://raw.githubusercontent.com/augin/telemt_script/main/installer_telemt_v2.sh"
TELEMT_PANEL_INSTALL_URL="https://raw.githubusercontent.com/augin/telemt_script/main/install_telemt-panel.sh"
TELEMT_SYSTEMCTL_URL="https://raw.githubusercontent.com/anch665/keendev/main/systemctl.sh"
TELEMT_JOURNALCTL_URL="https://raw.githubusercontent.com/anch665/keendev/main/journalctl.sh"

is_telemt_installed() {
  [ -x /opt/usr/bin/telemt ] || [ -x /opt/etc/init.d/S99telemt ] || \
    [ -d /opt/etc/telemt ] || [ -x /opt/sbin/telemt-panel ] || \
    [ -x /opt/etc/init.d/S99telemt-panel ] || [ -d /opt/etc/telemt-panel ]
}

install_telemt() {
  echo
  info "Установка telemt"
  info "Источник: $TELEMT_INSTALL_URL"
  info "Требуется: aarch64, curl, libnghttp2"
  echo
  opkg update 2>/dev/null || true
  opkg install curl libnghttp2 2>/dev/null || true
  mkdir -p /opt/tmp
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TELEMT_INSTALL_URL" -o /opt/tmp/install_telemt.sh || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO /opt/tmp/install_telemt.sh "$TELEMT_INSTALL_URL" || return 1
  else
    error "Нужны curl или wget."
    return 1
  fi
  if [ -c /dev/tty ]; then
    sh /opt/tmp/install_telemt.sh < /dev/tty > /dev/tty 2>&1 || true
  else
    sh /opt/tmp/install_telemt.sh || true
  fi
  drain_stdin
  info "Установщик telemt завершил работу."
}

install_telemt_panel() {
  echo
  info "Установка telemt-panel"
  info "Источник: $TELEMT_PANEL_INSTALL_URL"
  echo
  mkdir -p /opt/tmp
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TELEMT_PANEL_INSTALL_URL" -o /opt/tmp/install_telemt-panel.sh || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO /opt/tmp/install_telemt-panel.sh "$TELEMT_PANEL_INSTALL_URL" || return 1
  else
    error "Нужны curl или wget."
    return 1
  fi
  if [ -c /dev/tty ]; then
    sh /opt/tmp/install_telemt-panel.sh < /dev/tty > /dev/tty 2>&1 || true
  else
    sh /opt/tmp/install_telemt-panel.sh || true
  fi
  drain_stdin
  info "Установщик telemt-panel завершил работу."
}

install_telemt_systemd_emu() {
  echo
  info "Эмуляция systemD (systemctl / journalctl) для панели и логов"
  info "systemctl:  $TELEMT_SYSTEMCTL_URL"
  info "journalctl: $TELEMT_JOURNALCTL_URL"
  echo
  mkdir -p /opt/usr/bin
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TELEMT_SYSTEMCTL_URL" -o /opt/usr/bin/systemctl || return 1
    curl -fsSL "$TELEMT_JOURNALCTL_URL" -o /opt/usr/bin/journalctl || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO /opt/usr/bin/systemctl "$TELEMT_SYSTEMCTL_URL" || return 1
    wget -qO /opt/usr/bin/journalctl "$TELEMT_JOURNALCTL_URL" || return 1
  else
    error "Нужны curl или wget."
    return 1
  fi
  chmod +x /opt/usr/bin/systemctl /opt/usr/bin/journalctl
  if [ -x /opt/etc/init.d/S99telemt-panel ]; then
    /opt/etc/init.d/S99telemt-panel restart 2>/dev/null || true
    info "S99telemt-panel перезапущен."
  else
    warn "S99telemt-panel не найден — перезапуск пропущен."
  fi
  info "Эмуляция systemD установлена: /opt/usr/bin/systemctl, /opt/usr/bin/journalctl"
}

remove_telemt() {
  echo
  info "Удаление telemt / telemt-panel..."
  /opt/etc/init.d/S99telemt-panel stop 2>/dev/null || true
  /opt/etc/init.d/S99telemt stop 2>/dev/null || true
  rm -f /opt/etc/init.d/S99telemt
  rm -f /opt/etc/init.d/S99telemt-panel
  rm -f /opt/usr/bin/telemt
  rm -f /opt/sbin/telemt-panel
  rm -rf /opt/etc/telemt
  rm -rf /opt/etc/telemt-panel
  rm -rf /opt/tmp/telemt_dl
  rm -rf /opt/tmp/telemt-panel-install
  rm -f /tmp/log/telemt.log
  rm -f /tmp/cache/beobachten.txt
  info "telemt / telemt-panel удалены."
}

menu_telemt() {
  while true; do
    clear 2>/dev/null || true
    printf '%s\n' "${CYAN}================================================${NC}"
    printf '%s\n' "${CYAN}${BOLD}           telemt / telemt-panel${NC}"
    printf '%s\n' "${CYAN}================================================${NC}"
    echo
    printf '%s\n' "${DIM}Telemt — быстрый, безопасный и функциональный сервер на Rust:${NC}"
    printf '%s\n' "${DIM}полностью реализует официальный алгоритм Telegram-прокси${NC}"
    printf '%s\n' "${DIM}и добавляет множество улучшений.${NC}"
    echo
    printf '%s\n' "${DIM}Скрипты: https://github.com/augin/telemt_script${NC}"
    printf '%s\n' "${DIM}(Entware / Keenetic, рекомендуется aarch64)${NC}"
    echo
    if is_telemt_installed; then
      _tm_st=""
      { [ -x /opt/usr/bin/telemt ] || [ -x /opt/etc/init.d/S99telemt ]; } && _tm_st="${_tm_st}telemt "
      { [ -x /opt/sbin/telemt-panel ] || [ -x /opt/etc/init.d/S99telemt-panel ]; } && _tm_st="${_tm_st}telemt-panel "
      [ -x /opt/usr/bin/systemctl ] && _tm_st="${_tm_st}systemctl "
      info "Обнаружено: ${_tm_st:-частично}"
      echo
    fi
    echo "  1. Установка telemt"
    echo "  2. Установка telemt-panel"
    echo "  3. Эмуляция systemD"
    echo "  4. Удаление"
    echo "  0. Назад"
    echo
    ask "Выбор: "
    read_menu tchoice
    case "$tchoice" in
      1) install_telemt || true ;;
      2) install_telemt_panel || true ;;
      3) install_telemt_systemd_emu || true ;;
      4)
        if confirm_no "Удалить telemt и telemt-panel?"; then
          remove_telemt || true
        else
          info "Отменено."
        fi
        ;;
      0|"") return 0 ;;
      *) warn "Неверный пункт" ;;
    esac
    drain_stdin
    echo
    ask "$LBL_BACK"
    read_menu _
  done
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
# Один проход awk: секции + --blob= + fake:blob= (без grep/fork на каждую строку)
parse_fake_blobs() {
  local conf="$1"
  local map_file="$2"
  local list_file="$3"

  : > "$map_file"
  : > "$list_file"
  [ -f "$conf" ] || return 1

  # BusyBox/mawk-совместимый однопроходный разбор
  awk -v mapf="$map_file" -v listf="$list_file" '
  function basename(p,   n, a) {
    gsub(/["\047]/, "", p)
    if (p ~ /^0[xX]*/) return "(hex)"
    n = split(p, a, "/")
    return (n > 0 && a[n] != "") ? a[n] : p
  }
  BEGIN {
    cur = "?"
    idx = 0
  }
  {
    line = $0

    # Секции NFQWS_*ARGS*
    if (match(line, /^(NFQWS_BASE_ARGS|NFQWS_ARGS_QUIC|NFQWS_ARGS_UDP|NFQWS_ARGS_CUSTOM|NFQWS_EXTRA_ARGS|NFQWS_ARGS)=/)) {
      cur = substr(line, 1, RLENGTH - 1)
    }

    # Токены --blob=name:path (пробелы/табы как разделители)
    n = split(line, tok, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (tok[i] ~ /^--blob=/) {
        rest = substr(tok[i], 8)   # после --blob=
        colon = index(rest, ":")
        if (colon < 1) continue
        name = substr(rest, 1, colon - 1)
        path = substr(rest, colon + 1)
        sub(/^@/, "", path)
        gsub(/["\047]/, "", path)
        if (name == "") continue
        base = basename(path)
        if (!(name in blobmap)) {
          blobmap[name] = base
          # порядок map не важен — пишем в END
        }
      }
    }

    # fake:blob=NAME (не hex) — basename резолвим в END (после всего map)
    if (index(line, "fake:blob=") == 0) next
    tmp = line
    while (match(tmp, /fake:blob=[^: \t"]+/)) {
      fb = substr(tmp, RSTART, RLENGTH)
      name = substr(fb, 11)   # после fake:blob=
      tmp = substr(tmp, RSTART + RLENGTH)
      if (name == "" || name ~ /^0[xX]/) continue
      if (name in seen) continue
      seen[name] = 1
      idx++
      order[idx] = name
      sec[name] = cur
    }
  }
  END {
    for (name in blobmap)
      print name "|" blobmap[name] > mapf
    close(mapf)
    for (i = 1; i <= idx; i++) {
      name = order[i]
      base = (name in blobmap) ? blobmap[name] : "(нет --blob= / встроенный)"
      print i "|" sec[name] "|" name "|" base > listf
    }
    close(listf)
    exit (idx > 0 ? 0 : 1)
  }
  ' "$conf"
}

list_repo_blobs() {
  # 1) strategies/blobs/SHA256SUMS  2) GitHub API  3) встроенный fallback
  local cache="/tmp/nfqws-repo-blobs.list"
  local now age=999999 list

  now=$(date +%s 2>/dev/null || echo 0)
  if [ -f "$cache" ]; then
    age=$((now - $(stat -c %Y "$cache" 2>/dev/null || echo 0)))
  fi
  if [ -f "$cache" ] && [ "$age" -lt 3600 ] && [ -s "$cache" ]; then
    cat "$cache"
    return 0
  fi

  if ensure_blobs_sha256sums; then
    list=$(awk 'NF >= 2 {
      n = $2
      sub(/.*\//, "", n)
      if (n ~ /\.bin$/) print n
    }' "$BLOBS_SHA256SUMS_CACHE" 2>/dev/null | sort -u)
    if [ -n "$list" ]; then
      printf '%s\n' "$list" > "$cache"
      cat "$cache"
      return 0
    fi
  fi

  if fetch_url "${STRATEGIES_API}/blobs" 2>/dev/null | \
      grep -oE '"name":[[:space:]]*"[^"]+\.bin"' | \
      sed 's/.*"\([^"]*\.bin\)".*/\1/' | sort -u > "$cache" && [ -s "$cache" ]; then
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
  is_tg_ws_proxy_rs_installed       && items="$items tg-ws-proxy-rs"
  is_installed "usque-keenetic"     && items="$items usque-keenetic"
  is_installed "magitrickle"        && items="$items magitrickle"
  is_installed "opera-proxy"        && items="$items opera-proxy"
  [ -f /opt/keenkit.sh ]            && items="$items KeenKit"
  is_telemt_installed               && items="$items telemt"

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
        tg-ws-proxy-rs) remove_tg_ws_proxy_rs ;;
        usque-keenetic) remove_usque_keenetic ;;
        magitrickle)   remove_magitrickle ;;
        opera-proxy)   remove_opera_proxy ;;
        KeenKit)       remove_keenkit ;;
        telemt)        remove_telemt ;;
        *)
          opkg remove --autoremove "$target"
          info "$target удалён."
          ;;
      esac
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Сервисные утилиты (S / U)
# ---------------------------------------------------------------------------
opkg_upgrade_all() {
  echo
  info "$LBL_U"
  info "opkg update && opkg upgrade ..."
  if ! opkg update; then
    error "opkg update не удался."
    return 1
  fi
  if ! opkg upgrade; then
    error "opkg upgrade не удался."
    return 1
  fi
  refresh_opkg_cache
  info "Обновление пакетов завершено."

  # dpi-detector ставится не через opkg — обновляем отдельно, если уже установлен
  if [ -x /opt/bin/dpi-detector ]; then
    info "Найден /opt/bin/dpi-detector — обновление..."
    if run_remote_sh "${DPI_DETECTOR_INSTALL_URL:-https://raw.githubusercontent.com/Runnin4ik/dpi-detector/rust/install.sh}"; then
      info "dpi-detector обновлён."
    else
      warn "Не удалось обновить dpi-detector."
    fi
  fi
}

service_upx_compress() {
  echo
  info "$LBL_S1"
  warn "UPX сожмёт исполняемые файлы в /opt/bin /opt/sbin /opt/usr/bin /opt/libexec."
  warn "Уже сжатые бинарники UPX обычно пропускает; сбой на одном файле не критичен."
  if ! confirm_yes "Продолжить?"; then
    info "Отменено."
    return 0
  fi
  if ! command -v upx >/dev/null 2>&1; then
    info "Установка upx..."
    opkg update 2>/dev/null || true
    if ! opkg install upx; then
      error "Не удалось установить upx."
      return 1
    fi
  fi
  info "Сжатие (может занять несколько минут)..."
  # || true — отдельные файлы могут не сжаться (уже UPX / не-ELF)
  find /opt/bin /opt/sbin /opt/usr/bin /opt/libexec \
    -type f -executable 2>/dev/null \
    -exec upx --lzma --best {} + 2>/dev/null || true
  info "Готово."
}

# Скачать HTTPS-URL в файл (curl → wget). Не pipe|sh.
download_https_file() {
  local url="$1" dest="$2"
  rm -f "$dest"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest" 2>/dev/null && [ -s "$dest" ] && return 0
    rm -f "$dest"
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" 2>/dev/null && [ -s "$dest" ] && return 0
    rm -f "$dest"
  fi
  return 1
}

# dropbear_fix (логика sw.ext.io): правки conf/init + restart Entware dropbear.
# Важно: stop убивает текущую SSH-сессию. Обычный фон (…&) получает SIGHUP и
# часто не доходит до start. Делаем conf-правки сейчас, restart — через nohup/trap HUP.
service_dropbear_fix() {
  local conf="/opt/etc/config/dropbear.conf"
  local init="/opt/etc/init.d/S51dropbear"
  local log="/tmp/dropbear_fix.log"
  local reset=0 port="" bin=""

  echo
  info "$LBL_S2"
  echo "  1) Без сброса пароля"
  echo "  2) Со сбросом пароля (root → keenetic)"
  echo "  0) Назад"
  echo
  ask "Выбор [1/2/0]: "
  read_menu dchoice
  case "$dchoice" in
    1) reset=0 ;;
    2)
      if ! confirm_no "Сбросить пароль root Entware на keenetic?"; then
        info "Отменено."
        return 0
      fi
      reset=1
      ;;
    0|"") return 0 ;;
    *) warn "Неверный выбор."; return 0 ;;
  esac

  if [ ! -x "$init" ] && [ ! -f "$init" ]; then
    error "Не найден $init — Entware dropbear не установлен?"
    return 1
  fi
  if [ ! -f "$conf" ]; then
    error "Не найден $conf"
    return 1
  fi

  # --- правки конфига, пока SSH ещё жив ---
  if grep -q '^PORT=22$' "$conf" 2>/dev/null; then
    sed -i 's/^PORT=22$/PORT=222/' "$conf"
    info "PORT: 22 → 222"
  fi
  if grep -q 'PIDFILE="/opt/var/run/dropbear.pid"' "$init" 2>/dev/null; then
    sed -i 's|PIDFILE="/opt/var/run/dropbear.pid"|PIDFILE="/var/run/dropbear.pid"|g' "$init"
    info "PIDFILE → /var/run/dropbear.pid"
  fi
  if [ "$reset" = "1" ] && [ -f /opt/etc/passwd ]; then
    # стандартный hash keenetic (как в sw.ext.io dropbear_fix)
    sed -i 's#^\(root:\)[^:]*#\1$1$6vKOV7zs$d2EqNYGvlBWEYoFD7FFkr0#' /opt/etc/passwd
    info "Пароль root Entware сброшен на: keenetic"
  fi

  port=$(grep -E '^PORT=' "$conf" 2>/dev/null | head -1 | cut -d= -f2)
  [ -z "$port" ] && port="?"
  bin="/opt/sbin/dropbear"
  [ -x "$bin" ] || bin="dropbear"

  echo
  warn "Сейчас будет перезапуск Entware dropbear — SSH-сессия оборвётся."
  warn "Подключайтесь через 5–10 сек:"
  warn "  ssh -p $port root@<IP-роутера>"
  [ "$reset" = "1" ] && warn "  пароль: keenetic"
  echo
  info "Планирую restart в фоне (лог: $log)..."

  # Полная отвязка от SSH-сессии (SIGHUP не должен убить restart)
  rm -f "$log"
  if command -v nohup >/dev/null 2>&1; then
    nohup sh -c "
      trap '' HUP
      sleep 2
      echo \"[\$(date)] stop\" >>'$log'
      '$init' stop >>'$log' 2>&1 || true
      killall -9 dropbear >>'$log' 2>&1 || true
      killall -9 /opt/sbin/dropbear >>'$log' 2>&1 || true
      rm -f /opt/var/run/dropbear.pid /var/run/dropbear.pid
      sleep 1
      echo \"[\$(date)] start\" >>'$log'
      '$init' start >>'$log' 2>&1 || '$bin' -p '$port' >>'$log' 2>&1 || true
      sleep 1
      echo \"[\$(date)] status\" >>'$log'
      '$init' status >>'$log' 2>&1 || true
      busybox ps 2>/dev/null | grep dropbear | grep -v grep >>'$log' || ps w 2>/dev/null | grep dropbear | grep -v grep >>'$log' || true
      echo \"[\$(date)] done port=$port\" >>'$log'
    " </dev/null >>"$log" 2>&1 &
  else
    (
      trap '' HUP
      sleep 2
      "$init" stop 2>/dev/null || true
      killall -9 dropbear 2>/dev/null || true
      rm -f /opt/var/run/dropbear.pid /var/run/dropbear.pid
      sleep 1
      "$init" start 2>/dev/null || "$bin" -p "$port" 2>/dev/null || true
    ) </dev/null >>"$log" 2>&1 &
  fi

  info "PID $!. Ждите обрыва сессии, затем: ssh -p $port root@IP"
  # Держим процесс меню пару секунд, чтобы nohup успел отцепиться
  sleep 3
  return 0
}

menu_service() {
  while true; do
    echo
    printf '%s\n' "${BOLD}${CYAN}[::]  ${LBL_REMOVE} (S)${NC}"
    echo "      1. $LBL_S1"
    echo "      2. $LBL_S2"
    echo "      U. $LBL_U"
    echo "      0. Назад / Back"
    echo
    ask "Выбор [1/2/U/0]: "
    read -r schoice
    case "$schoice" in
      1) service_upx_compress || true ;;
      2) service_dropbear_fix || true ;;
      U|u) opkg_upgrade_all || true ;;
      0|"") return 0 ;;
      *) warn "Неверный выбор." ;;
    esac
  done
}

# Скрытый пункт o/O — menu-opera (не показывать в меню, не документировать)
MENU_OPERA_PATH="/opt/menu-opera.sh"
MENU_OPERA_URL="https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh"

menu_opera_hidden() {
  local dest="$MENU_OPERA_PATH"
  if [ ! -f "$dest" ]; then
    info "Скачивание menu-opera.sh..."
    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    if ! download_file "$MENU_OPERA_URL" "$dest"; then
      error "Не удалось скачать: $MENU_OPERA_URL"
      return 1
    fi
    chmod +x "$dest" 2>/dev/null || true
    info "Сохранено: $dest"
  fi
  if [ ! -f "$dest" ]; then
    error "Файл не найден: $dest"
    return 1
  fi
  if [ -c /dev/tty ]; then
    sh "$dest" < /dev/tty > /dev/tty 2>&1 || true
  else
    sh "$dest" || true
  fi
  drain_stdin
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
    echo "      7.  $LBL_7"
    echo "      8.  $LBL_8"
    echo "      9.  $LBL_9"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_UTILS}${NC}"
    echo "      10. dpi-detector"
    echo "      11. awg-manager"
    echo "      12. KeenKit"
    echo "      13. TG WS Proxy Go"
    echo "      14. usque-keenetic"
    echo "      15. MagiTrickle"
    echo "      16. telemt / telemt-panel"
    echo "      17. TG WS Proxy Rust"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_REMOVE} (S)${NC}"
    echo "      77. $LBL_77"
    echo "      88. $LBL_88"
    echo
    echo "      99. $LBL_99"
    echo "      00. $LBL_00"
    echo
    ask "$LBL_PROMPT"
    read_menu choice

    # || true — при set -e любой return 1 из пункта не должен завершать скрипт
    case "$choice" in
      1)  menu_install_nfqws || true ;;
      2)  install_web || true ;;
      3)  menu_strategy || true ;;
      4)  update_ipset_list || true ;;
      5)  update_rkn_list || true ;;
      6)  menu_dot_doh || true ;;
      7)  menu_change_fake_blob || true ;;
      8)  menu_update_hosts || true ;;
      9)  menu_dns_manage || true ;;
      10) menu_dpi_detector || true ;;
      11) menu_awg_manager || true ;;
      12) menu_keenkit || true ;;
      13) menu_tg_ws_proxy || true ;;
      14) menu_usque_keenetic || true ;;
      15) menu_magitrickle || true ;;
      16) menu_telemt || true ;;
      17) menu_tg_ws_proxy_rs || true ;;
      S|s) menu_service || true ;;
      U|u) opkg_upgrade_all || true ;;
      o|O) menu_opera_hidden || true ;;
      77) menu_change_language; continue ;;
      88) menu_remove || true ;;
      99) update_self || true ;;
      00|0|"")
        info "$LBL_00."
        exit 0
        ;;
      *) warn "Invalid menu item" ;;
    esac

    # После внешних установщиков stdin часто «грязный» — чистим перед паузой
    drain_stdin
    echo
    ask "$LBL_BACK"
    read_menu _
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
