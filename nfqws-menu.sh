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

SCRIPT_VERSION="0.9.41"

REPO_URL="https://github.com/rndnaame/nfqws-menu"
RAW_BASE="https://raw.githubusercontent.com/rndnaame/nfqws-menu/main"
STRATEGIES_API="https://api.github.com/repos/rndnaame/nfqws-menu/contents/strategies"

# Туннели для fallback-скачивания, если основной канал недоступен (DPI и т.п.)
# Порядок = приоритет. opkgtun0 — usque; opgktun0 — на случай другого имени.
FALLBACK_IFACES="awg0 t2s0 nwg0 opkgtun0 opgktun0"

# Таймауты скачивания (сек). Чуть выше для сильного DPI, но не слишком —
# чтобы быстрее уходить на fallback/зеркало.
CURL_CONNECT_TIMEOUT=5
CURL_MAX_TIME=25
CURL_MAX_TIME_LARGE=180   # rkn.list ~2 МБ и подобные
WGET_TIMEOUT=20

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
      UPD_MARK=" ⭡"
      LBL_UPD_LEGEND="⭡ — доступна новая версия"
      LBL_INSTALLED="Установленные компоненты:"
      LBL_NONE="— ничего не установлено —"
      LBL_COMPONENTS="КОМПОНЕНТЫ"
      LBL_STRATEGIES="СТРАТЕГИИ / СПИСКИ"
      LBL_UTILS="УТИЛИТЫ"
      LBL_REMOVE="СЕРВИС"
      LBL_S1="Сжать bin/sbin (UPX)"
      LBL_S2="Dropbear fix"
      LBL_U="Обновить все пакеты"
      LBL_1="Установка NFQWS / NFQWS2"
      LBL_3="Выбор стратегии"
      LBL_4="Обновить IPSet List"
      LBL_5="Загрузить rkn.list (125k+ доменов)"
      LBL_6="Обход блокировки DoT/DoH"
      LBL_7="Смена активных fake:blob"
      LBL_8="Обновление hosts"
      LBL_9="Управление DoT/DoH"
      LBL_88="Удаление пакетов"
      LBL_99="Обновить скрипт"
      LBL_00="Выход"
      LBL_PROMPT="Выберите пункт [Enter = выход]: "
      LBL_BACK="Нажмите Enter для возврата в меню..."
      LBL_MODEL="Модель:"
      LBL_LANG="Language: RU"
      LBL_INVALID="Неверный пункт меню"
      LBL_BACK_ITEM="Назад"
      LBL_CANCEL="Отмена"
      LBL_YOUR_CHOICE="Ваш выбор"
      LBL_CHOICE="Выбор"
      LBL_INSTALL_TITLE="Установка NFQWS / NFQWS2"
      LBL_IPK_TITLE="Установка / обновление .ipk (обход DPI)"
      LBL_IPK_MENU="Установка / обновление .ipk (обход DPI)"
      LBL_IPSET_WARN1="⚠ ОСТОРОЖНО"
      LBL_IPSET_WARN2="Вы собираетесь изменить ipset.list."
      LBL_IPSET_WARN3="Большой список CIDR от Flowseal (33K+) может нагрузить роутер"
      LBL_IPSET_WARN4="и поломать работу отдельных сервисов / сайтов."
      LBL_IPSET_OPT1="Загрузить IPSet от FlowSeal (33K+ CIDR)"
      LBL_IPSET_OPT2="Загрузить стандартный IPSet от nfqws-keenetic"
      ;;
    *)
      UI_LANG="en"
      UI_UTF8=0
      RUN_MARK=" *"
      UPD_MARK=" ⭡"
      LBL_UPD_LEGEND="⭡ — newer version available"
      LBL_INSTALLED="Installed components:"
      LBL_NONE="(none)"
      LBL_COMPONENTS="COMPONENTS"
      LBL_STRATEGIES="STRATEGIES / LISTS"
      LBL_UTILS="UTILITIES"
      LBL_REMOVE="SERVICE"
      LBL_S1="Compress bin/sbin (UPX)"
      LBL_S2="Dropbear fix"
      LBL_U="Upgrade all packages"
      LBL_1="Install NFQWS / NFQWS2"
      LBL_3="Select strategy"
      LBL_4="Update IPSet list"
      LBL_5="Download rkn.list (125k+ domains)"
      LBL_6="Bypass DoT/DoH blocking"
      LBL_7="Switch active fake:blob"
      LBL_8="Update hosts file"
      LBL_9="Manage DoT/DoH DNS"
      LBL_88="Remove packages"
      LBL_99="Update this script"
      LBL_00="Exit"
      LBL_PROMPT="Select an option [Enter = exit]: "
      LBL_BACK="Press Enter to return to the menu..."
      LBL_MODEL="Model:"
      LBL_LANG="Language: EN"
      LBL_INVALID="Invalid menu option"
      LBL_BACK_ITEM="Back"
      LBL_CANCEL="Cancel"
      LBL_YOUR_CHOICE="Your choice"
      LBL_CHOICE="Choice"
      LBL_INSTALL_TITLE="Install NFQWS / NFQWS2"
      LBL_IPK_TITLE="Install / update .ipk (bypass DPI)"
      LBL_IPK_MENU="Install / update .ipk (bypass DPI)"
      LBL_IPSET_WARN1="⚠ CAUTION"
      LBL_IPSET_WARN2="You are about to change ipset.list."
      LBL_IPSET_WARN3="A large Flowseal CIDR list (33K+) may load the router"
      LBL_IPSET_WARN4="and break some services / websites."
      LBL_IPSET_OPT1="Download IPSet from FlowSeal (33K+ CIDR)"
      LBL_IPSET_OPT2="Download standard IPSet from nfqws-keenetic"
      ;;
  esac
}

ui_apply_lang "$(ui_detect_default_lang)"

# --- Проверка новых версий: значения по умолчанию --------------------------
# Метки и подпись задаёт ui_apply_lang; здесь — только то, что нужно, если
# отрисовка случится до выбора языка.
: "${UPD_MARK:= ⭡}"
: "${LBL_UPD_LEGEND:=$UPD_MARK - a newer version is available}"
UPD_TTL="${NFQWS_MENU_UPDATE_TTL:-600}"   # 10 мин
UPD_REDRAW=0
UPD_JOB=""
MENU_PID=""

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
  # Порядок: оригинал → CDN → ghproxy (мёртвый proxy не первым)
  local url="$1" rest owner repo ref path_rest

  case "$url" in
    https://raw.githubusercontent.com/*)
      rest="${url#https://raw.githubusercontent.com/}"
      owner="${rest%%/*}"; rest="${rest#*/}"
      repo="${rest%%/*}"; rest="${rest#*/}"
      ref="${rest%%/*}"; path_rest="${rest#*/}"
      if [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$ref" ] && [ -n "$path_rest" ]; then
        case "$ref" in
          refs/heads/*) ref="${ref#refs/heads/}" ;;
          refs/tags/*)  ref="${ref#refs/tags/}" ;;
        esac
        printf '%s\n' "https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path_rest}"
        printf '%s\n' "https://fastly.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path_rest}"
        printf '%s\n' "https://cdn.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path_rest}"
        printf '%s\n' "https://ghproxy.net/https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path_rest}"
        return 0
      fi
      ;;
    https://api.github.com/*)
      printf '%s\n' "$url"
      printf '%s\n' "https://ghproxy.net/${url}"
      return 0
      ;;
    https://github.com/*/releases/download/*)
      printf '%s\n' "$url"
      printf '%s\n' "https://ghproxy.net/${url}"
      return 0
      ;;
    https://*.github.io/*|http://*.github.io/*)
      printf '%s\n' "$url"
      printf '%s\n' "https://ghproxy.net/${url}"
      return 0
      ;;
  esac
  printf '%s\n' "$url"
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
# ---------------------------------------------------------------------------
# Единое скачивание: зеркала → (опц.) туннели → проверки
# download_file URL DEST [progress] [sh] [min=N] [timeout=N] [connect=N]
#   progress  — progress-bar (большие файлы)
#   sh        — shebang + sh -n (install.sh / меню)
#   min=N     — минимум байт (для sh по умолчанию 8000)
#   timeout=N — CURL_MAX_TIME / WGET на эту загрузку
# ---------------------------------------------------------------------------
download_file() {
  local url="$1" dest="$2"
  shift 2
  local progress=0 validate_sh=0 min_bytes=0 timeout="" connect=""
  local alt iface sz syn_err ok=0 _c _m _w

  while [ $# -gt 0 ]; do
    case "$1" in
      progress) progress=1 ;;
      sh|script) validate_sh=1 ;;
      min=*) min_bytes="${1#min=}" ;;
      timeout=*) timeout="${1#timeout=}" ;;
      connect=*) connect="${1#connect=}" ;;
    esac
    shift
  done

  case "$min_bytes" in ''|*[!0-9]*) min_bytes=0 ;; esac
  if [ "$validate_sh" -eq 1 ] && [ "$min_bytes" -eq 0 ]; then
    min_bytes=8000
  fi

  mkdir -p "$(dirname "$dest")" 2>/dev/null || true
  rm -f "$dest"

  _c="$CURL_CONNECT_TIMEOUT"
  _m="$CURL_MAX_TIME"
  _w="$WGET_TIMEOUT"
  if [ -n "$connect" ]; then
    CURL_CONNECT_TIMEOUT="$connect"
  else
    CURL_CONNECT_TIMEOUT=5
  fi
  if [ -n "$timeout" ]; then
    CURL_MAX_TIME="$timeout"
    WGET_TIMEOUT="$timeout"
  elif [ "$progress" -eq 1 ]; then
    CURL_MAX_TIME="$CURL_MAX_TIME_LARGE"
    WGET_TIMEOUT="$CURL_MAX_TIME_LARGE"
  else
    CURL_MAX_TIME=25
    WGET_TIMEOUT=20
  fi

  for alt in $(github_alt_urls "$url"); do
    rm -f "$dest"
    # Только fallback-зеркала (основной URL уже в «Источник:»)
    [ "$validate_sh" -eq 1 ] && [ "$alt" != "$url" ] && info "Пробуем зеркало: $alt" >&2
    if [ "$progress" -eq 1 ]; then
      _http_get_file_progress "$alt" "$dest" || continue
    else
      _http_get_file "$alt" "$dest" || continue
    fi

    sz=$(wc -c < "$dest" 2>/dev/null | tr -d ' \t')
    case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
    if [ "$min_bytes" -gt 0 ] && [ "$sz" -lt "$min_bytes" ]; then
      warn "Обрывок (${sz} Б < ${min_bytes}) — другой источник..." >&2
      rm -f "$dest"
      continue
    fi
    if [ "$validate_sh" -eq 1 ]; then
      if ! head -1 "$dest" | grep -qE '^#!/(usr/)?bin/(sh|bash)'; then
        warn "Нет shebang — пропуск источника" >&2
        rm -f "$dest"
        continue
      fi
      syn_err=$(sh -n "$dest" 2>&1) || {
        warn "Скрипт битый (syntax) — пропуск источника" >&2
        [ -n "$syn_err" ] && printf '%s\n' "$syn_err" >&2
        rm -f "$dest"
        continue
      }
    fi

    ok=1
    [ "$alt" != "$url" ] && info "Скачано через зеркало" >&2
    break
  done

  if [ "$ok" -ne 1 ] && command -v curl >/dev/null 2>&1; then
    for iface in $(list_up_fallback_ifaces); do
      warn "Основной канал недоступен, пробуем через $iface ..." >&2
      for alt in $(github_alt_urls "$url"); do
        rm -f "$dest"
        if [ "$progress" -eq 1 ]; then
          _http_get_file_progress "$alt" "$dest" "$iface" || continue
        else
          _http_get_file "$alt" "$dest" "$iface" || continue
        fi
        sz=$(wc -c < "$dest" 2>/dev/null | tr -d ' \t')
        case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
        if [ "$min_bytes" -gt 0 ] && [ "$sz" -lt "$min_bytes" ]; then
          rm -f "$dest"
          continue
        fi
        if [ "$validate_sh" -eq 1 ]; then
          head -1 "$dest" | grep -qE '^#!/(usr/)?bin/(sh|bash)' || { rm -f "$dest"; continue; }
          sh -n "$dest" 2>/dev/null || { rm -f "$dest"; continue; }
        fi
        ok=1
        info "Скачано через $iface" >&2
        break 2
      done
    done
  fi

  CURL_CONNECT_TIMEOUT="$_c"
  CURL_MAX_TIME="$_m"
  WGET_TIMEOUT="$_w"

  if [ "$ok" -ne 1 ] || [ ! -s "$dest" ]; then
    rm -f "$dest"
    return 1
  fi
  return 0
}

# Совместимость: тонкие обёртки (1–2 вызова в меню)
download_file_progress() {
  download_file "$1" "$2" progress
}

download_sh_validated() {
  download_file "$1" "$2" sh "min=${3:-8000}" connect=5 timeout=25
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

# ---------------------------------------------------------------------------
# Удалённые .sh: скачать (validated) + выполнить на полном tty
# ---------------------------------------------------------------------------
# $1=url  [$2=min_bytes, по умолчанию 8000; для коротких installers — 2000]
_run_remote_sh_restore_traps() {
  if [ -n "${MENU_PID:-}" ]; then
    trap 'upd_cleanup' EXIT
  else
    trap - EXIT
  fi
  trap - INT TERM
}

run_remote_sh() {
  local url="$1" min_bytes="${2:-8000}" tmp rc=0
  rm -f /tmp/nfqws-remote-*.sh 2>/dev/null || true
  tmp="/tmp/nfqws-remote-$$.sh"
  trap 'rm -f /tmp/nfqws-remote-$$.sh 2>/dev/null; _run_remote_sh_restore_traps' EXIT INT TERM

  if ! download_sh_validated "$url" "$tmp" "$min_bytes"; then
    error "Не удалось скачать целый скрипт: $url"
    rm -f "$tmp"
    _run_remote_sh_restore_traps
    return 1
  fi

  # Полный tty — иначе интерактив (awg-menu и т.п.) не поднимается
  if [ -c /dev/tty ]; then
    sh "$tmp" < /dev/tty > /dev/tty 2>&1 || rc=$?
  else
    sh "$tmp" || rc=$?
  fi
  rm -f "$tmp"
  _run_remote_sh_restore_traps
  drain_stdin
  return "$rc"
}

# Единый формат пункта меню → удалённый установщик:
#   [+] Открываем: 11. awg-manager
#   [+] Источник: https://...
#   ================================================
# $1=номер  $2=название  $3=url  [$4=min_bytes]
run_menu_remote_sh() {
  local num="$1" name="$2" url="$3" min_bytes="${4:-8000}"
  echo
  info "Открываем: ${num}. ${name}"
  info "Источник: $url"
  printf '%s\n' "================================================"
  run_remote_sh "$url" "$min_bytes"
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
# Архитектура / модель (кэш)
# ---------------------------------------------------------------------------
ARCH=""
ARCH_RAW=""
ARCH_SOURCE=""   # opkg | conf | uname | ""
ROUTER_MODEL=""
ROUTER_TITLE=""  # title из RCI, напр. 5.1.5
RCI_CHECKED=0
RCI_HAS_NF_KMOD=""  # 1=есть opkg-kmod-netfilter в components, 0=нет, ""=RCI недоступен

# Нормализация сырого идентификатора → ARCH (mipsel|mips|aarch64|x86_64|x86).
# Пустой результат = не распознано. mipsel* / mipselsf* проверяются ДО mips*.
_arch_normalize() {
  case "$1" in
    aarch64*|arm64*)                    echo "aarch64" ;;
    # 32-bit ARM: в репозиториях nfqws обычно нет отдельной ветки
    armv7*|armv6*|arm*)                 echo "" ;;
    mipsel*|mipselsf*|mips64el*)        echo "mipsel" ;;
    mips*|mipssf*)                      echo "mips" ;;
    x86_64*|amd64*|x64*)                echo "x86_64" ;;
    i[3-6]86*|x86*|i686*)               echo "x86" ;;
    *)                                  echo "" ;;
  esac
}

# Лучшая строка «arch NAME PRIORITY» из stdin (opkg print-architecture или opkg.conf).
_arch_pick_best() {
  awk '
    $1 == "arch" && $2 != "" && $2 != "all" {
      p = $3 + 0
      n = $2
      bonus = 0
      if (n ~ /^mipsel/ || n ~ /^mipselsf/ || n ~ /^mips64el/) bonus = 2
      else if (n ~ /^aarch64/ || n ~ /^arm64/) bonus = 2
      score = p * 10 + bonus
      if (score > best) { best = score; name = n }
    }
    END { if (name != "") print name }
  '
}

_arch_from_opkg() {
  opkg print-architecture 2>/dev/null | _arch_pick_best
}

# /opt/etc/opkg.conf — arch … или URL src/gz (mipselsf-k3.4, aarch64-k3.10, …)
_arch_from_opkg_conf() {
  local conf="${1:-/opt/etc/opkg.conf}" line name from_url=""
  [ -f "$conf" ] || return 0

  name=$(grep -E '^[[:space:]]*arch[[:space:]]+' "$conf" 2>/dev/null | _arch_pick_best)
  if [ -n "$name" ]; then
    printf '%s\n' "$name"
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      src/gz*|src\ *)
        case "$line" in
          *mipselsf*|*mips64el*) from_url="mipselsf"; break ;;
          *mipssf*)              from_url="mipssf"; break ;;
          *aarch64*|*arm64*)     from_url="aarch64"; break ;;
          */x64*|*x86_64*)       from_url="x86_64"; break ;;
          */x86*|*i386*)         from_url="x86"; break ;;
        esac
        ;;
    esac
  done < "$conf"
  [ -n "$from_url" ] && printf '%s\n' "$from_url"
}

# RCI show/version: модель + наличие opkg-kmod-netfilter (один раз за сессию)
_rci_fetch() {
  local json
  [ "$RCI_CHECKED" = "1" ] && return 0
  RCI_CHECKED=1
  json=$(curl -s --connect-timeout 2 --max-time 3 "http://127.0.0.1:79/rci/show/version" 2>/dev/null) \
    || json=$(wget -qO- -T 3 "http://127.0.0.1:79/rci/show/version" 2>/dev/null) \
    || json=""
  [ -n "$json" ] || return 0

  ROUTER_MODEL=$(printf '%s' "$json" | sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  ROUTER_TITLE=$(printf '%s' "$json" | sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  if printf '%s' "$json" | grep -q 'opkg-kmod-netfilter'; then
    RCI_HAS_NF_KMOD=1
  else
    RCI_HAS_NF_KMOD=0
  fi
}

# Строка под заголовком: Модель: WR3000P (KN-3811) 5.1.5 aarch64
# ARCH зелёный из opkg, жёлтый из opkg.conf / uname.
print_arch_line() {
  local arch_col
  case "$ARCH_SOURCE" in
    opkg) arch_col="$GREEN" ;;
    conf|uname) arch_col="$YELLOW" ;;
    *) arch_col="$DIM" ;;
  esac

  printf '%s' "${LBL_MODEL:-Model:}"
  if [ -n "$ROUTER_MODEL" ]; then
    printf ' %s' "$ROUTER_MODEL"
  else
    printf ' %s—%s' "$DIM" "$NC"
  fi
  [ -n "$ROUTER_TITLE" ] && printf ' %s' "$ROUTER_TITLE"
  if [ -n "$ARCH" ]; then
    printf ' %s%s%s' "$arch_col" "$ARCH" "$NC"
  fi
  printf '\n'

  if [ "$RCI_HAS_NF_KMOD" = "0" ]; then
    printf '%s\n' "${RED}${BOLD}[!] Через web-интерфейс Keenetic/Netcraze установить пакет «Модули ядра подсистемы Netfilter» (OPKG → Kernel modules for Netfilter).${NC}"
  fi
}

detect_arch() {
  local um cand

  # Уже определено — только перерисовать строку (RCI кэшируется)
  if [ -n "$ARCH" ] || [ -n "$ARCH_SOURCE" ]; then
    _rci_fetch
    print_arch_line
    return 0
  fi

  # 1) opkg print-architecture
  ARCH_RAW=$(_arch_from_opkg)
  ARCH=$(_arch_normalize "$ARCH_RAW")
  [ -n "$ARCH" ] && ARCH_SOURCE="opkg"

  # 2) /opt/etc/opkg.conf
  if [ -z "$ARCH" ]; then
    ARCH_RAW=$(_arch_from_opkg_conf /opt/etc/opkg.conf)
    ARCH=$(_arch_normalize "$ARCH_RAW")
    [ -n "$ARCH" ] && ARCH_SOURCE="conf"
  fi

  # 3) uname -m (mips* не берём — на Keenetic врёт)
  if [ -z "$ARCH" ]; then
    um=$(uname -m 2>/dev/null || true)
    case "$um" in
      mips|mipsel|mips64|mips64el|"") ;;
      *)
        cand=$(_arch_normalize "$um")
        if [ -n "$cand" ]; then
          ARCH="$cand"
          ARCH_RAW="$um"
          ARCH_SOURCE="uname"
        fi
        ;;
    esac
  fi

  [ -z "$ARCH_SOURCE" ] && ARCH_SOURCE="none"

  _rci_fetch
  print_arch_line

  if [ -z "$ARCH" ]; then
    warn "ARCH не определена — установка NFQWS/usque по архитектуре может быть недоступна."
  fi
  return 0
}

need_arch() {
  [ -z "$ARCH" ] && detect_arch
  if [ -z "$ARCH" ]; then
    error "Нужна архитектура: opkg print-architecture или /opt/etc/opkg.conf (uname/RCI на mipsel врут)."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Кэш opkg / процессов
# ---------------------------------------------------------------------------
OPKG_INSTALLED_CACHE=""
PROC_CACHE=""
PORT90_CACHE=""

# Список установленных из /opt/lib/opkg/status (без вызова opkg, без lock).
# Только Status «… installed» (не «not-installed» — старые residual-записи).
# Формат строк: «name - version».
refresh_opkg_cache() {
  local status="/opt/lib/opkg/status"
  [ -r "$status" ] || status="/usr/lib/opkg/status"
  if [ ! -r "$status" ]; then
    OPKG_INSTALLED_CACHE=""
    return 0
  fi
  OPKG_INSTALLED_CACHE=$(awk '
    function flush() {
      # « installed» есть у installed; у not-installed пробела перед installed нет
      if (ok && pkg != "" && ver != "") print pkg " - " ver
      pkg = ""; ver = ""; ok = 0
    }
    /^Package:[[:space:]]*/ {
      flush()
      pkg = $0
      sub(/^Package:[[:space:]]*/, "", pkg)
      next
    }
    /^Version:[[:space:]]*/ {
      ver = $0
      sub(/^Version:[[:space:]]*/, "", ver)
      next
    }
    /^Status:[[:space:]]*/ {
      ok = ($0 ~ / installed/)
      next
    }
    /^$/ { flush() }
    END { flush() }
  ' "$status" 2>/dev/null) || OPKG_INSTALLED_CACHE=""
}

refresh_proc_cache() {
  PROC_CACHE=$(ps w 2>/dev/null || ps 2>/dev/null || true)
}

# Без fork: shell-цикл по кэшу
is_installed() {
  local line pref
  [ -n "$OPKG_INSTALLED_CACHE" ] || refresh_opkg_cache
  pref="$1 - "
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$pref"*) return 0 ;;
    esac
  done <<EOF
$OPKG_INSTALLED_CACHE
EOF
  return 1
}

# Без grep/sed/head — один shell-цикл по кэшу
pkg_version() {
  local line pref
  [ -n "$OPKG_INSTALLED_CACHE" ] || refresh_opkg_cache
  pref="$1 - "
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$pref"*) printf '%s\n' "${line#"$pref"}"; return 0 ;;
    esac
  done <<EOF
$OPKG_INSTALLED_CACHE
EOF
  return 1
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
  # substring в кэше ps — без fork (имена сервисов достаточно уникальны)
  case "$PROC_CACHE" in
    *"$name"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Целое имя команды: tg-ws-proxy ≠ tg-ws-proxy-rs
proc_running_exact() {
  local name="$1" line
  [ -n "$PROC_CACHE" ] || refresh_proc_cache
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"/$name "*|*"/$name"|*" $name "*|*" $name") return 0 ;;
    esac
  done <<EOF
$PROC_CACHE
EOF
  return 1
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

# Один awk: OPKG + PROC + UPD → готовые строки статуса (минимум fork на MIPS)
# Метки ⭡: ключи UPD_CACHE = nfqws-keenetic|nfqws2-keenetic|nfqws-keenetic-web|
#   tg-ws-proxy-rs|dpi-detector|awg-manager (см. upd_check_bg).
show_installed() {
  local out web_up=0 has_sb=0
  local extras="" rs_ver dpi_ver kk_ver
  PORT90_CACHE=""
  refresh_opkg_cache
  refresh_proc_cache

  echo
  printf '%s\n' "${BOLD}${LBL_INSTALLED}${NC}"

  # port 90 / sing-box — один раз
  port_is_open 90 && web_up=1
  { [ -x /opt/etc/awg-manager/singbox/sing-box ] || [ -f /opt/etc/awg-manager/singbox/sing-box ]; } && has_sb=1

  # Внешние tool-версии (не из opkg) — до awk
  if [ -x "${TG_WS_PROXY_RS_BIN:-/opt/bin/tg-ws-proxy-rs}" ]; then
    rs_ver=$(tg_ws_proxy_rs_version 2>/dev/null) || rs_ver="ok"
    extras="${extras}tool|tg-ws-proxy-rs|${rs_ver:-ok}|tg-ws-proxy-rs
"
  fi
  if [ -x /opt/bin/dpi-detector ] || command -v dpi-detector >/dev/null 2>&1; then
    dpi_ver=$(dpi_detector_version 2>/dev/null) || dpi_ver="ok"
    extras="${extras}tool|dpi-detector|${dpi_ver:-ok}|
"
  fi
  if [ -f /opt/keenkit.sh ]; then
    kk_ver=$(sed -n 's/^SCRIPT_VERSION=["'\'']\([^"'\'']*\)["'\''].*/\1/p' /opt/keenkit.sh 2>/dev/null | head -1)
    extras="${extras}tool|KeenKit|${kk_ver:-ok}|
"
  fi
  if [ -x /opt/usr/bin/telemt ] || [ -x /opt/etc/init.d/S99telemt ] || [ -d /opt/etc/telemt ]; then
    _tm_ver=""
    [ -f /opt/etc/telemt/.version ] && _tm_ver=$(head -n1 /opt/etc/telemt/.version 2>/dev/null | tr -d ' \r\n')
    case "$_tm_ver" in v*|V*) _tm_ver=$(printf '%s' "$_tm_ver" | sed 's/^[vV]//') ;; esac
    if [ -z "$_tm_ver" ] && [ -x /opt/usr/bin/telemt ]; then
      _tm_ver=$(/opt/usr/bin/telemt --version 2>/dev/null | head -n1 | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
    fi
    extras="${extras}tool|telemt|${_tm_ver:-ok}|telemt
"
  fi
  if [ -x /opt/sbin/telemt-panel ] || [ -x /opt/etc/init.d/S99telemt-panel ] || [ -d /opt/etc/telemt-panel ]; then
    _tp_ver=""
    # GitHub/бинарник — не в opkg; версия только из .version (пишет установщик)
    [ -f /opt/etc/telemt-panel/.version ] && _tp_ver=$(head -n1 /opt/etc/telemt-panel/.version 2>/dev/null | tr -d ' \r\n')
    case "$_tp_ver" in v*|V*) _tp_ver=$(printf '%s' "$_tp_ver" | sed 's/^[vV]//') ;; esac
    if [ -z "$_tp_ver" ]; then
      _tp_ver=$(opkg list-installed 2>/dev/null | awk '/^telemt-panel[ -]/{print $3; exit}')
      case "$_tp_ver" in *-* ) _tp_ver=$(printf '%s' "$_tp_ver" | cut -d- -f1) ;; esac
    fi
    extras="${extras}tool|telemt-panel|${_tp_ver:-ok}|telemt-panel
"
  fi
  # awg без opkg-пакета, но с каталогом
  if [ -d /opt/etc/awg-manager ]; then
    extras="${extras}awgdir
"
  fi
  # список S* init (имена сервисов)
  if [ -d /opt/etc/init.d ]; then
    local f base
    for f in /opt/etc/init.d/S[0-9][0-9]*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      base=${f##*/}
      # S99name → name (BusyBox: ${var#S[0-9][0-9]} может не сработать — sed fallback)
      base=$(printf '%s' "$base" | sed 's/^S[0-9][0-9]//')
      [ -n "$base" ] || continue
      extras="${extras}init|${base}
"
    done
  fi

  out=$(
    WEB_UP="$web_up" HAS_SB="$has_sb" \
    G="$GREEN" N="$NC" R="${RUN_MARK}" U="${UPD_MARK}" D="$DIM" \
    awk -v none="$LBL_NONE" '
    function ver_gt(a, b,   i, na, nb, xa, xb, ca, cb) {
      if (a == "" || b == "" || a == b) return 0
      na = split(a, A, /[^0-9A-Za-z]+/)
      nb = split(b, B, /[^0-9A-Za-z]+/)
      for (i = 1; i <= na || i <= nb; i++) {
        xa = (i <= na) ? A[i] : "0"
        xb = (i <= nb) ? B[i] : "0"
        if (xa ~ /^[0-9]+$/ && xb ~ /^[0-9]+$/) {
          ca = xa + 0; cb = xb + 0
          if (ca > cb) return 1
          if (ca < cb) return 0
        } else {
          if (xa > xb) return 1
          if (xa < xb) return 0
        }
      }
      return 0
    }
    function row(name, ver, mark,   s) {
      s = sprintf("  %s%-22s%s %s%s", G, name, N, ver, mark)
      print s
      shown++
    }
    function mark_run(on) { return on ? R : "" }
    function mark_upd(pkg, localv,   rem) {
      rem = remote[pkg]
      if (rem == "" || localv == "" || rem == localv) return ""
      if (ver_gt(rem, localv)) return U G rem N
      return ""
    }
    function proc_has(s) { return index(PROC, s) > 0 }

    BEGIN {
      section = "opkg"
      shown = 0
      G = ENVIRON["G"]; N = ENVIRON["N"]; R = ENVIRON["R"]
      U = ENVIRON["U"]; D = ENVIRON["D"]
      WEB_UP = ENVIRON["WEB_UP"] + 0
      HAS_SB = ENVIRON["HAS_SB"] + 0
    }
    /^---PROC---$/ { section = "proc"; next }
    /^---UPD---$/  { section = "upd";  next }
    /^---EXTRA---$/ { section = "extra"; next }
    section == "opkg" {
      if ($0 ~ /^[^ ]+ - /) {
        pkg = $1
        ver = $0
        sub(/^[^ ]+ - /, "", ver)
        opkg[pkg] = ver
      }
      next
    }
    section == "proc" { PROC = PROC $0 "\n"; next }
    section == "upd" {
      if ($1 != "" && $1 != "checked") {
        rem = $0; sub(/^[^ ]+ /, "", rem)
        remote[$1] = rem
      }
      next
    }
    section == "extra" {
      if ($0 == "awgdir") { awgdir = 1; next }
      if ($0 ~ /^tool\|/) {
        n = split($0, t, "|")
        # tool|name|ver|kind
        tname = t[2]; tver = t[3]; tkind = t[4]
        tools[tname] = tver
        tkind_of[tname] = tkind
        next
      }
      if ($0 ~ /^init\|/) {
        svc = substr($0, 6)
        if (svc != "") inits[svc] = 1
        next
      }
      next
    }
    END {
      # --- основные opkg-пакеты ---
      if ("nfqws-keenetic" in opkg) {
        m = mark_run(proc_has("nfqws")) mark_upd("nfqws-keenetic", opkg["nfqws-keenetic"])
        row("nfqws-keenetic", opkg["nfqws-keenetic"], m)
      }
      if ("nfqws2-keenetic" in opkg) {
        m = mark_run(proc_has("nfqws2")) mark_upd("nfqws2-keenetic", opkg["nfqws2-keenetic"])
        row("nfqws2-keenetic", opkg["nfqws2-keenetic"], m)
      }
      if ("nfqws-keenetic-web" in opkg) {
        m = mark_run(WEB_UP || proc_has("lighttpd")) mark_upd("nfqws-keenetic-web", opkg["nfqws-keenetic-web"])
        row("nfqws-keenetic-web", opkg["nfqws-keenetic-web"], m)
      }
      if ("usque-keenetic" in opkg) {
        m = mark_run(proc_has("usque")) mark_upd("usque-keenetic", opkg["usque-keenetic"])
        row("usque-keenetic", opkg["usque-keenetic"], m)
      }
      # tools (tg-ws, dpi, keenkit, telemt)
      if ("tg-ws-proxy-rs" in tools) {
        m = mark_run(proc_has("tg-ws-proxy-rs")) mark_upd("tg-ws-proxy-rs", tools["tg-ws-proxy-rs"])
        row("tg-ws-proxy-rs", tools["tg-ws-proxy-rs"], m)
      }
      if ("magitrickle" in opkg) {
        m = mark_run(proc_has("magitrickle")) mark_upd("magitrickle", opkg["magitrickle"])
        row("magitrickle", opkg["magitrickle"], m)
      }
      if ("dpi-detector" in tools) {
        m = mark_upd("dpi-detector", tools["dpi-detector"])
        row("dpi-detector", tools["dpi-detector"], m)
      }
      # awg-manager
      if (("awg-manager" in opkg) || awgdir) {
        aver = ("awg-manager" in opkg) ? opkg["awg-manager"] : "ok"
        if (HAS_SB) aver = aver " [+SB]"
        up = proc_has("awg-manager") || proc_has("amneziawg") || (HAS_SB && proc_has("sing-box"))
        m = mark_run(up) mark_upd("awg-manager", ("awg-manager" in opkg) ? opkg["awg-manager"] : "")
        row("awg-manager", aver, m)
      }
      if ("KeenKit" in tools) row("KeenKit", tools["KeenKit"], "")
      if ("telemt" in tools) {
        m = mark_run(proc_has("telemt"))
        row("telemt", tools["telemt"], m)
      }
      if ("telemt-panel" in tools) {
        m = mark_run(proc_has("telemt-panel"))
        row("telemt-panel", tools["telemt-panel"], m)
      }

      # прочие init.d
      skip["nfqws"]=1; skip["nfqws2"]=1; skip["lighttpd"]=1; skip["usque"]=1
      skip["tg-ws-proxy"]=1; skip["tg-ws-proxy-rs"]=1; skip["magitrickle"]=1
      skip["telemt"]=1; skip["telemt-panel"]=1
      if (("awg-manager" in opkg) || awgdir) skip["awg-manager"]=1
      for (svc in inits) {
        if (svc in skip) continue
        ver = (svc in opkg) ? opkg[svc] : ""
        m = mark_run(proc_has(svc))
        row(svc, ver, m)
      }

      if (shown == 0) printf "  %s%s%s\n", D, none, N
    }
    ' <<EOF
$OPKG_INSTALLED_CACHE
---PROC---
$PROC_CACHE
---UPD---
$( [ -f "${UPD_CACHE:-}" ] && cat "$UPD_CACHE" 2>/dev/null )
---EXTRA---
$extras
EOF
  )
  printf '%s\n' "$out"
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
    ask "${LBL_YOUR_CHOICE} [0]: "
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
  need_arch || return 1
  info "Установка nfqws-keenetic (версия 1)..."
  install_deps
  ensure_opkg_repo "nfqws-keenetic" "https://nfqws.github.io/nfqws-keenetic/$ARCH"
  opkg install nfqws-keenetic
  info "nfqws-keenetic установлен."
  ask_web_install
}

install_nfqws2() {
  need_arch || return 1
  info "Установка nfqws2-keenetic (версия 2)..."
  if is_installed "nfqws-keenetic"; then
    warn "Обнаружен nfqws-keenetic. Рекомендуется удалить его перед установкой nfqws2."
    if confirm_no "Удалить nfqws-keenetic и веб-интерфейс?"; then
      stop_nfqws1_hard
      opkg remove nfqws-keenetic-web nfqws-keenetic 2>/dev/null || true
      stop_nfqws1_hard
    fi
  fi
  install_deps
  ensure_opkg_repo "nfqws2-keenetic" "https://nfqws.github.io/nfqws2-keenetic/$ARCH"
  opkg install nfqws2-keenetic
  info "nfqws2-keenetic установлен."
  ask_web_install
}

# Суффикс архитектуры в имени .ipk
ipk_arch_suffix() {
  case "${ARCH:-}" in
    mipsel)  echo "mipsel-3.4" ;;
    mips)    echo "mips-3.4" ;;
    aarch64) echo "aarch64-3.10" ;;
    x86_64)  echo "x86_64" ;;
    x86)     echo "x86" ;;
    *)       echo "${ARCH:-unknown}" ;;
  esac
}

ipk_github_repo() {
  case "$1" in
    nfqws-keenetic)     echo "nfqws/nfqws-keenetic" ;;
    nfqws2-keenetic)    echo "nfqws/nfqws2-keenetic" ;;
    nfqws-keenetic-web) echo "nfqws/nfqws-keenetic-web" ;;
    *) return 1 ;;
  esac
}

# Версия из raw VERSION (fetch_url → зеркала jsDelivr/ghproxy)
fetch_pkg_version_file() {
  # Только быстрые зеркала, короткие таймауты (без долгого GitHub)
  local repo="$1" ver url _c _m _w
  _c="$CURL_CONNECT_TIMEOUT"; _m="$CURL_MAX_TIME"; _w="$WGET_TIMEOUT"
  CURL_CONNECT_TIMEOUT=4
  CURL_MAX_TIME=10
  WGET_TIMEOUT=10
  ver=""
  for url in \
    "https://ghproxy.net/https://raw.githubusercontent.com/${repo}/master/VERSION" \
    "https://cdn.jsdelivr.net/gh/${repo}@master/VERSION" \
    "https://fastly.jsdelivr.net/gh/${repo}@master/VERSION"
  do
    ver=$(_http_get_stdout "$url" 2>/dev/null | tr -d ' \t\r\n' | head -1)
    [ -n "$ver" ] && break
    ver=""
  done
  CURL_CONNECT_TIMEOUT="$_c"
  CURL_MAX_TIME="$_m"
  WGET_TIMEOUT="$_w"
  [ -n "$ver" ] || return 1
  printf '%s\n' "$ver"
}

ipk_filename() {
  local pkg="$1" ver="$2" suf
  case "$pkg" in
    nfqws-keenetic-web)
      echo "${pkg}_${ver}_all_entware.ipk"
      ;;
    *)
      suf=$(ipk_arch_suffix)
      echo "${pkg}_${ver}_${suf}.ipk"
      ;;
  esac
}

# Метаданные .ipk: Packages (github.io) → fallback VERSION + имя файла
# stdout: VERSION<TAB>FILENAME
fetch_ipk_meta() {
  # Только VERSION (быстро). Packages не трогаем.
  local base="$1" pkg="$2" ver fn repo
  repo=$(ipk_github_repo "$pkg") || return 1
  ver=$(fetch_pkg_version_file "$repo") || return 1
  fn=$(ipk_filename "$pkg" "$ver")
  printf '%s\t%s\n' "$ver" "$fn"
  return 0
}

# Скачать .ipk: github.io → GitHub Releases
# Путь основного конфига пакета (пусто если не nfqws*)
ipk_conf_path() {
  case "$1" in
    nfqws-keenetic)  echo "/opt/etc/nfqws/nfqws.conf" ;;
    nfqws2-keenetic) echo "/opt/etc/nfqws2/nfqws2.conf" ;;
    *) echo "" ;;
  esac
}

# Каталог etc пакета в data.tar.gz
ipk_etc_dir() {
  case "$1" in
    nfqws-keenetic)  echo "/opt/etc/nfqws" ;;
    nfqws2-keenetic) echo "/opt/etc/nfqws2" ;;
    *) echo "" ;;
  esac
}

# Если opkg не положил conffiles — достаём их из data.tar.gz .ipk
# (типично после «Not deleting modified conffile» + rm -rf: статус opkg
#  считает файлы «пользовательскими» и при install не восстанавливает)
extract_ipk_etc() {
  local ipk="$1" pkg="$2" tmp etc
  etc=$(ipk_etc_dir "$pkg")
  [ -n "$etc" ] && [ -f "$ipk" ] || return 1

  tmp="/tmp/ipk-ex-$$"
  rm -rf "$tmp"
  mkdir -p "$tmp" || return 1

  if ! tar -xzf "$ipk" -C "$tmp" 2>/dev/null; then
    rm -rf "$tmp"
    return 1
  fi
  if [ ! -f "$tmp/data.tar.gz" ]; then
    rm -rf "$tmp"
    return 1
  fi

  # пути в архиве: ./opt/etc/nfqws2/...
  if tar -xzf "$tmp/data.tar.gz" -C / ".$etc" 2>/dev/null; then
    :
  elif tar -xzf "$tmp/data.tar.gz" -C / "${etc#/}" 2>/dev/null; then
    :
  else
    # вытащить весь opt/etc/...
    tar -xzf "$tmp/data.tar.gz" -C / --wildcards '*/etc/nfqws2/*' 2>/dev/null || \
    tar -xzf "$tmp/data.tar.gz" -C / --wildcards '*/etc/nfqws/*' 2>/dev/null || true
  fi

  rm -rf "$tmp"
  [ -d "$etc" ] || return 1
  return 0
}

# Установка локального .ipk
#
#  не установлен     → opkg install
#  стоит другая ver  → opkg install (upgrade 1.3.0→1.3.1)
#  стоит та же ver   → force-reinstall
_opkg_install_ipk() {
  # Как вручную: opkg install /tmp/file.ipk — без лишних --force-*
  # (force-maintainer/overwrite на Entware ломали распаковку conffiles)
  local dest="$1" pkg="$2" new_ver="$3"
  local cur

  refresh_opkg_cache

  if ! is_installed "$pkg"; then
    info "Чистая установка $pkg $new_ver"
    opkg install "$dest"
    return $?
  fi

  cur=$(pkg_version "$pkg")
  if [ -n "$cur" ] && [ -n "$new_ver" ] && [ "$cur" != "$new_ver" ]; then
    info "Обновление $pkg: $cur → $new_ver"
    opkg install "$dest"
    return $?
  fi

  # Та же версия: обычный install даст «up to date» и не тронет файлы
  info "Та же версия ($cur) — force-reinstall"
  case "$pkg" in
    nfqws2-keenetic) stop_nfqws2_hard ;;
    nfqws-keenetic)  stop_nfqws1_hard ;;
  esac
  PKG_UPGRADE=1 opkg install --force-reinstall "$dest"
  return $?
}

install_ipk_from_repo() {
  # $1=label $2=pkg $3=base $4=version (опционально)
  local label="$1" pkg="$2" base="$3" ver_hint="${4:-}"
  local meta ver fn url dest repo ok=0 _c _m _w conf

  [ -z "$ARCH" ] && detect_arch
  conf=$(ipk_conf_path "$pkg")
  refresh_opkg_cache

  if [ -n "$ver_hint" ] && [ "$ver_hint" != "?" ]; then
    ver="$ver_hint"
    fn=$(ipk_filename "$pkg" "$ver")
    info "Пакет $pkg $ver"
  else
    info "Получение сведений о пакете $pkg ..."
    meta=$(fetch_ipk_meta "$base" "$pkg") || {
      error "Не удалось определить версию $pkg"
      return 1
    }
    ver=$(printf '%s\n' "$meta" | head -1 | cut -f1 | tr -d '\r')
    fn=$(printf '%s\n' "$meta" | head -1 | cut -f2 | tr -d '\r')
  fi
  [ -n "$ver" ] && [ -n "$fn" ] || {
    error "Пустые метаданные для $pkg"
    return 1
  }

  dest="/tmp/${fn}"
  rm -f "$dest"
  info "Скачивание $fn ..."

  repo=$(ipk_github_repo "$pkg") || repo=""
  _c="$CURL_CONNECT_TIMEOUT"; _m="$CURL_MAX_TIME"; _w="$WGET_TIMEOUT"
  CURL_CONNECT_TIMEOUT=8
  CURL_MAX_TIME=90
  WGET_TIMEOUT=90

  # Приоритет: github.com → ghproxy → github.io (с прогрессом)
  for url in \
    ${repo:+"https://github.com/${repo}/releases/download/v${ver}/${fn}"} \
    ${repo:+"https://ghproxy.net/https://github.com/${repo}/releases/download/v${ver}/${fn}"} \
    "${base}/${fn}" \
    "https://ghproxy.net/${base}/${fn}"
  do
    [ -n "$url" ] || continue
    printf '%s\n' "${DIM}  ← $url${NC}" >&2
    if _http_get_file_progress "$url" "$dest" && [ -s "$dest" ]; then
      info "Скачано ($(( $(wc -c < "$dest" | tr -d ' ') / 1024 )) КБ)"
      ok=1
      break
    fi
    rm -f "$dest"
  done

  CURL_CONNECT_TIMEOUT="$_c"
  CURL_MAX_TIME="$_m"
  WGET_TIMEOUT="$_w"

  if [ "$ok" -ne 1 ] || [ ! -s "$dest" ]; then
    error "Не удалось скачать $fn"
    rm -f "$dest"
    return 1
  fi

  if ! _opkg_install_ipk "$dest" "$pkg" "$ver"; then
    error "Не удалось установить $fn"
    rm -f "$dest"
    return 1
  fi

  refresh_opkg_cache

  # opkg иногда не кладёт conffiles — докладываем из .ipk
  if [ -n "$conf" ] && [ ! -f "$conf" ]; then
    warn "opkg не создал $conf — распаковка из .ipk..."
    if extract_ipk_etc "$dest" "$pkg" && [ -f "$conf" ]; then
      info "Конфиги восстановлены из .ipk"
    else
      error "После установки нет $conf"
      rm -f "$dest"
      return 1
    fi
  fi

  if [ -n "$conf" ]; then
    info "$label $ver OK. Конфиг: $conf"
  else
    info "$label $ver установлен."
  fi

  rm -f "$dest"
  return 0
}

menu_install_ipk_direct() {
  local v1="?" v2="?" vweb="?" base1 base2 baseweb meta choice

  need_arch || return 1

  base1="https://nfqws.github.io/nfqws-keenetic/${ARCH}"
  base2="https://nfqws.github.io/nfqws2-keenetic/${ARCH}"
  baseweb="https://nfqws.github.io/nfqws-keenetic-web/all"

  info "Запрос крайних версий .ipk (архитектура: $ARCH) ..."
  meta=$(fetch_ipk_meta "$base1" "nfqws-keenetic" 2>/dev/null) && v1=$(printf '%s\n' "$meta" | head -1 | cut -f1 | tr -d '\r')
  meta=$(fetch_ipk_meta "$base2" "nfqws2-keenetic" 2>/dev/null) && v2=$(printf '%s\n' "$meta" | head -1 | cut -f1 | tr -d '\r')
  meta=$(fetch_ipk_meta "$baseweb" "nfqws-keenetic-web" 2>/dev/null) && vweb=$(printf '%s\n' "$meta" | head -1 | cut -f1 | tr -d '\r')
  [ -z "$v1" ] && v1="?"
  [ -z "$v2" ] && v2="?"
  [ -z "$vweb" ] && vweb="?"
  if [ "$v1" = "?" ] && [ "$v2" = "?" ] && [ "$vweb" = "?" ]; then
    warn "Не удалось получить версии (github.io / GitHub). Проверьте сеть или туннель."
  fi

  echo
  printf '%s\n' "${BOLD}── ${LBL_IPK_TITLE} ──${NC}"
  printf "  %s1)%s  nfqws-keenetic       %s%s%s\n" "$GREEN" "$NC" "$CYAN" "$v1" "$NC"
  printf "  %s2)%s  nfqws2-keenetic      %s%s%s\n" "$GREEN" "$NC" "$CYAN" "$v2" "$NC"
  printf "  %s3)%s  nfqws-keenetic-web   %s%s%s\n" "$GREEN" "$NC" "$CYAN" "$vweb" "$NC"
  printf "  %s0)%s  ${LBL_CANCEL}\n" "$DIM" "$NC"
  ask "${LBL_YOUR_CHOICE} [0]: "
  read_menu choice
  case "$choice" in
    1)
      [ "$v1" = "?" ] && { error "Версия nfqws-keenetic неизвестна."; return 1; }
      install_ipk_from_repo "nfqws-keenetic" "nfqws-keenetic" "$base1" "$v1" || return 1
      ask_web_install
      ;;
    2)
      [ "$v2" = "?" ] && { error "Версия nfqws2-keenetic неизвестна."; return 1; }
      if is_installed "nfqws-keenetic"; then
        warn "Обнаружен nfqws-keenetic. Рекомендуется удалить его перед установкой nfqws2."
        if confirm_no "Удалить nfqws-keenetic и веб-интерфейс?"; then
          stop_nfqws1_hard
          opkg remove nfqws-keenetic-web nfqws-keenetic 2>/dev/null || true
          stop_nfqws1_hard
        fi
      fi
      install_ipk_from_repo "nfqws2-keenetic" "nfqws2-keenetic" "$base2" "$v2" || return 1
      ask_web_install
      ;;
    3)
      [ "$vweb" = "?" ] && { error "Версия nfqws-keenetic-web неизвестна."; return 1; }
      install_ipk_from_repo "nfqws-keenetic-web" "nfqws-keenetic-web" "$baseweb" "$vweb" || return 1
      info "Адрес: http://<IP-роутера>:90"
      info "Логин/пароль — учётные данные Entware (по умолчанию root / keenetic)"
      ;;
    0|"") info "${LBL_CANCEL}."; return 0 ;;
    *) warn "${LBL_INVALID}"; return 1 ;;
  esac
}

menu_install_nfqws() {
  echo
  printf '%s\n' "${BOLD}── ${LBL_INSTALL_TITLE} ──${NC}"
  printf "  %s1)%s  nfqws-keenetic\n" "$GREEN" "$NC"
  printf "  %s2)%s  nfqws2-keenetic\n" "$GREEN" "$NC"
  printf "  %s3)%s  nfqws-keenetic-web\n" "$GREEN" "$NC"
  printf "  %s4)%s  ${LBL_IPK_MENU}\n" "$GREEN" "$NC"
  printf "  %s0)%s  ${LBL_BACK_ITEM}\n" "$DIM" "$NC"
  ask "${LBL_YOUR_CHOICE} [0]: "
  read_menu choice
  case "$choice" in
    1) install_nfqws1 ;;
    2) install_nfqws2 ;;
    3) install_web ;;
    4) menu_install_ipk_direct ;;
    0|"") return ;;
    *) warn "${LBL_INVALID}" ;;
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

# Проверка глобального IPv6 на интерфейсе (любой scope global, не только 2a00*).
# $1 — один iface или несколько через пробел ("ppp0 eth3"): достаточно одного с global.
# Возвращает 0 если найден, иначе 1.
iface_has_global_ipv6() {
  local ifaces="$1" iface
  [ -z "$ifaces" ] && return 1
  for iface in $ifaces; do
    [ -z "$iface" ] && continue
    if command -v ip >/dev/null 2>&1; then
      # любой inet6 … scope global (2a00, 2a02, 2606, 2001, …); без link/host
      if ip -6 addr show dev "$iface" scope global 2>/dev/null | grep -qE 'inet6[[:space:]]+[0-9a-fA-F]'; then
        return 0
      fi
    else
      # ifconfig (BusyBox): "inet6 addr: 2a02:…/64 Scope:Global"
      if ifconfig "$iface" 2>/dev/null | grep -qiE 'inet6.*Scope:Global'; then
        return 0
      fi
    fi
  done
  return 1
}

# Записать ISP_INTERFACE="…" в conf (замена или вставка в начало).
set_isp_interface_line() {
  local conf="$1" val="$2"
  [ -n "$val" ] || return 0
  if grep -qE '^ISP_INTERFACE=' "$conf" 2>/dev/null; then
    sed -i "s|^ISP_INTERFACE=.*|ISP_INTERFACE=\"$val\"|" "$conf"
  else
    printf 'ISP_INTERFACE="%s"\n' "$val" | cat - "$conf" > "${conf}.new" && mv "${conf}.new" "$conf"
  fi
}

# $1=conf  $2=опционально: ISP из конфига ДО смены стратегии (эталон для сравнения)
fix_isp_interface() {
  local conf="$1" preferred="${2:-}" detected current ipv6_val current_ipv6 chosen iface_for_v6 conf_isp
  detected=$(detect_isp_interface)
  if [ -z "$detected" ]; then
    warn "Не удалось определить интерфейс провайдера (route/ip route)."
    return 1
  fi

  # Эталон: переданное значение из старого конфига, иначе то что уже в conf
  # tr -d '\r"' — иначе CRLF из .conf даёт \r и ломает вывод
  if [ -n "$preferred" ]; then
    current=$(printf '%s' "$preferred" | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  else
    current=$(grep -E '^ISP_INTERFACE=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  info "Интерфейс провайдера (default route): ${GREEN}${detected}${NC}"
  if [ -n "$current" ]; then
    info "В текущем конфиге: ISP_INTERFACE=\"${RED}${current}${NC}\""
  else
    info "В текущем конфиге ISP_INTERFACE не задан."
  fi

  chosen=""
  if [ -n "$current" ] && [ "$current" = "$detected" ]; then
    info "ISP_INTERFACE уже совпадает с интерфейсом провайдера."
    chosen="$detected"
  elif [ -z "$current" ]; then
    ask "Установить ISP_INTERFACE=\"${GREEN}${detected}${NC}\"? [${GREEN}Y${NC}/${RED}n${NC}]: "
    read -r ans
    case "$ans" in
      n|N|н|Н) warn "ISP_INTERFACE не изменён." ;;
      *) chosen="$detected" ;;
    esac
  else
    # current ≠ detected: Y → detected, N → оставить как в текущем конфиге
    ask "Установить ISP_INTERFACE=\"${GREEN}${detected}${NC}\"? (в текущем конфиге: \"${RED}${current}${NC}\") [${GREEN}Y${NC}/${RED}n${NC}]: "
    read -r ans
    case "$ans" in
      n|N|н|Н)
        chosen="$current"
        info "Оставляем ISP_INTERFACE=\"${RED}${current}${NC}\" из текущего конфига."
        ;;
      *) chosen="$detected" ;;
    esac
  fi

  if [ -n "$chosen" ]; then
    conf_isp=$(grep -E '^ISP_INTERFACE=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$conf_isp" != "$chosen" ]; then
      set_isp_interface_line "$conf" "$chosen"
      info "ISP_INTERFACE=\"$chosen\" записан в $conf"
    fi
  fi

  # --- IPV6_ENABLED: по фактическому ISP (chosen или то что в conf / detected) ---
  iface_for_v6="$chosen"
  [ -z "$iface_for_v6" ] && iface_for_v6=$(grep -E '^ISP_INTERFACE=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$iface_for_v6" ] && iface_for_v6="$detected"

  echo
  info "=== Проверка IPv6 на $iface_for_v6 ==="
  if iface_has_global_ipv6 "$iface_for_v6"; then
    ipv6_val=1
    info "Найден глобальный IPv6 (scope global) на $iface_for_v6 → IPV6_ENABLED=1"
  else
    ipv6_val=0
    info "Глобальный IPv6 на $iface_for_v6 не найден → IPV6_ENABLED=0"
  fi

  current_ipv6=$(grep -E '^IPV6_ENABLED=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ "$current_ipv6" = "$ipv6_val" ]; then
    info "IPV6_ENABLED уже = $ipv6_val — без изменений."
  else
    if grep -qE '^IPV6_ENABLED=' "$conf" 2>/dev/null; then
      sed -i "s|^IPV6_ENABLED=.*|IPV6_ENABLED=$ipv6_val|" "$conf"
    else
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
  local init_script stopped_svc=0 cache_file saved_isp=""

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

  # ISP_INTERFACE из текущего конфига (до замены стратегией) — эталон для сравнения с route
  if grep -qE '^ISP_INTERFACE=' "$conf_dest" 2>/dev/null; then
    saved_isp=$(grep -E '^ISP_INTERFACE=' "$conf_dest" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
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
  # $saved_isp — значение из конфига до смены стратегии
  fix_isp_interface "$conf_dest" "$saved_isp"

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

  # ts-фулинг: нужен TCP timestamp на Windows
  warn_ts_fooling "$conf_dest"

  echo
  service_restart "$(nfqws_init_path "$ver")"
  info "Сервис перезапущен."
}

# Предупреждение, если в конфиге --dpi-desync-fooling=ts или tcp_ts
warn_ts_fooling() {
  local conf="$1"
  [ -f "$conf" ] || return 0
  # ищем в не-комментариях
  if ! grep -vE '^[[:space:]]*#' "$conf" 2>/dev/null | grep -qE -- '--dpi-desync-fooling=ts|tcp_ts'; then
    return 0
  fi
  echo
  printf '%s\n' "${RED}${BOLD}⚠ ВАЖНО${NC}"
  printf '%s\n' "${RED}При использовании ts-фулинг в стратегиях нужно убедиться,${NC}"
  printf '%s\n' "${RED}что TCP timestamp включён и работает (только для WINDOWS ОС).${NC}"
  echo
  printf '%s\n' "${RED}Включить метки времени RFC 1323 (CMD от администратора):${NC}"
  echo
  printf '%s\n' "${RED}  netsh interface tcp set global timestamps=enabled${NC}"
  echo
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

  echo "   0) ${LBL_BACK_ITEM}"
  ask "${LBL_YOUR_CHOICE} [0]: "
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
  echo "   0) ${LBL_BACK_ITEM}"
  ask "${LBL_YOUR_CHOICE} [0]: "
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
IPSET_FLOWSEAL_URL="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt"
# Стандартные списки из официальных пакетов nfqws
IPSET_NFQWS1_URL="https://raw.githubusercontent.com/nfqws/nfqws-keenetic/master/etc/nfqws/ipset.list"
IPSET_NFQWS2_URL="https://raw.githubusercontent.com/nfqws/nfqws2-keenetic/master/etc/nfqws2/lists/ipset.list"

# Санитизация hostlist/ipset: без #/; пустых, хвостовых пробелов и \r (CRLF).
# $1=src $2=dest → count. 0=ok, 1=пусто/ошибка.
_list_file_clean() {
  local src="$1" dest="$2"
  awk '!/^[[:space:]]*([#;]|$)/ {
    gsub(/[ \t\r]+$/, "")
    if ($0 != "") print
  }' "$src" > "$dest" 2>/dev/null || true
  count=$(wc -l < "$dest" 2>/dev/null | tr -d ' ')
  [ -n "$count" ] && [ "$count" != "0" ]
}

# Скачать URL → tmp (очищенный in-place). Выставляет count. 0=ok, 1=ошибка.
_ipset_fetch_clean() {
  local url="$1" tmp="$2"
  info "URL: $url"
  if ! download_file "$url" "$tmp"; then
    error "Не удалось скачать список."
    return 1
  fi
  if ! _list_file_clean "$tmp" "${tmp}.clean"; then
    error "Скачанный файл пуст или не содержит записей."
    rm -f "$tmp" "${tmp}.clean"
    return 1
  fi
  mv -f "${tmp}.clean" "$tmp"
  info "Записей в списке: $count"
  return 0
}

update_ipset_list() {
  need_nfqws_installed || return

  local choice tmp count src_label
  tmp="/tmp/nfqws-ipset-$$.txt"

  echo
  printf '%s\n' "${RED}${BOLD}${LBL_IPSET_WARN1}${NC}"
  printf '%s\n' "${RED}${LBL_IPSET_WARN2}${NC}"
  printf '%s\n' "${RED}${LBL_IPSET_WARN3}${NC}"
  printf '%s\n' "${RED}${LBL_IPSET_WARN4}${NC}"
  echo
  echo "  1) ${LBL_IPSET_OPT1}"
  echo "  2) ${LBL_IPSET_OPT2}"
  echo "  0) ${LBL_BACK_ITEM}"
  ask "${LBL_YOUR_CHOICE} [0]: "
  read -r choice
  case "$choice" in
    1) ;;
    2) ;;
    0|"") return 0 ;;
    *) warn "${LBL_INVALID}"; return 1 ;;
  esac

  pick_nfqws_ver 1 || return

  write_ipset() {
    local dest="$1" dir
    dir=$(dirname "$dest")
    mkdir -p "$dir"
    backup_file "$dest"
    cp "$tmp" "$dest"
    info "Записано: $dest ($count строк)"
  }

  apply_and_restart() {
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
  }

  if [ "$choice" = "1" ]; then
    src_label="Flowseal/zapret-discord-youtube"
    info "Скачивание IPSet с $src_label ..."
    if ! _ipset_fetch_clean "$IPSET_FLOWSEAL_URL" "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    apply_and_restart
    rm -f "$tmp"
    return 0
  fi

  # choice=2 — стандартный ipset из репозитория пакета
  src_label="nfqws (офиставка пакета)"
  info "Скачивание стандартного IPSet ($src_label) ..."

  case "$NFQWS_VER" in
    1)
      if ! _ipset_fetch_clean "$IPSET_NFQWS1_URL" "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      write_ipset "/opt/etc/nfqws/ipset.list"
      service_restart /opt/etc/init.d/S51nfqws
      info "Сервис nfqws перезапущен."
      ;;
    2)
      if ! _ipset_fetch_clean "$IPSET_NFQWS2_URL" "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      write_ipset "/opt/etc/nfqws2/lists/ipset.list"
      service_restart /opt/etc/init.d/S51nfqws2
      info "Сервис nfqws2 перезапущен."
      ;;
    both)
      # v1
      if ! _ipset_fetch_clean "$IPSET_NFQWS1_URL" "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      write_ipset "/opt/etc/nfqws/ipset.list"
      # v2
      if ! _ipset_fetch_clean "$IPSET_NFQWS2_URL" "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      write_ipset "/opt/etc/nfqws2/lists/ipset.list"
      service_restart /opt/etc/init.d/S51nfqws
      service_restart /opt/etc/init.d/S51nfqws2
      info "Сервисы перезапущены."
      ;;
  esac
  rm -f "$tmp"
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

  local tmp="/tmp/nfqws-rkn-$$.txt" count
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
    # Сначала GitHub raw; зеркала — если raw недоступен (DPI)
    local _old_max="$CURL_MAX_TIME" _old_wget="$WGET_TIMEOUT" _ok=0 _u
    CURL_MAX_TIME="${CURL_MAX_TIME_LARGE:-180}"
    WGET_TIMEOUT="$CURL_MAX_TIME"
    for _u in \
      "$RKN_LIST_URL" \
      "https://cdn.jsdelivr.net/gh/IndeecFOX/zapret4rocket@master/extra_strats/TCP/RKN/List.txt" \
      "https://fastly.jsdelivr.net/gh/IndeecFOX/zapret4rocket@master/extra_strats/TCP/RKN/List.txt" \
      "https://ghproxy.net/https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/master/extra_strats/TCP/RKN/List.txt" \
      "$RKN_LIST_MIRROR_URL"
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

    if ! _list_file_clean "$tmp" "${tmp}.clean"; then
      error "Скачанный файл пуст или не содержит записей."
      rm -f "$tmp" "${tmp}.clean"
      return 1
    fi
    mv -f "${tmp}.clean" "$tmp"
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
      cp "$tmp" "$dest"
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

  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# 6. DoT/DoH bypass strategy в NFQWS_ARGS_CUSTOM
# Стратегии: strategies/dns_filter_nfqws1 | strategies/dns_filter_nfqws2
# ---------------------------------------------------------------------------

# Fallback, если скачивание с GitHub недоступно (формат nfqws2 / lua)
DOT_DOH_STRATEGY_NFQWS2='#DNS
--filter-tcp=443,853
--filter-l7=http,tls
--hostlist-domains=dns.iij.jp,dot.sb,dns.sb,doh.sb,dns.google,dot.pub,doh.pub,controld.com,opendns.com,anycast.censurfridns.dk,dns.alidns.com,libredns.gr,cloudflare-dns.com,one.one.one.one,opennameserver.org,cleanbrowsing.org,dns.adguard-dns.com,dns.comss.one,xbox-dns.ru,dns.malw.link,geohide.ru,dns.nextdns.io,dns10.quad9.net,dns.astracat.network,dns.bezmezhau.com,dns.dns-ai.ru,dns.mafioznik.xyz,free.shecan.ir
--out-range=-d10
--payload=tls_client_hello,http_req
--lua-desync=multisplit:pos=1,host+2,midsld+2,endsld-2:seqovl=4:tcp_ts_up
--lua-desync=fake:blob=tls_clienthello:tcp_md5:tcp_seq=10000:tls_mod=rnd,dupsid,sni=ozon.ru:repeats=3
--new
--filter-tcp=443,853
--filter-l7=http,tls
--ipset-ip=104.16.248.249,104.16.249.249,91.239.100.100,89.233.43.71,8.8.8.8,8.8.4.4,1.12.12.12,120.53.53.53,208.67.222.222,208.67.220.220,223.5.5.5,223.6.6.6,116.202.176.26,1.1.1.1,1.0.0.1,1.1.1.2,1.0.0.2,1.1.1.3,1.0.0.3,217.160.70.42,213.202.211.221,81.169.136.222,185.181.61.24,185.228.168.9,185.228.169.9,94.140.14.14,94.140.15.15,94.140.14.140,94.140.14.141,94.140.14.15,94.140.15.16,45.90.28.94,45.90.30.94,76.76.2.11,76.76.10.11,9.9.9.9,9.9.9.10,149.112.112.112,185.222.222.222,45.11.45.11,172.104.93.80
--out-range=-d10
--payload=tls_client_hello,http_req
--lua-desync=multisplit:pos=1,27:seqovl=4:tcp_ts_up
--lua-desync=fake:blob=tls_clienthello:tcp_md5:tcp_seq=10000:tls_mod=rnd,dupsid,sni=ozon.ru:repeats=3
--new
--filter-udp=443,853
--filter-l7=quic
--hostlist-domains=cloudflare-dns.com,dns.adguard-dns.com,dns.nextdns.io,nextdns.io,dns.google,controld.com
--payload=quic_initial
--lua-desync=send:ipfrag:ipfrag_pos_udp=88'

# Fallback для nfqws1 (классический dpi-desync)
DOT_DOH_STRATEGY_NFQWS1='#DNS
--filter-tcp=443,853 --filter-l7=http,tls --hostlist-domains=dns.iij.jp,dot.sb,dns.sb,doh.sb,dns.google,dot.pub,doh.pub,controld.com,opendns.com,anycast.censurfridns.dk,dns.alidns.com,libredns.gr,cloudflare-dns.com,one.one.one.one,opennameserver.org,cleanbrowsing.org,dns.adguard-dns.com,dns.comss.one,xbox-dns.ru,dns.malw.link,geohide.ru,dns.nextdns.io,dns10.quad9.net,dns.astracat.network,dns.bezmezhau.com,dns.dns-ai.ru,dns.mafioznik.xyz,free.shecan.ir --dpi-desync=multisplit,fake --dpi-desync-split-pos=1,host+2,midsld+2,endsld-2 --dpi-desync-split-seqovl=4 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=/opt/etc/nfqws/tls_clienthello.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=ozon.ru --dpi-desync-repeats=3
--new
--filter-tcp=443,853 --filter-l7=http,tls --ipset-ip=104.16.248.249,104.16.249.249,91.239.100.100,89.233.43.71,8.8.8.8,8.8.4.4,1.12.12.12,120.53.53.120,208.67.222.222,208.67.220.220,223.5.5.5,223.6.6.6,116.202.176.26,1.1.1.1,1.0.0.1,1.1.1.2,1.0.0.2,1.1.1.3,1.0.0.3,217.160.70.42,213.202.211.221,81.169.136.222,185.181.61.24,185.228.168.9,185.228.169.9,94.140.14.14,94.140.15.15,94.140.14.140,94.140.14.141,94.140.14.15,94.140.15.16,45.90.28.94,45.90.30.94,76.76.2.11,76.76.10.11,9.9.9.9,9.9.9.10,149.112.112.112,185.222.222.222,45.11.45.11,172.104.93.80 --dpi-desync=multisplit,fake --dpi-desync-split-pos=1,27 --dpi-desync-split-seqovl=4 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=/opt/etc/nfqws/tls_clienthello.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=ozon.ru --dpi-desync-repeats=3
--new
--filter-udp=443,853 --filter-l7=quic --hostlist-domains=cloudflare-dns.com,dns.adguard-dns.com,dns.nextdns.io,nextdns.io,dns.google,controld.com --dpi-desync=ipfrag2 --dpi-desync-ipfrag-pos-udp=88'

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

# Загрузить стратегию dns_filter для ver=1|2 в strat_tmp; return 0 при успехе
load_dot_doh_strategy() {
  local ver="$1" dest="$2"
  local url="${RAW_BASE}/strategies/dns_filter_nfqws${ver}"
  local tmp="/tmp/dns_filter_nfqws${ver}-$$.txt"

  rm -f "$tmp"
  if download_file "$url" "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    # убрать CRLF и пустые ведущие строки
    tr -d '\r' < "$tmp" | sed '/^[[:space:]]*$/d' > "$dest"
    rm -f "$tmp"
    # маркер #DNS в начало, если его нет
    if ! grep -qE '^[[:space:]]*#DNS' "$dest" 2>/dev/null; then
      { printf '%s\n' '#DNS'; cat "$dest"; } > "${dest}.n" && mv "${dest}.n" "$dest"
    fi
    info "Стратегия dns_filter_nfqws${ver} скачана с GitHub."
    return 0
  fi
  rm -f "$tmp"

  warn "Не удалось скачать dns_filter_nfqws${ver} — используем встроенный fallback."
  if [ "$ver" = "1" ]; then
    printf '%s\n' "$DOT_DOH_STRATEGY_NFQWS1" > "$dest"
  else
    printf '%s\n' "$DOT_DOH_STRATEGY_NFQWS2" > "$dest"
  fi
  return 0
}

# Вставить содержимое strat_tmp в NFQWS_ARGS_CUSTOM конфига conf
inject_custom_strategy() {
  local conf="$1" strat_tmp="$2"
  local tmp="/tmp/nfqws-conf-dot-$$.tmp"
  local found=0 in_block=0 has_content=0

  : > "$tmp"
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
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$conf"
  return 0
}

apply_dot_doh_for_ver() {
  local ver="$1"
  local conf init_script strat_tmp svc_name

  conf=$(nfqws_conf_path "$ver")
  init_script=$(nfqws_init_path "$ver")
  if [ "$ver" = "1" ]; then
    svc_name="nfqws"
  else
    svc_name="nfqws2"
  fi

  if [ ! -f "$conf" ]; then
    error "Конфиг $conf не найден."
    return 1
  fi

  if grep -qE '#DNS|dot\.pub,doh\.pub|dns\.iij\.jp|xbox-dns\.ru' "$conf" 2>/dev/null; then
    warn "Похоже, стратегия DoT/DoH уже присутствует в конфиге (nfqws${ver})."
    confirm_no "Добавить повторно?" || { info "Пропуск nfqws${ver}."; return 0; }
  fi

  backup_file "$conf"

  strat_tmp="/tmp/nfqws${ver}-dot-$$.txt"
  load_dot_doh_strategy "$ver" "$strat_tmp" || {
    rm -f "$strat_tmp"
    return 1
  }

  if ! inject_custom_strategy "$conf" "$strat_tmp"; then
    rm -f "$strat_tmp"
    return 1
  fi
  rm -f "$strat_tmp"

  info "Стратегия DoT/DoH (dns_filter_nfqws${ver}) добавлена в NFQWS_ARGS_CUSTOM."

  echo
  info "=== Проверка портов 853 (DoT) [nfqws${ver}] ==="
  ensure_port_in_var "$conf" "TCP_PORTS" "853"
  ensure_port_in_var "$conf" "UDP_PORTS" "853"
  service_restart "$init_script"
  info "Сервис $svc_name перезапущен."
  return 0
}

menu_dot_doh() {
  # refresh — кэш мог устареть; return 0 — set -e не должен выкидывать из меню
  refresh_opkg_cache
  local has1=0 has2=0
  is_installed "nfqws-keenetic"  && has1=1
  is_installed "nfqws2-keenetic" && has2=1

  if [ "$has1" -eq 0 ] && [ "$has2" -eq 0 ]; then
    error "Пункт доступен при установленном nfqws-keenetic и/или nfqws2-keenetic."
    return 0
  fi

  echo
  info "Стратегии: dns_filter_nfqws1 / dns_filter_nfqws2"
  info "  https://github.com/rndnaame/nfqws-menu/blob/main/strategies/dns_filter_nfqws1"
  info "  https://github.com/rndnaame/nfqws-menu/blob/main/strategies/dns_filter_nfqws2"
  echo

  if [ "$has1" -eq 1 ] && [ "$has2" -eq 1 ]; then
    echo "Установлены обе версии."
    echo "  1) nfqws-keenetic  (v1) — dns_filter_nfqws1"
    echo "  2) nfqws2-keenetic (v2) — dns_filter_nfqws2"
    echo "  a) Обе"
    ask "${LBL_YOUR_CHOICE} [0 = отмена]: "
    read_menu c
    case "$c" in
      1)
        confirm_yes "Добавить стратегию обхода DoT/DoH в NFQWS_ARGS_CUSTOM (nfqws1)?" || { info "Отменено."; return 0; }
        apply_dot_doh_for_ver 1 || true
        ;;
      2)
        confirm_yes "Добавить стратегию обхода DoT/DoH в NFQWS_ARGS_CUSTOM (nfqws2)?" || { info "Отменено."; return 0; }
        apply_dot_doh_for_ver 2 || true
        ;;
      a|A|а|А)
        confirm_yes "Добавить стратегию обхода DoT/DoH в оба конфига?" || { info "Отменено."; return 0; }
        apply_dot_doh_for_ver 1 || true
        apply_dot_doh_for_ver 2 || true
        ;;
      *) info "Отменено."; return 0 ;;
    esac
  elif [ "$has1" -eq 1 ]; then
    confirm_yes "Добавить в NFQWS_ARGS_CUSTOM стратегию обхода блокировки DoT/DoH (nfqws1)?" || {
      info "Отменено."; return 0
    }
    apply_dot_doh_for_ver 1 || true
  else
    confirm_yes "Добавить в NFQWS_ARGS_CUSTOM стратегию обхода блокировки DoT/DoH (nfqws2)?" || {
      info "Отменено."; return 0
    }
    apply_dot_doh_for_ver 2 || true
  fi
  return 0
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
22|DNS4EU Protective|protective.joindns4.eu|protective.joindns4.eu|
23|DNS4EU Unfiltered|unfiltered.joindns4.eu|unfiltered.joindns4.eu|
24|OpenNameServer ns1|217.160.70.42|ns1.opennameserver.org|
25|OpenNameServer ns2|213.202.211.221|ns2.opennameserver.org|
26|OpenNameServer ns3|81.169.136.222|ns3.opennameserver.org|
27|OpenNameServer ns4|185.181.61.24|ns4.opennameserver.org|
28|IIJ Japan|public.dns.iij.jp|public.dns.iij.jp|
29|Alibaba DNS|dns.alidns.com|dns.alidns.com|
30|DNSPod|dot.pub|dot.pub|
31|Xbox-DNS|xbox-dns.ru|xbox-dns.ru|
32|Comss DNS|dns.comss.one|dns.comss.one|
33|Malw Link|dns.malw.link|dns.malw.link|
34|NullsProxy|dns.nullsproxy.com|dns.nullsproxy.com|
35|Cloudflare Gateway|5u35p8m9i7.cloudflare-gateway.com|5u35p8m9i7.cloudflare-gateway.com|
36|Geo Hide|geohide.ru|geohide.ru|
37|AstraCat|dns.astracat.network|dns.astracat.network|
38|Bezmezhau|dns.bezmezhau.com|dns.bezmezhau.com|
39|DNS-AI|dns.dns-ai.ru|dns.dns-ai.ru|
40|Mafioznik|dns.mafioznik.xyz|dns.mafioznik.xyz|
41|Shecan Free|free.shecan.ir|free.shecan.ir|
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
12|DNS4EU Protective|https://protective.joindns4.eu/dns-query
13|DNS4EU Unfiltered|https://unfiltered.joindns4.eu/dns-query
14|OpenNameServer ns1|https://ns1.opennameserver.org/dns-query
15|OpenNameServer ns2|https://ns2.opennameserver.org/dns-query
16|OpenNameServer ns3|https://ns3.opennameserver.org/dns-query
17|OpenNameServer ns4|https://ns4.opennameserver.org/dns-query
18|IIJ Japan|https://public.dns.iij.jp/dns-query
19|Alibaba DNS|https://dns.alidns.com/dns-query
20|DNSPod|https://doh.pub/dns-query
21|Xbox-DNS|https://xbox-dns.ru/dns-query
22|Comss DNS|https://dns.comss.one/dns-query
23|Malw Link|https://dns.malw.link/dns-query
24|NullsProxy|https://dns.nullsproxy.com/dns-query
25|Cloudflare Gateway|https://5u35p8m9i7.cloudflare-gateway.com/dns-query
26|Geo Hide|https://dns.geohide.ru/dns-query
27|AstraCat|https://dns.astracat.network/dns-query
28|Bezmezhau|https://dns.bezmezhau.com/dns-query
29|DNS-AI|https://dns.dns-ai.ru/dns-query
30|Mafioznik|https://dns.mafioznik.xyz/dns-query
31|Shecan Free|https://free.shecan.ir/dns-query
EOF
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
  echo "22) DNS4EU Protective (protective.joindns4.eu)"
  echo "23) DNS4EU Unfiltered (unfiltered.joindns4.eu)"
  printf '%s\n' " ${YELLOW}--- OpenNameServer ---${NC}"
  echo "24) OpenNameServer ns1 (217.160.70.42)"
  echo "25) OpenNameServer ns2 (213.202.211.221)"
  echo "26) OpenNameServer ns3 (81.169.136.222)"
  echo "27) OpenNameServer ns4 (185.181.61.24)"
  printf '%s\n' " ${YELLOW}--- Япония & Китай ---${NC}"
  echo "28) IIJ Japan (public.dns.iij.jp)"
  echo "29) Alibaba DNS (dns.alidns.com)"
  echo "30) DNSPod (dot.pub)"
  printf '%s\n' " ${GREEN}--- Proxy-DNS (Обход блокировок) ---${NC}"
  echo "31) Xbox-DNS (xbox-dns.ru)"
  echo "32) Comss DNS (dns.comss.one)"
  echo "33) Malw Link (dns.malw.link)"
  echo "34) NullsProxy (dns.nullsproxy.com)"
  echo "35) Cloudflare Gateway (5u35p8m9i7.cloudflare-gateway.com)"
  echo "36) Geo Hide (geohide.ru)"
  echo "37) AstraCat (dns.astracat.network)"
  echo "38) Bezmezhau (dns.bezmezhau.com)"
  echo "39) DNS-AI (dns.dns-ai.ru)"
  echo "40) Mafioznik (dns.mafioznik.xyz)"
  echo "41) Shecan Free (free.shecan.ir)"
  printf '%s\n' " ${YELLOW}--- Свой вариант ---${NC}"
  echo "42) Ввести вручную (IP / Port / SNI)"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  ask "Привязать выбранные к домену? (пусто для всех): "
  read -r domain

  local added_any=0 choice num label ip sni port
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    if [ "$choice" = "42" ]; then
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
  echo "12) DNS4EU Protective (https://protective.joindns4.eu/dns-query)"
  echo "13) DNS4EU Unfiltered (https://unfiltered.joindns4.eu/dns-query)"
  printf '%s\n' " ${YELLOW}--- OpenNameServer ---${NC}"
  echo "14) OpenNameServer ns1 (https://ns1.opennameserver.org/dns-query)"
  echo "15) OpenNameServer ns2 (https://ns2.opennameserver.org/dns-query)"
  echo "16) OpenNameServer ns3 (https://ns3.opennameserver.org/dns-query)"
  echo "17) OpenNameServer ns4 (https://ns4.opennameserver.org/dns-query)"
  printf '%s\n' " ${YELLOW}--- Япония & Китай ---${NC}"
  echo "18) IIJ Japan (https://public.dns.iij.jp/dns-query)"
  echo "19) Alibaba DNS (https://dns.alidns.com/dns-query)"
  echo "20) DNSPod (https://doh.pub/dns-query)"
  printf '%s\n' " ${GREEN}--- Proxy-DNS (Обход блокировок) ---${NC}"
  echo "21) Xbox-DNS (https://xbox-dns.ru/dns-query)"
  echo "22) Comss DNS Keenetic/MikroTik (https://dns.comss.one/dns-query)"
  echo "23) Malw Link (https://dns.malw.link/dns-query)"
  echo "24) NullsProxy (https://dns.nullsproxy.com/dns-query)"
  echo "25) Cloudflare Gateway (https://5u35p8m9i7.cloudflare-gateway.com/dns-query)"
  echo "26) Geo Hide (https://dns.geohide.ru/dns-query)"
  echo "27) AstraCat (https://dns.astracat.network/dns-query)"
  echo "28) Bezmezhau (https://dns.bezmezhau.com/dns-query)"
  echo "29) DNS-AI (https://dns.dns-ai.ru/dns-query)"
  echo "30) Mafioznik (https://dns.mafioznik.xyz/dns-query)"
  echo "31) Shecan Free (https://free.shecan.ir/dns-query)"
  printf '%s\n' " ${YELLOW}--- Свой вариант ---${NC}"
  echo "32) Ввести вручную (произвольный URI)"
  echo " 0) Отмена"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
  ask "Выберите варианты: "
  read -r raw_choices
  [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

  ask "Привязать выбранные к домену? (пусто для всех): "
  read -r domain

  local added_any=0 choice line uri
  for choice in $(echo "$raw_choices" | tr ',' ' '); do
    if [ "$choice" = "32" ]; then
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
    printf '%s\n' " ${BOLD}0)${NC} ${LBL_BACK_ITEM}"
    printf '%s\n' "${DIM}────────────────────────────────────────────────────────${NC}"
    ask "${LBL_YOUR_CHOICE} [0]: "
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
extract_script_version() {
  grep -E '^SCRIPT_VERSION=' "$1" 2>/dev/null | head -1 | \
    sed -n 's/^SCRIPT_VERSION="\([^"]*\)".*/\1/p'
}

update_self() {
  local dest="/opt/nfqws-menu.sh" tmp="/tmp/nfqws-menu-update-$$.sh"
  local remote_ver url

  info "Скачивание nfqws-menu.sh ..."
  rm -f "$tmp"
  url="${RAW_BASE}/nfqws-menu.sh"
  if ! download_file "$url" "$tmp" sh min=50000 connect=5 timeout=40; then
    error "Не удалось скачать целый скрипт ни с одного источника"
    return 1
  fi
  if ! grep -q 'SCRIPT_VERSION=' "$tmp" 2>/dev/null; then
    error "В файле нет SCRIPT_VERSION"
    rm -f "$tmp"
    return 1
  fi

  remote_ver=$(extract_script_version "$tmp")
  [ -z "$remote_ver" ] && remote_ver="?"
  if [ "$remote_ver" = "$SCRIPT_VERSION" ]; then
    info "Уже актуальная версия: v${SCRIPT_VERSION}"
    rm -f "$tmp"
    return 0
  fi

  info "Установка v${remote_ver} (было v${SCRIPT_VERSION}) → $dest"
  if ! cat "$tmp" > "$dest"; then
    error "Не удалось записать $dest"
    rm -f "$tmp"
    return 1
  fi
  chmod +x "$dest" 2>/dev/null || true
  rm -f "$tmp"
  rm -f "${CACHE_DIR}/updates.cache" 2>/dev/null || true
  unset SCRIPT_PATH
  export SCRIPT_PATH="$dest"
  info "Перезапуск меню..."
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
  if [ -x /opt/bin/dpi-detector ]; then
    echo
    info "Открываем: 10. dpi-detector"
    info "Локально: /opt/bin/dpi-detector"
    printf '%s\n' "================================================"
    cleanup_dpi_detector_dupes
    if [ -c /dev/tty ]; then
      /opt/bin/dpi-detector </dev/tty
    else
      /opt/bin/dpi-detector
    fi
    return 0
  fi
  run_menu_remote_sh "10" "dpi-detector" "$DPI_DETECTOR_INSTALL_URL" || return 1
  echo
  info "Очистка дубликатов dpi-detector (/tmp, /opt/root)..."
  cleanup_dpi_detector_dupes
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
  run_menu_remote_sh "11" "awg-manager" "$AWG_MANAGER_INSTALL_URL" || return 1
}

menu_keenkit() {
  if [ -f /opt/keenkit.sh ]; then
    echo
    info "Открываем: 12. KeenKit"
    info "Локально: /opt/keenkit.sh"
    printf '%s\n' "================================================"
    if [ -c /dev/tty ]; then
      sh /opt/keenkit.sh </dev/tty
    else
      sh /opt/keenkit.sh
    fi
    return 0
  fi
  # install.sh KeenKit — короткий bootstrap (~900 Б), скачивает keenkit.sh
  run_menu_remote_sh "12" "KeenKit" "$KEENKIT_INSTALL_URL" 500 || return 1
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

# Секрет до установки: свой не трогаем, чужой (из Go-установки) переносим — ради
# этого функция и существует, ссылки клиентов после перехода не меняются.
#
# Генерации здесь нет: когда секрета нет ни там ни тут, его создаёт инсталлер
# (write_entware_config → entware_new_secret, `tr -dc 'a-f0-9' < /dev/urandom`).
# Раньше меню генерировало само, потому что инсталлер брал те же 16 байт через
# `od -An -tx1`, а такого ключа у BusyBox нет; с 2.4.6 инсталлер тоже на `tr`,
# проверено на Keenetic (BusyBox 1.37): `od -An` даёт `invalid option -- 'A'`,
# генератор инсталлера — 32 hex-символа в 20 прогонах из 20.
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

  # Секрета нет вовсе: его создаст инсталлер, здесь ничего не пишем — иначе
  # пришлось бы держать второй генератор.
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
# релиза v2.4.5 и больше не перемеряются: от релиза к релизу они гуляют на
# десятые доли процента (v2.5.0 поменял второй знак в трёх ячейках из десяти),
# а таблица нужна, чтобы сравнивать сборки между собой, а не как точный размер.
# Формат: <target> <обычная> <upx>.
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
    ask "${LBL_YOUR_CHOICE} [0]: "
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
  if ! download_sh_validated "$url" "$script" 20000; then
    error "Не удалось скачать целый install.sh — проверьте доступ к GitHub / зеркалам."
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
  info "tg-ws-proxy-rs удалён."
  if [ -d "$TG_WS_PROXY_RS_CONF_DIR" ]; then
    if confirm_no "Удалить конфиг и секрет ($TG_WS_PROXY_RS_CONF_DIR)?"; then
      rm -rf "$TG_WS_PROXY_RS_CONF_DIR"
      info "Каталог $TG_WS_PROXY_RS_CONF_DIR удалён."
    else
      info "Конфиг и секрет оставлены в $TG_WS_PROXY_RS_CONF_DIR."
    fi
  fi
  return 0
}

# 13. usque-keenetic  (installer_usque.sh in this repo)
USQUE_INSTALL_URL="https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_usque.sh"

menu_usque_keenetic() {
  # min=2000: installer_usque.sh ~5 КБ
  if ! run_menu_remote_sh "13" "usque-keenetic" "$USQUE_INSTALL_URL" 2000; then
    error "Установщик usque-keenetic завершился с ошибкой."
    return 1
  fi
  refresh_opkg_cache 2>/dev/null || true
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
# 15. telemt / telemt-panel — installer_telemt.sh
# ---------------------------------------------------------------------------
TELEMT_BUNDLE_URL="https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_telemt.sh"
TELEMT_SYSTEMCTL_URL="https://raw.githubusercontent.com/anch665/keendev/main/systemctl.sh"
TELEMT_JOURNALCTL_URL="https://raw.githubusercontent.com/anch665/keendev/main/journalctl.sh"


is_telemt_installed() {
  [ -x /opt/usr/bin/telemt ] || [ -x /opt/etc/init.d/S99telemt ] || \
    [ -d /opt/etc/telemt ] || [ -x /opt/sbin/telemt-panel ] || \
    [ -x /opt/etc/init.d/S99telemt-panel ] || [ -d /opt/etc/telemt-panel ]
}

remove_telemt() {
  echo
  info "Удаление telemt / telemt-panel..."
  /opt/etc/init.d/S99telemt-panel stop 2>/dev/null || true
  /opt/etc/init.d/S99telemt stop 2>/dev/null || true
  rm -f /opt/etc/init.d/S99telemt /opt/etc/init.d/S99telemt-panel
  rm -f /opt/usr/bin/telemt /opt/sbin/telemt-panel
  rm -rf /opt/etc/telemt /opt/etc/telemt-panel
  rm -rf /opt/tmp/telemt_dl /opt/tmp/telemt-panel-install
  rm -rf /tmp/telemt_dl /tmp/telemt-panel-dl
  rm -f /tmp/log/telemt.log /tmp/cache/beobachten.txt
  info "telemt / telemt-panel удалены."
}

menu_telemt() {
  run_menu_remote_sh "15" "telemt / telemt-panel" "$TELEMT_BUNDLE_URL" 2000 || return 1
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

dpi_detector_version() {
  local bin
  if [ -x /opt/bin/dpi-detector ]; then
    bin="/opt/bin/dpi-detector"
  elif command -v dpi-detector >/dev/null 2>&1; then
    bin=$(command -v dpi-detector)
  else
    return 1
  fi
  "$bin" --version 2>/dev/null | head -1 | \
    sed -n 's/.*dpi-detector[[:space:]]\+\([^[:space:]]*\).*/\1/p'
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
  ask "${LBL_YOUR_CHOICE} [0]: "
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



# Принудительная остановка nfqws/nfqws2 перед remove/reinstall.
# init is_running() ломается на пустом pidfile (bad number / kill without pid),
# из-за чего процесс остаётся висеть после opkg remove.
stop_nfqws2_hard() {
  [ -x /opt/etc/init.d/S51nfqws2 ] && /opt/etc/init.d/S51nfqws2 stop 2>/dev/null || true
  killall nfqws2 2>/dev/null || true
  # на всякий случай по полному пути
  killall /opt/usr/bin/nfqws2 2>/dev/null || true
  rm -f /opt/var/run/nfqws2.pid
}

stop_nfqws1_hard() {
  [ -x /opt/etc/init.d/S51nfqws ] && /opt/etc/init.d/S51nfqws stop 2>/dev/null || true
  killall nfqws 2>/dev/null || true
  killall /opt/usr/bin/nfqws 2>/dev/null || true
  rm -f /opt/var/run/nfqws.pid
}

# Удаление пакета nfqws* с предварительным kill
remove_nfqws_pkg() {
  local pkg="$1"
  case "$pkg" in
    nfqws2-keenetic)
      info "Остановка nfqws2 перед удалением..."
      stop_nfqws2_hard
      ;;
    nfqws-keenetic)
      info "Остановка nfqws перед удалением..."
      stop_nfqws1_hard
      ;;
  esac
  opkg remove "$pkg"
  # хвосты после remove
  case "$pkg" in
    nfqws2-keenetic) stop_nfqws2_hard ;;
    nfqws-keenetic)  stop_nfqws1_hard ;;
  esac
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
  echo "  [0] ${LBL_BACK_ITEM}"
  echo
  ask "${LBL_YOUR_CHOICE} [0]: "
  read -r choice

  case "$choice" in
    0|"") return ;;
    b|B|б|Б) remove_backups ;;
    a|A|а|А)
      if confirm_no "Точно удалить все пакеты NFQWS (и dpi-detector, если есть)?"; then
        stop_nfqws2_hard
        stop_nfqws1_hard
        opkg remove nfqws-keenetic-web nfqws2-keenetic nfqws-keenetic 2>/dev/null || true
        stop_nfqws2_hard
        stop_nfqws1_hard
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
        tg-ws-proxy-rs) remove_tg_ws_proxy_rs ;;
        usque-keenetic) remove_usque_keenetic ;;
        magitrickle)   remove_magitrickle ;;
        opera-proxy)   remove_opera_proxy ;;
        KeenKit)       remove_keenkit ;;
        telemt)        remove_telemt ;;
        nfqws-keenetic|nfqws2-keenetic)
          remove_nfqws_pkg "$target" || true
          info "$target удалён."
          ;;
        *)
          opkg remove "$target"
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
  echo "  0) ${LBL_BACK_ITEM}"
  echo
  ask "${LBL_YOUR_CHOICE} [0]: "
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
    echo "      0. ${LBL_BACK_ITEM}"
    echo
    ask "${LBL_YOUR_CHOICE} [0]: "
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
    if ! download_file "$MENU_OPERA_URL" "$dest" sh min=2000; then
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
# Проверка новых версий: в фоне, чтобы меню открывалось сразу
# ---------------------------------------------------------------------------
# Меню не ждёт сеть: версии с сервера тянет отдельный процесс, он кладёт их в
# кэш и будит меню сигналом USR1, по которому цикл перерисовывает экран. Метки
# появляются сами через секунду-другую после открытия, а сам экран рисуется
# мгновенно — в том числе когда GitHub недоступен.
#
# В кэше лежат только версии с сервера, без сравнения: сравнение с
# установленными делается при отрисовке, поэтому после обновления метка
# исчезает сразу и перепроверка для этого не нужна.
UPD_CACHE="${CACHE_DIR}/updates.cache"

# Версия скрипта меню: первые 2 КБ файла через зеркала — 200 КБ тянуть незачем.
upd_menu_version() {
  local url alt tmp ver
  command -v curl >/dev/null 2>&1 || return 1
  url="${RAW_BASE}/nfqws-menu.sh"
  tmp="/tmp/nfqws-menu-upd-$$"
  for alt in $(github_alt_urls "$url"); do
    curl -fsS -m 8 -r 0-2047 "$alt" -o "$tmp" 2>/dev/null || continue
    ver=$(extract_script_version "$tmp") || ver=""
    if [ -n "$ver" ]; then
      rm -f "$tmp"
      printf '%s' "$ver"
      return 0
    fi
  done
  rm -f "$tmp"
  return 1
}

# Тег последнего стабильного релиза из редиректа releases/latest (без pre-release).
upd_release_tag() {   # $1 = owner/repo
  local url alt loc
  command -v curl >/dev/null 2>&1 || return 1
  url="https://github.com/$1/releases/latest"
  for alt in $(github_alt_urls "$url"); do
    loc=$(curl -sS -m 8 -o /dev/null -w '%{redirect_url}' "$alt" 2>/dev/null) || continue
    case "$loc" in
      */releases/tag/*)
        printf '%s' "${loc##*/releases/tag/}" | sed 's/^v//'
        return 0
        ;;
    esac
  done
  return 1
}

# Новейший релиз включая pre-release (API releases?per_page=1).
# Нужен для dpi-detector: все теги — prerelease, /releases/latest пустой.
upd_release_tag_any() {   # $1 = owner/repo
  local repo="$1" url json tag
  command -v curl >/dev/null 2>&1 || return 1
  for url in \
    "https://api.github.com/repos/${repo}/releases?per_page=1" \
    "https://ghproxy.net/https://api.github.com/repos/${repo}/releases?per_page=1"
  do
    json=$(curl -fsS -m 10 -H 'Accept: application/vnd.github+json' "$url" 2>/dev/null) || continue
    tag=$(printf '%s' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$tag" ] || continue
    printf '%s' "$tag" | sed 's/^v//'
    return 0
  done
  return 1
}

# Версии с сервера в кэш (работает в фоне). Проверяются только установленные
# пакеты: у остальных сравнивать не с чем.
upd_check_bg() {
  local tmp="${UPD_CACHE}.tmp.$$" ver pair
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  : > "$tmp" || return 1
  ver=$(upd_menu_version 2>/dev/null) || ver=""
  [ -n "$ver" ] && printf 'menu %s\n' "$ver" >> "$tmp"
  for pair in \
    nfqws-keenetic:nfqws/nfqws-keenetic \
    nfqws2-keenetic:nfqws/nfqws2-keenetic \
    nfqws-keenetic-web:nfqws/nfqws-keenetic-web
  do
    is_installed "${pair%%:*}" || continue
    ver=$(fetch_pkg_version_file "${pair#*:}" 2>/dev/null) || ver=""
    [ -n "$ver" ] && printf '%s %s\n' "${pair%%:*}" "$ver" >> "$tmp"
  done
  if is_tg_ws_proxy_rs_installed; then
    ver=$(upd_release_tag "valnesfjord/tg-ws-proxy-rs" 2>/dev/null) || ver=""
    [ -n "$ver" ] && printf 'tg-ws-proxy-rs %s\n' "$ver" >> "$tmp"
  fi
  if is_dpi_detector_installed; then
    # все релизы dpi-detector — pre-release; /releases/latest их не видит
    ver=$(upd_release_tag_any "Runnin4ik/dpi-detector" 2>/dev/null) || ver=""
    [ -n "$ver" ] && printf 'dpi-detector %s\n' "$ver" >> "$tmp"
  fi
  if is_awg_manager_installed; then
    ver=$(upd_release_tag "hoaxisr/awg-manager" 2>/dev/null) || ver=""
    [ -n "$ver" ] && printf 'awg-manager %s\n' "$ver" >> "$tmp"
  fi
  # Время проверки пишется всегда: иначе неудачный прогон повторялся бы на
  # каждом входе в меню.
  printf 'checked %s\n' "$(date +%s)" >> "$tmp"
  mv "$tmp" "$UPD_CACHE" 2>/dev/null || { rm -f "$tmp"; return 1; }
  # USR1 только если есть реальные метки — иначе лишний clear меню
  if ! upd_has_pending; then
    return 0
  fi
  if [ -r "/proc/${MENU_PID}/cmdline" ] &&
     tr -d '\0' < "/proc/${MENU_PID}/cmdline" 2>/dev/null | grep -q 'nfqws-menu'
  then
    kill -USR1 "$MENU_PID" 2>/dev/null || true
  fi
  return 0
}

# Кэш моложе TTL — сеть не нужна.
upd_cache_fresh() {
  local checked now
  [ -f "$UPD_CACHE" ] || return 1
  checked=$(sed -n 's/^checked //p' "$UPD_CACHE" 2>/dev/null | head -1)
  case "$checked" in
    ''|*[!0-9]*) return 1 ;;
  esac
  now=$(date +%s)
  [ $((now - checked)) -lt "$UPD_TTL" ]
}

upd_cleanup() {
  [ -n "${UPD_JOB:-}" ] && kill "$UPD_JOB" 2>/dev/null
  rm -f "${UPD_CACHE}.tmp.$$" 2>/dev/null
  return 0
}

# Один раз при входе в меню: подписка на сигнал и, если кэш устарел, фоновый
# процесс. Кэш свежий — метки рисуются сразу, без единого запроса.
upd_start() {
  MENU_PID=$$
  trap 'UPD_REDRAW=1' USR1
  trap 'upd_cleanup' EXIT
  # NFQWS_MENU_UPDATE_BG=0 — без фоновой проверки (без второго кадра)
  case "${NFQWS_MENU_UPDATE_BG:-1}" in
    0|false|FALSE|no|NO) return 0 ;;
  esac
  upd_cache_fresh && return 0
  ( upd_check_bg ) </dev/null >/dev/null 2>&1 &
  UPD_JOB=$!
  return 0
}

# Версия с сервера для ключа (пусто — данных нет).
upd_remote() {
  [ -f "$UPD_CACHE" ] || return 0
  sed -n "s/^$1 //p" "$UPD_CACHE" 2>/dev/null | head -1
}

# Установленная версия для ключа.
upd_local() {
  case "$1" in
    menu)           printf '%s' "$SCRIPT_VERSION" ;;
    tg-ws-proxy-rs) tg_ws_proxy_rs_version 2>/dev/null ;;
    dpi-detector)   dpi_detector_version 2>/dev/null ;;
    awg-manager)    pkg_version "awg-manager" 2>/dev/null ;;
    *)              pkg_version "$1" 2>/dev/null ;;
  esac
  return 0
}

# Сравнение версий a > b (semver-подобно: 1.2.10 > 1.2.9). 0 = да.
ver_gt() {
  local a="$1" b="$2" ia ib n=1
  [ -n "$a" ] && [ -n "$b" ] || return 1
  [ "$a" = "$b" ] && return 1
  while [ $n -le 8 ]; do
    ia="${a%%.*}"; ib="${b%%.*}"
    case "$ia" in ''|*[!0-9]*) ia=0 ;; esac
    case "$ib" in ''|*[!0-9]*) ib=0 ;; esac
    [ "$ia" -gt "$ib" ] 2>/dev/null && return 0
    [ "$ia" -lt "$ib" ] 2>/dev/null && return 1
    [ "$a" = "$ia" ] && a=0 || a="${a#*.}"
    [ "$b" = "$ib" ] && b=0 || b="${b#*.}"
    [ "$a" = "0" ] && [ "$b" = "0" ] && [ $n -gt 1 ] && return 1
    n=$((n + 1))
  done
  return 1
}

# Есть ли хоть одна метка обновления по текущему кэшу.
upd_has_pending() {
  local key rest
  [ -f "$UPD_CACHE" ] || return 1
  while read -r key rest; do
    case "$key" in ''|checked) continue ;; esac
    [ -n "$(upd_mark "$key")" ] && return 0
  done < "$UPD_CACHE"
  return 1
}

# Метка: только если на сервере НОВЕЕ, чем установлено. « ⭡1.2.7».
upd_mark() {
  local remote installed
  remote=$(upd_remote "$1")
  [ -n "$remote" ] || return 0
  installed=$(upd_local "$1")
  [ -n "$installed" ] || return 0
  [ "$remote" = "$installed" ] && return 0
  ver_gt "$remote" "$installed" || return 0
  # стрелка + версия на сервере зелёным
  printf '%s%s%s%s' "$UPD_MARK" "$GREEN" "$remote" "$NC"
  return 0
}

# Подпись к меткам — печатается, только если хоть одна метка есть.
upd_legend() {
  local key rest
  [ -f "$UPD_CACHE" ] || return 0
  while read -r key rest; do
    case "$key" in ''|checked) continue ;; esac
    [ -n "$(upd_mark "$key")" ] || continue
    printf '  %s%s%s\n' "$DIM" "$LBL_UPD_LEGEND" "$NC"
    return 0
  done < "$UPD_CACHE"
  return 0
}

# Чтение выбора с оглядкой на фоновую проверку. READ_RC: 0 — ввод получен,
# 1 — перерисовать (пришла проверка), 2 — stdin закрыт (меню завершается).
# На BusyBox/ash USR1 часто НЕ прерывает блокирующий read — поэтому на TTY
# крутим read -t 1 и сами смотрим UPD_REDRAW (перерисовка без Enter).
read_choice() {
  local _var="$1"
  READ_RC=0
  if [ -t 0 ]; then
    while true; do
      if [ "$UPD_REDRAW" = 1 ]; then
        UPD_REDRAW=0
        READ_RC=1
        return 1
      fi
      # timeout 1 с: 0 = строка введена; иначе таймаут/сигнал → снова цикл
      if read -r -t 1 "$_var" 2>/dev/null; then
        return 0
      fi
      if [ "$UPD_REDRAW" = 1 ]; then
        UPD_REDRAW=0
        READ_RC=1
        return 1
      fi
    done
  fi
  # не TTY (pipe/скрипт): обычный блокирующий read
  if read_menu "$_var"; then
    return 0
  fi
  if [ "$UPD_REDRAW" = 1 ]; then
    UPD_REDRAW=0
    READ_RC=1
    return 1
  fi
  READ_RC=2
  return 1
}

# ---------------------------------------------------------------------------
# Главное меню
# ---------------------------------------------------------------------------
main_menu() {
  upd_start
  while true; do
    clear 2>/dev/null || true
    echo
    printf '%s\n' "${CYAN}========================================${NC}"
    printf '%s\n' "${CYAN}${BOLD}    NFQWS-MENU (Entware)  v${SCRIPT_VERSION}$(upd_mark menu)${NC}"
    printf '%s\n' "${CYAN}========================================${NC}"
    detect_arch
    show_installed
    upd_legend
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_COMPONENTS}${NC}"
    echo "      1.  $LBL_1"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_STRATEGIES}${NC}"
    echo "      2.  $LBL_3"
    echo "      3.  $LBL_4"
    echo "      4.  $LBL_5"
    echo "      5.  $LBL_6"
    echo "      6.  $LBL_7"
    echo "      7.  $LBL_8"
    echo "      8.  $LBL_9"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_UTILS}${NC}"
    echo "      10. dpi-detector"
    echo "      11. awg-manager"
    echo "      12. KeenKit"
    echo "      13. usque-keenetic"
    echo "      14. MagiTrickle"
    echo "      15. telemt / telemt-panel"
    echo "      16. TG WS Proxy Rust"
    echo
    printf '%s\n' "${CYAN}${BOLD}[::]  ${LBL_REMOVE} [${GREEN}S${CYAN}${BOLD}]  |  ${LBL_LANG} [${GREEN}77${CYAN}${BOLD}]${NC}"
    echo "      88. $LBL_88"
    echo "      99. $LBL_99"
    echo "      00. $LBL_00"
    echo
    ask "$LBL_PROMPT"
    if read_choice choice; then
      :   # обычный путь: выбор разбирается ниже
    elif [ "$READ_RC" = 1 ]; then
      continue    # пришла фоновая проверка версий — перерисуем с метками
    else
      exit 1      # stdin закрыт: как и раньше, выходим из меню
    fi

    # || true — при set -e любой return 1 из пункта не должен завершать скрипт
    case "$choice" in
      1)  menu_install_nfqws || true ;;
      2)  menu_strategy || true ;;
      3)  update_ipset_list || true ;;
      4)  update_rkn_list || true ;;
      5)  menu_dot_doh || true ;;
      6)  menu_change_fake_blob || true ;;
      7)  menu_update_hosts || true ;;
      8)  menu_dns_manage || true ;;
      10) menu_dpi_detector || true ;;
      11) menu_awg_manager || true ;;
      12) menu_keenkit || true ;;
      13) menu_usque_keenetic || true ;;
      14) menu_magitrickle || true ;;
      15) menu_telemt || true ;;
      16) menu_tg_ws_proxy_rs || true ;;
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
      *) warn "${LBL_INVALID:-Invalid menu option}" ;;
    esac

    # После внешних установщиков stdin часто «грязный» — чистим перед паузой
    drain_stdin
    echo
    ask "$LBL_BACK"
    if read_choice _; then
      :
    elif [ "$READ_RC" = 1 ]; then
      continue
    else
      exit 1
    fi
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
  # curl -o сбрасывает +x — всегда восстанавливаем, иначе menu → Permission denied
  chmod +x "$target" 2>/dev/null || true
  [ -d /opt/bin ] || mkdir -p /opt/bin 2>/dev/null || return 0
  if [ -L "$link" ]; then
    cur=$(readlink "$link" 2>/dev/null || true)
    [ "$cur" = "$target" ] && return 0
  fi
  [ -e "$link" ] && [ ! -L "$link" ] && return 0
  ln -sf "$target" "$link" 2>/dev/null || true
}

ensure_menu_symlink

if ! command -v opkg >/dev/null 2>&1; then
  error "opkg не найден. Скрипт предназначен для Entware (Keenetic/Netcraze)."
  exit 1
fi

main_menu
