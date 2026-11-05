#!/bin/sh
# installer_warpscout.sh — меню warpscout для Entware (Keenetic / Netcraze)
# Бинарники: https://github.com/rndnaame/warpscout (mipsel + arm)
# Upstream:   https://github.com/vernette/warpscout (arm fallback)
# Обёртка:    https://github.com/rndnaame/nfqws-menu
#
# Версионирование (MAJOR.MINOR.PATCH): при любых правках бампать SCRIPT_VERSION.
#   PATCH — мелкие фиксы; MINOR — новое поведение; MAJOR — ломающие изменения.
#
# 1) Установка / обновление warpscout
# 2) Создать аккаунт (warpscout register)
# 3) Сканирование адресов (AWG → list + conf)
# 4) Автоматический поиск / apply junk (find-junk)
# 5) Применить conf в awg-manager (если установлен)
# 6) Проверка туннеля (curl --interface nwg*/awg*)
# 88) Удаление
#
# Запуск:
#   sh installer_warpscout.sh
#   curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_warpscout.sh | sh

SCRIPT_VERSION="0.1.44"

# ANSI (portable для ash/BusyBox)
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[0;36m')
BLUE=$(printf '\033[0;34m')
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[!]${NC} $*"; }

# короткий вывод длинного I1
show_i1_brief() {
  # без \n — для встраивания в info/printf
  _i1="$1"
  if [ -z "$_i1" ]; then
    printf '%s' "${DIM}(нет)${NC}"
    return
  fi
  _n=${#_i1}
  if [ "$_n" -le 48 ]; then
    printf '%s' "$_i1"
  else
    _head=$(printf '%s' "$_i1" | head -c 40)
    printf '%s… (%s симв.)' "$_head" "$_n"
  fi
}

BIN="/opt/bin/warpscout"
ACCOUNT_FILE="/opt/root/warpscout-account.json"
SCAN_OUT="/opt/root/warpscout-awg.list"
CONF_OUT="/opt/root/warpscout-awg.conf"
JUNK_FILE="/opt/root/warpscout-junk.env"
FIND_JUNK_LOG="/opt/root/warpscout-find-junk.log"
# rndnaame — сборки mipsel + arm; vernette — официальный upstream (arm)
GITHUB_REPO="rndnaame/warpscout"
OFFICIAL_REPO="vernette/warpscout"
# fallback, если GitHub API недоступен
PIN_VERSION="0.16.1"
MIPSEL_BIN_FALLBACK="https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/warpscout/warpscout-0.16.1-mipsle"
WS_VERSION=""
WS_VERSION_SOURCE=""
AWG_SETTINGS="/opt/etc/awg-manager/settings.json"
AWG_API_KEY_FILE="/opt/etc/awg-manager/.api_key"
TMPDIR="/tmp/warpscout-installer-$$"
# свой tmp + чужие от мёртвых PID (обрыв SSH / kill -9 / ^C в родителе)
_cleanup_tmpdir() {
  rm -rf "$TMPDIR" 2>/dev/null || true
}
_cleanup_stale_tmp() {
  for d in /tmp/warpscout-installer-*; do
    [ -d "$d" ] || continue
    # не трогаем свой каталог текущей сессии
    [ "$d" = "$TMPDIR" ] && continue
    pid=${d##*-}
    case "$pid" in
      ''|*[!0-9]*) rm -rf "$d" 2>/dev/null || true; continue ;;
    esac
    # PID жив? kill -0 — без сигнала
    if kill -0 "$pid" 2>/dev/null; then
      continue
    fi
    rm -rf "$d" 2>/dev/null || true
  done
}
trap '_cleanup_tmpdir' EXIT INT TERM HUP
_cleanup_stale_tmp
mkdir -p "$TMPDIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Архитектура
# ---------------------------------------------------------------------------
ARCH=""
ARCH_RAW=""
ARCH_SOURCE=""

_arch_normalize() {
  case "$1" in
    aarch64*|arm64*)             echo "aarch64" ;;
    armv7*|armv6*|arm*)          echo "" ;;
    mipsel*|mipselsf*|mips64el*) echo "mipsel" ;;
    mips*|mipssf*)               echo "mips" ;;
    x86_64*|amd64*|x64*)         echo "x86_64" ;;
    i[3-6]86*|x86*|i686*)        echo "x86" ;;
    *)                           echo "" ;;
  esac
}

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

_arch_from_opkg_conf() {
  conf="${1:-/opt/etc/opkg.conf}"
  [ -f "$conf" ] || return 0
  name=$(grep -E '^[[:space:]]*arch[[:space:]]+' "$conf" 2>/dev/null | _arch_pick_best)
  [ -n "$name" ] && { printf '%s\n' "$name"; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      src/gz*|src\ *)
        case "$line" in
          *mipselsf*|*mips64el*) printf '%s\n' "mipselsf"; return 0 ;;
          *mipssf*)              printf '%s\n' "mipssf"; return 0 ;;
          *aarch64*|*arm64*)     printf '%s\n' "aarch64"; return 0 ;;
        esac
        ;;
    esac
  done < "$conf"
}

detect_arch() {
  ARCH=""
  ARCH_RAW=""
  ARCH_SOURCE=""

  ARCH_RAW=$(_arch_from_opkg)
  ARCH=$(_arch_normalize "$ARCH_RAW")
  [ -n "$ARCH" ] && ARCH_SOURCE="opkg"

  if [ -z "$ARCH" ]; then
    ARCH_RAW=$(_arch_from_opkg_conf /opt/etc/opkg.conf)
    ARCH=$(_arch_normalize "$ARCH_RAW")
    [ -n "$ARCH" ] && ARCH_SOURCE="conf"
  fi

  if [ -z "$ARCH" ]; then
    um=$(uname -m 2>/dev/null)
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
}

need_arch() {
  [ -z "$ARCH" ] && detect_arch
  if [ -z "$ARCH" ]; then
    error "Не удалось определить архитектуру."
    return 1
  fi
  case "$ARCH" in
    aarch64|mipsel)
      return 0
      ;;
    mips)
      error "mips (big-endian) не поддерживается — нужен mipsel-бинарник."
      return 1
      ;;
    *)
      error "Архитектура $ARCH не поддерживается (нужны aarch64 / mipsel)."
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# HTTP / зеркала
# ---------------------------------------------------------------------------
github_alt_urls() {
  url="$1"
  case "$url" in
    https://github.com/*/releases/download/*)
      printf '%s\n' "$url"
      printf '%s\n' "https://ghproxy.net/${url}"
      printf '%s\n' "https://mirror.ghproxy.com/${url}"
      printf '%s\n' "https://ghfast.top/${url}"
      printf '%s\n' "https://gh-proxy.com/${url}"
      printf '%s\n' "https://gh.ddlc.top/${url}"
      printf '%s\n' "https://gitproxy.click/${url}"
      ;;
    https://raw.githubusercontent.com/*)
      rest="${url#https://raw.githubusercontent.com/}"
      owner="${rest%%/*}"; rest="${rest#*/}"
      repo="${rest%%/*}"; rest="${rest#*/}"
      ref="${rest%%/*}"; path_rest="${rest#*/}"
      printf '%s\n' "$url"
      if [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$ref" ]; then
        printf '%s\n' "https://fastly.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path_rest}"
        printf '%s\n' "https://cdn.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path_rest}"
      fi
      printf '%s\n' "https://ghproxy.net/${url}"
      ;;
    *)
      printf '%s\n' "$url"
      ;;
  esac
}

_http_get_one() {
  u="$1"
  d="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 5 --max-time 40 "$u" -o "$d" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$d" -T 40 "$u" 2>/dev/null
  else
    return 1
  fi
}

http_get() {
  # http_get URL DEST [quiet]
  url="$1"
  dest="$2"
  quiet="${3:-}"
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    error "Нужны curl или wget."
    return 1
  fi
  rm -f "$dest"
  n=0
  for alt in $(github_alt_urls "$url"); do
    [ -n "$alt" ] || continue
    n=$((n + 1))
    if [ -z "$quiet" ]; then
      info "Пробуем [$n]: $alt"
    fi
    if _http_get_one "$alt" "$dest" && [ -s "$dest" ]; then
      if [ -z "$quiet" ] && [ "$alt" != "$url" ]; then
        info "Скачано через зеркало"
      fi
      return 0
    fi
  done
  return 1
}

# tag_name latest release (с «v» или без)
_fetch_tag_name() {
  repo="$1"
  api="https://api.github.com/repos/${repo}/releases/latest"
  body=""
  if command -v curl >/dev/null 2>&1; then
    body=$(curl -fsS --connect-timeout 3 --max-time 8 \
      -H "Accept: application/vnd.github+json" "$api" 2>/dev/null) || body=""
    if [ -z "$body" ]; then
      body=$(curl -fsS --connect-timeout 3 --max-time 8 \
        -H "Accept: application/vnd.github+json" \
        "https://ghproxy.net/${api}" 2>/dev/null) || body=""
    fi
  fi
  [ -n "$body" ] || return 1
  # первое tag_name в JSON latest
  printf '%s' "$body" | tr ',' '\n' | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# WS_VERSION / WS_VERSION_SOURCE: api → pin 0.16.1
resolve_release_version() {
  WS_VERSION=""
  WS_VERSION_SOURCE=""
  tag=$(_fetch_tag_name "$GITHUB_REPO" 2>/dev/null) || tag=""
  if [ -n "$tag" ]; then
    WS_VERSION=$(printf '%s' "$tag" | sed 's/^[vV]//')
    WS_VERSION_SOURCE="api"
  fi
  case "$WS_VERSION" in
    [0-9]*.[0-9]*) ;;
    *)
      WS_VERSION="$PIN_VERSION"
      WS_VERSION_SOURCE="pin"
      ;;
  esac
}

# https://github.com/REPO/releases/download/vVER/warpscout_VER_SUFFIX.tar.gz
release_asset_url() {
  printf 'https://github.com/%s/releases/download/v%s/warpscout_%s_%s.tar.gz' \
    "$1" "$2" "$2" "$3"
}

# Скачать tar.gz и найти bin warpscout → INSTALL_SRC
install_from_tarball() {
  url="$1"
  label="$2"
  archive="$TMPDIR/warpscout.tar.gz"
  INSTALL_SRC=""
  rm -f "$archive" "$TMPDIR/warpscout" 2>/dev/null || true
  info "$label"
  if ! http_get "$url" "$archive"; then
    return 1
  fi
  sz=$(wc -c < "$archive" 2>/dev/null | tr -d ' ')
  case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
  if [ "$sz" -lt 100000 ]; then
    warn "Архив слишком маленький (${sz} байт)."
    return 1
  fi
  info "Распаковка (${sz} байт)..."
  if ! tar -xzf "$archive" -C "$TMPDIR" 2>/dev/null; then
    warn "Не удалось распаковать архив."
    return 1
  fi
  if [ -f "$TMPDIR/warpscout" ]; then
    INSTALL_SRC="$TMPDIR/warpscout"
  else
    INSTALL_SRC=$(find "$TMPDIR" -type f -name 'warpscout' 2>/dev/null | head -1)
  fi
  if [ -z "$INSTALL_SRC" ] || [ ! -f "$INSTALL_SRC" ]; then
    warn "В архиве не найден бинарник warpscout."
    INSTALL_SRC=""
    return 1
  fi
  return 0
}


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
read_choice() {
  if [ -c /dev/tty ]; then
    read -r choice < /dev/tty
  else
    read -r choice
  fi
  printf '%s' "$choice"
}

confirm_yes() {
  printf '%s' "${YELLOW}[?]${NC} $1 [y/N]: "
  c=$(read_choice)
  case "$c" in
    y|Y|yes|YES|д|Д|да|Да) return 0 ;;
    *) return 1 ;;
  esac
}

# Да по умолчанию [Y/n]
confirm_Y() {
  printf '%s' "${YELLOW}[?]${NC} $1 [Y/n]: "
  c=$(read_choice)
  case "$c" in
    n|N|no|NO|н|Н|нет|Нет) return 1 ;;
    *) return 0 ;;
  esac
}

pause() {
  printf '%s' "Нажмите Enter..."
  if [ -c /dev/tty ]; then
    read -r _ < /dev/tty
  else
    read -r _
  fi
}

ensure_tmpdir() {
  mkdir -p "$TMPDIR" 2>/dev/null || true
}

# Строка меню туннеля (статус в конце, endpoint cyan)
# print_tunnel_menu_line N KEY STATUS NAME [ADDR] [ENDPOINT] [GLOBAL]
print_tunnel_menu_line() {
  _n="$1"
  _key="$2"
  _st="${3:-?}"
  _name="${4:-}"
  _addr="${5:-}"
  _ep="${6:-}"
  _glob="${7:-false}"
  if [ "$_glob" = "true" ]; then
    _ncol="$GREEN"
  else
    _ncol="$DIM"
  fi
  printf '  %s%d)%s  %-8s' "$BOLD" "$_n" "$NC" "$_key"
  if [ -n "$_name" ] && [ "$_name" != "$_key" ]; then
    printf ' · %s%s%s' "$_ncol" "$_name" "$NC"
  fi
  [ -n "$_addr" ] && printf ' · %s' "$_addr"
  [ -n "$_ep" ] && printf ' · %s%s%s' "$CYAN" "$_ep" "$NC"
  printf '  %s[%s]%s\n' "$DIM" "$_st" "$NC"
}


is_installed() {
  [ -x "$BIN" ]
}

installed_version() {
  if [ -x "$BIN" ]; then
    v=$("$BIN" version 2>/dev/null | head -1)
    if [ -n "$v" ]; then
      printf '%s\n' "$v" | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p'
      return 0
    fi
  fi
  return 1
}

has_account() {
  [ -f "$ACCOUNT_FILE" ] && [ -s "$ACCOUNT_FILE" ]
}

has_conf() {
  [ -f "$CONF_OUT" ] && [ -s "$CONF_OUT" ]
}

is_awg_manager_installed() {
  if opkg list-installed 2>/dev/null | grep -q '^awg-manager '; then
    return 0
  fi
  [ -d /opt/etc/awg-manager ]
}

show_status() {
  st=""
  if is_installed; then
    ver=$(installed_version 2>/dev/null) || ver=""
    st="bin ${ver:-ok}"
  fi
  if has_account; then
    st="${st:+$st, }аккаунт ✓"
  else
    st="${st:+$st, }аккаунт ✗"
  fi
  if [ -f "$SCAN_OUT" ] && [ -s "$SCAN_OUT" ]; then
    n=$(wc -l < "$SCAN_OUT" 2>/dev/null | tr -d ' ')
    st="${st:+$st, }list ${n:-?} строк"
  fi
  if has_conf; then
    st="${st:+$st, }conf ✓"
  fi
  if [ -f "$JUNK_FILE" ] && [ -s "$JUNK_FILE" ]; then
    st="${st:+$st, }junk ✓"
  fi
  if is_awg_manager_installed; then
    st="${st:+$st, }awg-manager ✓"
  fi
  if [ -n "$st" ]; then
    info "Обнаружено: $st"
  else
    printf '%s\n' "${DIM}Не установлено${NC}"
  fi
}

# ---------------------------------------------------------------------------
# 1) Установка / обновление
# ---------------------------------------------------------------------------
do_install() {
  echo
  info "Установка / обновление warpscout"
  need_arch || return 1

  mkdir -p /opt/bin /opt/root "$TMPDIR" 2>/dev/null || true

  resolve_release_version
  info "Версия: v${WS_VERSION} (${WS_VERSION_SOURCE})"

  src=""
  case "$ARCH" in
    aarch64)
      info "Архитектура: aarch64"
      url=$(release_asset_url "$GITHUB_REPO" "$WS_VERSION" "linux_arm64")
      if install_from_tarball "$url" "${GITHUB_REPO} · linux_arm64"; then
        src="$INSTALL_SRC"
      else
        url=$(release_asset_url "$OFFICIAL_REPO" "$WS_VERSION" "linux_arm64")
        warn "Fallback upstream ${OFFICIAL_REPO}..."
        if install_from_tarball "$url" "${OFFICIAL_REPO} · linux_arm64"; then
          src="$INSTALL_SRC"
        elif [ "$WS_VERSION" != "$PIN_VERSION" ]; then
          url=$(release_asset_url "$OFFICIAL_REPO" "$PIN_VERSION" "linux_arm64")
          if install_from_tarball "$url" "${OFFICIAL_REPO} · pin v${PIN_VERSION}"; then
            src="$INSTALL_SRC"
          fi
        fi
      fi
      ;;
    mipsel)
      info "Архитектура: mipsel"
      url=$(release_asset_url "$GITHUB_REPO" "$WS_VERSION" "linux_mipsle")
      if install_from_tarball "$url" "${GITHUB_REPO} · linux_mipsle"; then
        src="$INSTALL_SRC"
      elif [ "$WS_VERSION" != "$PIN_VERSION" ]; then
        url=$(release_asset_url "$GITHUB_REPO" "$PIN_VERSION" "linux_mipsle")
        if install_from_tarball "$url" "${GITHUB_REPO} · pin v${PIN_VERSION}"; then
          src="$INSTALL_SRC"
        fi
      fi
      if [ -z "$src" ] || [ ! -f "$src" ]; then
        warn "Release недоступен — raw mipsel-bin..."
        src="$TMPDIR/warpscout"
        if ! http_get "$MIPSEL_BIN_FALLBACK" "$src"; then
          error "Не удалось скачать mipsel."
          return 1
        fi
        sz=$(wc -c < "$src" 2>/dev/null | tr -d ' ')
        case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
        if [ "$sz" -lt 100000 ]; then
          error "Файл слишком маленький (${sz} байт)."
          return 1
        fi
      fi
      ;;
    *)
      error "Неподдерживаемая ARCH=$ARCH"
      return 1
      ;;
  esac

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    error "Бинарник не получен."
    return 1
  fi

  if ! cp -f "$src" "$BIN"; then
    error "Не удалось скопировать в $BIN"
    return 1
  fi
  chmod +x "$BIN" 2>/dev/null || true

  ver=$(installed_version 2>/dev/null) || ver=""
  info "Установлено: $BIN ${ver:+(v$ver)}"
  printf '%s\n' "${DIM}Релиз: v${WS_VERSION} (${WS_VERSION_SOURCE}) · ${GITHUB_REPO}${NC}"
  return 0
}

# ---------------------------------------------------------------------------
# 2) Создать аккаунт
# ---------------------------------------------------------------------------
do_register() {
  echo
  info "Создание аккаунта WARP (warpscout register)"
  if ! is_installed; then
    error "warpscout не установлен. Сначала пункт 1."
    return 1
  fi

  mkdir -p /opt/root 2>/dev/null || true

  if has_account; then
    warn "Файл аккаунта уже есть: $ACCOUNT_FILE"
    if ! confirm_yes "Пересоздать аккаунт?"; then
      info "Отменено."
      return 0
    fi
    rm -f "$ACCOUNT_FILE" 2>/dev/null || true
  fi

  cd /opt/root || cd /tmp || true
  if ! "$BIN" register; then
    error "register завершился с ошибкой."
    warn "При блокировке api.cloudflareclient.com см. документацию warpscout (account)."
    return 1
  fi

  if [ ! -f "$ACCOUNT_FILE" ]; then
    for cand in \
      ./warpscout-account.json \
      /tmp/warpscout-account.json \
      "$(dirname "$BIN")/warpscout-account.json"
    do
      if [ -f "$cand" ]; then
        mv -f "$cand" "$ACCOUNT_FILE" 2>/dev/null || cp -f "$cand" "$ACCOUNT_FILE"
        break
      fi
    done
  fi

  if has_account; then
    info "Аккаунт сохранён: $ACCOUNT_FILE"
    return 0
  fi
  error "Файл аккаунта не найден после register."
  return 1
}


# Загрузить найденные junk-параметры (JC JMIN JMAX I1)
load_junk_params() {
  JC=""; JMIN=""; JMAX=""; I1=""
  [ -f "$JUNK_FILE" ] && [ -s "$JUNK_FILE" ] || return 1
  # shellcheck: файл пишем сами
  # JC=6 etc.
  JC=$(sed -n 's/^JC=//p' "$JUNK_FILE" | head -1)
  JMIN=$(sed -n 's/^JMIN=//p' "$JUNK_FILE" | head -1)
  JMAX=$(sed -n 's/^JMAX=//p' "$JUNK_FILE" | head -1)
  # I1 может содержать пробелы и <> — храним как I1=... одной строкой
  I1=$(sed -n 's/^I1=//p' "$JUNK_FILE" | head -1)
  [ -n "$JC" ] || [ -n "$I1" ]
}

save_junk_params() {
  # save_junk_params jc jmin jmax i1
  mkdir -p /opt/root 2>/dev/null || true
  {
    printf 'JC=%s\n' "$1"
    printf 'JMIN=%s\n' "$2"
    printf 'JMAX=%s\n' "$3"
    printf 'I1=%s\n' "$4"
  } > "$JUNK_FILE"
  info "Параметры сохранены: $JUNK_FILE"
  info "  -jc $1 -jmin $2 -jmax $3"
  [ -n "$4" ] && info "  -i1 $(show_i1_brief "$4")"
}

# Разобрать лог find-junk → JC JMIN JMAX I1
parse_find_junk_log() {
  # Лучший Attempt по N/M working; либо Good enough / scan -jc
  logf="$1"
  [ -f "$logf" ] || return 1
  JC=""; JMIN=""; JMAX=""; I1=""

  # 1) готовая команда scan / Good enough
  line=$(grep -E 'scan .*(-jc|--jc)|Good enough:.*jc=' "$logf" 2>/dev/null | tail -1)
  if [ -n "$line" ]; then
    JC=$(printf '%s\n' "$line" | sed -n 's/.*-jc[[:space:]]\+\([0-9][0-9]*\).*/\1/p;s/.*jc=\([0-9][0-9]*\).*/\1/p' | head -1)
    JMIN=$(printf '%s\n' "$line" | sed -n 's/.*-jmin[[:space:]]\+\([0-9][0-9]*\).*/\1/p;s/.*jmin=\([0-9][0-9]*\).*/\1/p' | head -1)
    JMAX=$(printf '%s\n' "$line" | sed -n 's/.*-jmax[[:space:]]\+\([0-9][0-9]*\).*/\1/p;s/.*jmax=\([0-9][0-9]*\).*/\1/p' | head -1)
    I1=$(printf '%s\n' "$line" | sed -n 's/.*-i1[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -z "$I1" ] && I1=$(printf '%s\n' "$line" | sed -n "s/.*-i1[[:space:]]*'\\([^']*\\)'.*/\\1/p" | head -1)
  fi

  # 2) иначе — Attempt с максимальным N в «N/M working»
  if [ -z "$JC" ]; then
    best_n=-1
    best_line=""
    while IFS= read -r al || [ -n "$al" ]; do
      case "$al" in
        *"Attempt "*"jc="*) ;;
        *) continue ;;
      esac
      n=$(printf '%s\n' "$al" | sed -n 's/.*[[:space:]]\([0-9][0-9]*\)\/[0-9][0-9]*[[:space:]]*working.*/\1/p' | head -1)
      case "$n" in ''|*[!0-9]*) n=0 ;; esac
      if [ "$n" -gt "$best_n" ]; then
        best_n=$n
        best_line=$al
      fi
    done <<EOF
$(grep -E 'Attempt [0-9]+:[[:space:]]*jc=' "$logf" 2>/dev/null)
EOF
    if [ -n "$best_line" ] && [ "$best_n" -ge 0 ]; then
      line=$best_line
      JC=$(printf '%s\n' "$line" | sed -n 's/.*jc=\([0-9][0-9]*\).*/\1/p' | head -1)
      JMIN=$(printf '%s\n' "$line" | sed -n 's/.*jmin=\([0-9][0-9]*\).*/\1/p' | head -1)
      JMAX=$(printf '%s\n' "$line" | sed -n 's/.*jmax=\([0-9][0-9]*\).*/\1/p' | head -1)
      # score в подсказку
      FIND_JUNK_SCORE="${best_n}"
    fi
  fi

  # i1 из Ready-to-run, если ещё нет
  if [ -z "$I1" ]; then
    I1=$(grep -E 'Ready-to-run scan|-i1 "' "$logf" 2>/dev/null | tail -1 | \
      sed -n 's/.*-i1[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  fi

  [ -n "$JC" ] || return 1
  return 0
}



# Прописать Jc/Jmin/Jmax/I1 в conf (секция [Interface])
patch_conf_junk() {
  conf="$1"
  [ -f "$conf" ] || return 1
  load_junk_params || return 1

  tmp="$conf.junknew"
  # awk: обновляет или добавляет ключи в [Interface]
  awk -v jc="$JC" -v jmin="$JMIN" -v jmax="$JMAX" -v i1="$I1" '
    BEGIN {
      inif=0
      seen_jc=0; seen_jmin=0; seen_jmax=0; seen_i1=0
    }
    function flush_missing() {
      if (jc != "" && !seen_jc)   print "Jc = " jc
      if (jmin != "" && !seen_jmin) print "Jmin = " jmin
      if (jmax != "" && !seen_jmax) print "Jmax = " jmax
      if (i1 != "" && !seen_i1)   print "I1 = " i1
      seen_jc=1; seen_jmin=1; seen_jmax=1; seen_i1=1
    }
    /^\[Interface\]/ { inif=1; print; next }
    /^\[/ {
      if (inif) { flush_missing(); inif=0 }
      print; next
    }
    inif && /^[[:space:]]*[Jj][Cc][[:space:]]*=/ {
      if (jc != "") { print "Jc = " jc; seen_jc=1; next }
    }
    inif && /^[[:space:]]*[Jj][Mm][Ii][Nn][[:space:]]*=/ {
      if (jmin != "") { print "Jmin = " jmin; seen_jmin=1; next }
    }
    inif && /^[[:space:]]*[Jj][Mm][Aa][Xx][[:space:]]*=/ {
      if (jmax != "") { print "Jmax = " jmax; seen_jmax=1; next }
    }
    inif && /^[[:space:]]*[Ii]1[[:space:]]*=/ {
      if (i1 != "") { print "I1 = " i1; seen_i1=1; next }
    }
    { print }
    END {
      if (inif) flush_missing()
      else if (!seen_jc && !seen_jmin && !seen_jmax && !seen_i1 && (jc!=""||jmin!=""||jmax!=""||i1!="")) {
        print "[Interface]"
        flush_missing()
      }
    }
  ' "$conf" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$conf" || return 1
  info "В $conf записаны junk-параметры:"
  [ -n "$JC" ] && info "  Jc = $JC"
  [ -n "$JMIN" ] && info "  Jmin = $JMIN"
  [ -n "$JMAX" ] && info "  Jmax = $JMAX"
  [ -n "$I1" ] && info "  I1 = $(show_i1_brief "$I1")"
  return 0
}

# Replace conf в выбранный туннель awg-manager (без смены endpoint/имени)
awg_replace_conf_file() {
  conf="$1"
  [ -f "$conf" ] || { error "Нет conf: $conf"; return 1; }
  if ! is_awg_manager_installed; then
    error "awg-manager не установлен."
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    error "Нужен curl."
    return 1
  fi
  base=$(awg_api_base)
  if ! awg_load_api_key; then
    error "API-ключ не задан."
    return 1
  fi
  key="$AWG_KEY"
  listf="$TMPDIR/awg-tunnels-junk.txt"
  mkdir -p "$TMPDIR" 2>/dev/null || true
  info "Запрос списка туннелей..."
  if ! awg_list_tunnels "$base" "$key" "$listf"; then
    error "Нет туннелей."
    return 1
  fi

  echo
  printf '%s\n' "${BOLD}Туннель для apply junk:${NC}"
  i=0
  while IFS='|' read -r tid tname tstat tend taddr tifc tndms || [ -n "$tid" ]; do
    [ -n "$tid" ] || continue
    i=$((i + 1))
    print_tunnel_menu_line "$i" "$tid" "${tstat:-?}" "$tname" "$taddr" "$tend" "true"
  done < "$listf"
  echo "  0) Отмена"
  echo
  printf '  %sВыбор:%s ' "$BOLD" "$NC"
  sel=$(read_choice)
  echo
  case "$sel" in
    0|"") info "Отменено."; return 0 ;;
    *[!0-9]*) warn "Неверный выбор."; return 1 ;;
  esac
  if [ "$sel" -lt 1 ] || [ "$sel" -gt "$i" ]; then
    warn "Неверный номер."; return 1
  fi
  tid=$(sed -n "${sel}p" "$listf" | cut -d'|' -f1)
  tname=$(sed -n "${sel}p" "$listf" | cut -d'|' -f2)
  tend=$(sed -n "${sel}p" "$listf" | cut -d'|' -f4)
  [ -n "$tid" ] || { error "Пустой id."; return 1; }

  # Только junk (Jc/Jmin/Jmax/I1): сервер/endpoint туннеля не трогаем
  if [ -n "$tend" ]; then
    info "Endpoint туннеля оставляем: $tend"
    tmp_ep="$TMPDIR/junk-ep.conf"
    if awg_patch_conf_endpoint "$conf" "$tmp_ep" "$tend"; then
      mv -f "$tmp_ep" "$conf" 2>/dev/null || cp -f "$tmp_ep" "$conf"
    else
      warn "Не удалось зафиксировать Endpoint в conf — продолжаем."
    fi
  else
    warn "Endpoint туннеля неизвестен — в conf может уйти Endpoint из scan."
  fi

  # Address: текущий у туннеля, смена только при конфликте с другими
  if ! awg_ensure_free_address "$conf" "$listf" "$tid"; then
    return 1
  fi

  info "Остановка $tid..."
  awg_control stop "$tid" "$key" "$base" || true

  bodyf="$TMPDIR/awg-junk-replace.json"
  {
    printf '{"content":"'
    tr -d '\r' < "$conf" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\t/\\t/g' | awk '{printf "%s\\n",$0}'
    printf '"}'
  } > "$bodyf"

  info "POST ${base}/tunnels/replace?id=${tid}  (junk → «${tname}»)"
  resp=$(curl -sS --connect-timeout 5 --max-time 30 \
    -X POST "${base}/tunnels/replace?id=${tid}" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -d @"$bodyf" 2>/dev/null) || resp=""
  if ! printf '%s' "$resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
    error "replace не удался."
    [ -n "$resp" ] && printf '%s\n' "$resp"
    return 1
  fi
  info "Конфиг туннеля $tid обновлён (junk)."
  sleep 1
  info "Запуск $tid..."
  if ! awg_control start "$tid" "$key" "$base"; then
    awg_control restart "$tid" "$key" "$base" || true
  fi
  return 0
}

# Применить сохранённый junk к conf и/или туннелю
do_apply_junk() {
  echo
  info "Применение junk-параметров"
  if ! load_junk_params; then
    error "Нет $JUNK_FILE — сначала п.4 find-junk."
    return 1
  fi
  info "Текущие: jc=${JC:-?} jmin=${JMIN:-?} jmax=${JMAX:-?}"
  [ -n "$I1" ] && info "  i1 = $(show_i1_brief "$I1")"

  echo
  printf '%s\n' "${BOLD}Куда применить:${NC}"
  echo "  1) Только conf ($CONF_OUT)"
  if is_awg_manager_installed; then
    echo "  2) conf + replace в туннель awg-manager"
  else
    printf '  %s2) conf + replace в туннель%s  %s(нужен awg-manager)%s\n' "$DIM" "$NC" "$DIM" "$NC"
  fi
  echo "  0) Отмена"
  echo
  printf '  %sВыбор:%s ' "$BOLD" "$NC"
  sel=$(read_choice)
  echo
  case "$sel" in
    0|"") info "Отменено."; return 0 ;;
    1)
      if ! has_conf; then
        error "Нет conf: $CONF_OUT (сначала п.3 scan)."
        return 1
      fi
      patch_conf_junk "$CONF_OUT" || return 1
      return 0
      ;;
    2)
      if ! is_awg_manager_installed; then
        error "awg-manager не установлен."
        return 1
      fi
      if ! has_conf; then
        error "Нет conf: $CONF_OUT (сначала п.3 scan)."
        return 1
      fi
      patch_conf_junk "$CONF_OUT" || return 1
      awg_replace_conf_file "$CONF_OUT" || return 1
      return 0
      ;;
    *) warn "Неверный выбор."; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Junk из туннеля awg-manager (Jc/Jmin/Jmax/I1 из API)
# ---------------------------------------------------------------------------
do_junk_from_tunnel() {
  echo
  info "Junk-параметры из туннеля awg-manager"
  if ! is_awg_manager_installed; then
    error "awg-manager не установлен."
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    error "Нужен curl."
    return 1
  fi
  if ! awg_load_api_key; then
    error "Нет API-ключа awg-manager."
    return 1
  fi
  base=$(awg_api_base)
  ensure_tmpdir

  # 1) список туннелей (list — без jc; детали подтянем после выбора)
  listf="$TMPDIR/junk-tun-list.txt"
  if ! awg_list_tunnels "$base" "$AWG_KEY" "$listf" 2>/dev/null || [ ! -s "$listf" ]; then
    error "Не удалось получить список туннелей."
    return 1
  fi

  echo
  printf '%s\n' "${BOLD}Туннели awg-manager:${NC}"
  n=0
  while IFS='|' read -r tid tname tstat tend taddr tifc _tndms || [ -n "$tid" ]; do
    [ -n "$tid" ] || continue
    n=$((n + 1))
    # key=id, show ifc in name area if useful
    _label="$tname"
    [ -n "$tifc" ] && [ "$tifc" != "$tname" ] && _label="${tname} · ${tifc}"
    print_tunnel_menu_line "$n" "$tid" "${tstat:-?}" "$_label" "$taddr" "$tend" "true"
  done < "$listf"
  echo "  0) Отмена"
  echo
  printf '  %sВыбор:%s ' "$BOLD" "$NC"
  sel=$(read_choice)
  echo
  case "$sel" in
    0|"") info "Отменено."; return 0 ;;
    *[!0-9]*) warn "Неверный выбор."; return 1 ;;
  esac
  if [ "$sel" -lt 1 ] || [ "$sel" -gt "$n" ]; then
    warn "Неверный номер."
    return 1
  fi
  line=$(sed -n "${sel}p" "$listf")
  tid=$(printf '%s' "$line" | cut -d'|' -f1)
  tname=$(printf '%s' "$line" | cut -d'|' -f2)
  [ -n "$tid" ] || { error "Пустой id."; return 1; }

  # 2) детали: локальный json → API detail/export
  body=""
  localf="/opt/etc/awg-manager/tunnels/${tid}.json"
  if [ -f "$localf" ]; then
    body=$(cat "$localf" 2>/dev/null) || body=""
    [ -n "$body" ] && info "Источник: $localf"
  fi
  if [ -z "$body" ]; then
    for path in \
      "tunnels/${tid}" \
      "tunnels/get?id=${tid}" \
      "tunnels?id=${tid}" \
      "export/conf?id=${tid}" \
      "tunnels/export?id=${tid}"
    do
      body=$(curl -sS --connect-timeout 3 --max-time 8 \
        -H "Authorization: Bearer ${AWG_KEY}" \
        "${base}/${path}" 2>/dev/null) || body=""
      case "$body" in
        *'"jc"'*|*"Jc = "*|*"jc":*)
          info "Источник: ${base}/${path}"
          break
          ;;
        *) body="" ;;
      esac
    done
  fi
  if [ -z "$body" ]; then
    error "Не удалось прочитать конфиг туннеля $tid (нет jc в list; json/API пусты)."
    return 1
  fi

  # 3) разобрать Jc/Jmin/Jmax/I1 (JSON или wireguard conf)
  JC=$(printf '%s' "$body" | sed -n 's/.*"jc"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p;s/.*[Jj]c[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
  JMIN=$(printf '%s' "$body" | sed -n 's/.*"jmin"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p;s/.*[Jj]min[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
  JMAX=$(printf '%s' "$body" | sed -n 's/.*"jmax"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p;s/.*[Jj]max[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
  I1=$(printf '%s' "$body" | sed -n 's/.*"i1"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p;s/.*[Ii]1[[:space:]]*=[[:space:]]*\(.*\)/\1/p' | head -1)
  I1=$(printf '%s' "$I1" | sed 's/\r$//;s/[[:space:]]*$//')

  if [ -z "$JC" ]; then
    error "В конфиге $tid нет Jc."
    return 1
  fi

  save_junk_params "$JC" "$JMIN" "$JMAX" "$I1"
  info "Из «${tname}» ($tid): jc=$JC jmin=${JMIN:-?} jmax=${JMAX:-?}"
  [ -n "$I1" ] && info "i1: ${#I1} символов" || warn "i1 пуст"
  echo
  if confirm_Y "Применить к conf / туннелю сейчас?"; then
    do_apply_junk || true
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 4) Автоматический поиск junk (find-junk) + apply к conf/туннелю
# ---------------------------------------------------------------------------
do_find_junk() {
  echo
  info "Автоматический поиск junk-параметров (find-junk)"
  if ! is_installed; then
    error "warpscout не установлен. Сначала пункт 1."
    return 1
  fi
  if ! has_account; then
    error "Нет аккаунта. Сначала пункт 2 (register)."
    return 1
  fi

  if load_junk_params; then
    echo
    info "Уже есть junk: jc=${JC:-?} jmin=${JMIN:-?} jmax=${JMAX:-?}"
    echo "  1) Искать заново (find-junk)"
    echo "  2) Применить сохранённые к conf / туннелю"
    if is_awg_manager_installed; then
      echo "  3) Взять из туннеля awg-manager"
    fi
    echo "  0) Отмена"
    echo
    printf '  %sВыбор:%s ' "$BOLD" "$NC"
    pre=$(read_choice)
    echo
    case "$pre" in
      0|"") info "Отменено."; return 0 ;;
      2) do_apply_junk; return $? ;;
      3) do_junk_from_tunnel; return $? ;;
      *) ;; # искать
    esac
  else
    # нет сохранённых — можно сразу взять из туннеля
    if is_awg_manager_installed; then
      echo
      echo "  1) Искать (find-junk)"
      echo "  3) Взять из туннеля awg-manager"
      echo "  0) Отмена"
      echo
      printf '  %sВыбор:%s ' "$BOLD" "$NC"
      pre=$(read_choice)
      echo
      case "$pre" in
        0|"") info "Отменено."; return 0 ;;
        3) do_junk_from_tunnel; return $? ;;
        *) ;; # искать
      esac
    fi
  fi

  echo
  printf '%s\n' "${BOLD}-gen-i1 профиль:${NC}"
  echo "  1) random  (по умолчанию)"
  echo "  2) quic"
  echo "  3) dns"
  echo "  4) sip"
  echo "  5) stun"
  echo "  0) Отмена"
  echo
  printf '  %sВыбор:%s ' "$BOLD" "$NC"
  sel=$(read_choice)
  echo
  case "$sel" in
    0) info "Отменено."; return 0 ;;
    2) gen_i1="quic" ;;
    3) gen_i1="dns" ;;
    4) gen_i1="sip" ;;
    5) gen_i1="stun" ;;
    *) gen_i1="random" ;;
  esac

  mkdir -p /opt/root "$TMPDIR" 2>/dev/null || true
  cd /opt/root || true
  # лог вне TMPDIR — переживает Ctrl+C / trap cleanup
  logf="$FIND_JUNK_LOG"
  : > "$logf"

  info "Команда: warpscout find-junk -gen-i1 $gen_i1"
  info "Долго. Ctrl+C — остановить и взять лучший Attempt из лога."
  printf '%s\n' "${DIM}Лог: $logf${NC}"
  echo

  # на время поиска не сносим tmp/лог по INT (только помечаем)
  FIND_JUNK_INT=0
  _find_junk_on_int() { FIND_JUNK_INT=1; }
  trap '_find_junk_on_int' INT
  rc=0
  if command -v tee >/dev/null 2>&1; then
    "$BIN" find-junk -gen-i1 "$gen_i1" 2>&1 | tee "$logf"
    rc=$?
  else
    "$BIN" find-junk -gen-i1 "$gen_i1" >"$logf" 2>&1
    rc=$?
    cat "$logf" 2>/dev/null || true
  fi
  # вернуть общий trap
  trap '_cleanup_tmpdir' EXIT INT TERM HUP
  echo

  FIND_JUNK_SCORE=""
  if parse_find_junk_log "$logf"; then
    save_junk_params "$JC" "$JMIN" "$JMAX" "$I1"
    if [ -n "$FIND_JUNK_SCORE" ]; then
      if [ "$FIND_JUNK_SCORE" -eq 0 ] 2>/dev/null; then
        warn "Лучший Attempt: 0 working — набор слабый (jc=$JC jmin=$JMIN jmax=$JMAX)."
        warn "Лучше п.3 «из туннеля» или продолжить поиск."
      else
        info "Лучший набор из лога: jc=$JC jmin=$JMIN jmax=$JMAX (${FIND_JUNK_SCORE} working)"
      fi
    else
      info "Параметры: jc=$JC jmin=$JMIN jmax=$JMAX"
    fi
    [ -n "$I1" ] && info "i1 сохранён (${#I1} символов)" || warn "i1 в логе нет (прервано до Ready-to-run) — jc/jmin/jmax всё равно сохранены"
    info "П.3 (scan) подхватит параметры автоматически."
    echo
    if confirm_Y "Применить junk к conf / туннелю сейчас?"; then
      do_apply_junk || true
    fi
  else
    warn "Не удалось разобрать jc/jmin/jmax из вывода find-junk."
    [ -f "$logf" ] && printf '%s\n' "${DIM}Лог: $logf${NC}"
    if [ "$FIND_JUNK_INT" -eq 1 ] || [ "$rc" -ne 0 ]; then
      return 1
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 3) Сканирование AWG (+ готовый conf)
# ---------------------------------------------------------------------------
do_scan() {
  echo
  info "Сканирование адресов (протокол AWG)"
  if ! is_installed; then
    error "warpscout не установлен. Сначала пункт 1."
    return 1
  fi
  if ! has_account; then
    error "Нет аккаунта. Сначала пункт 2 (register)."
    return 1
  fi

  mkdir -p /opt/root 2>/dev/null || true
  cd /opt/root || true

  set -- scan -p awg -P -o "$SCAN_OUT" -conf "$CONF_OUT"
  if load_junk_params; then
    info "Используем junk из $JUNK_FILE: jc=$JC jmin=$JMIN jmax=$JMAX"
    [ -n "$JC" ] && set -- "$@" -jc "$JC"
    [ -n "$JMIN" ] && set -- "$@" -jmin "$JMIN"
    [ -n "$JMAX" ] && set -- "$@" -jmax "$JMAX"
    [ -n "$I1" ] && set -- "$@" -i1 "$I1"
  else
    info "Junk-параметры не заданы (п.4 find-junk) — дефолты warpscout."
  fi

  info "Команда: warpscout $*"
  info "Это может занять несколько минут..."
  echo

  if ! "$BIN" "$@"; then
    error "scan завершился с ошибкой."
    return 1
  fi

  if [ -f "$SCAN_OUT" ] && [ -s "$SCAN_OUT" ]; then
    n=$(wc -l < "$SCAN_OUT" 2>/dev/null | tr -d ' ')
    info "Отчёт: $SCAN_OUT (${n:-?} строк)"
  else
    warn "Файл отчёта пуст или не создан: $SCAN_OUT"
  fi

  if has_conf; then
    info "Конфиг лучшего эндпоинта: $CONF_OUT"
    printf '%s\n' "${DIM}--- начало conf ---${NC}"
    head -n 40 "$CONF_OUT" 2>/dev/null || true
    printf '%s\n' "${DIM}--- конец (первые 40 строк) ---${NC}"
  else
    warn "Конфиг не создан: $CONF_OUT"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 5) Применить conf в awg-manager
# ---------------------------------------------------------------------------
awg_port() {
  p=""
  if [ -f "$AWG_SETTINGS" ]; then
    p=$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$AWG_SETTINGS" 2>/dev/null | head -1)
  fi
  [ -n "$p" ] || p=2222
  printf '%s\n' "$p"
}

awg_api_base() {
  printf 'http://127.0.0.1:%s/api' "$(awg_port)"
}

# Достаём API-ключ в AWG_KEY (глобально).
# Промпты только в stderr — иначе key=$(...) глотает вывод и «зависает».
# Только settings.json / .api_key — без интерактивного запроса (для фоновых проверок)
awg_load_api_key_quiet() {
  AWG_KEY=""
  if [ -f "$AWG_SETTINGS" ]; then
    for field in apiKey api_key ApiKey APIKey; do
      AWG_KEY=$(sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$AWG_SETTINGS" 2>/dev/null | head -1)
      [ -n "$AWG_KEY" ] && break
    done
  fi
  if [ -z "$AWG_KEY" ] && [ -f "$AWG_API_KEY_FILE" ]; then
    AWG_KEY=$(tr -d '\r\n' < "$AWG_API_KEY_FILE" 2>/dev/null)
  fi
  [ -n "$AWG_KEY" ]
}

awg_load_api_key() {
  if awg_load_api_key_quiet; then
    return 0
  fi
  printf '%s\n' "${YELLOW}[?]${NC} API-ключ awg-manager (Настройки → Расширенные → API Key):" >&2
  printf '    ' >&2
  AWG_KEY=$(read_choice)
  printf '\n' >&2
  if [ -n "$AWG_KEY" ]; then
    mkdir -p /opt/etc/awg-manager 2>/dev/null || true
    printf '%s\n' "$AWG_KEY" > "$AWG_API_KEY_FILE" 2>/dev/null || true
    chmod 600 "$AWG_API_KEY_FILE" 2>/dev/null || true
    info "Ключ сохранён в $AWG_API_KEY_FILE" >&2
  fi
  [ -n "$AWG_KEY" ]
}

# Список туннелей → файл: id|name|status|endpoint
# Ответ: {"success":true,"data":[{...},...]}
awg_list_tunnels() {
  base="$1"
  key="$2"
  out="$3"
  : > "$out"
  if ! command -v curl >/dev/null 2>&1; then
    error "Нужен curl для API awg-manager."
    return 1
  fi

  # -sS: без прогресса; жёсткие таймауты; без -f (чтобы увидеть тело при 401)
  resp=$(curl -sS --connect-timeout 3 --max-time 10 \
    -H "Authorization: Bearer ${key}" \
    "${base}/tunnels/list" 2>/dev/null) || resp=""

  if [ -z "$resp" ]; then
    error "Пустой ответ от ${base}/tunnels/list"
    error "Проверьте, что awg-manager запущен и API-ключ верный."
    return 1
  fi
  case "$resp" in
    *'"success":false'*|*'"success": false'*)
      err=$(printf '%s' "$resp" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
      error "API: ${err:-ошибка}"
      return 1
      ;;
  esac

  # Без pipe→while (subshell): пишем через временный файл кусков
  tmpc="$out.chunks"
  # Разделитель объектов: каждая «{» — новый фрагмент
  printf '%s' "$resp" | tr '{' '\n' > "$tmpc" 2>/dev/null || true
  : > "$out"
  while IFS= read -r chunk || [ -n "$chunk" ]; do
    case "$chunk" in
      *'"id"'*)
        tid=$(printf '%s' "$chunk" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        # пропускаем служебные вложенные объекты без id туннеля вида awg*
        [ -n "$tid" ] || continue
        case "$tid" in
          awg*|wg*|tun*|id-*) ;;
          *)
            # всё равно принимаем любые id из data[]
            ;;
        esac
        tname=$(printf '%s' "$chunk" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        tstat=$(printf '%s' "$chunk" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        tend=$(printf '%s' "$chunk" | sed -n 's/.*"endpoint"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        # "address":"172.16.0.3, 2606:..." или "172.16.0.2/32"
        taddr=$(printf '%s' "$chunk" | sed -n 's/.*"address"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        taddr_v4=$(printf '%s' "$taddr" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
          sed -n 's|^\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\(/[0-9]*\)\{0,1\}$|\1|p' | head -1)
        tifc=$(printf '%s' "$chunk" | sed -n 's/.*"interfaceName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        tndms=$(printf '%s' "$chunk" | sed -n 's/.*"ndmsName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        # отсекаем куски без status (вложенные pingCheck и т.п.)
        [ -n "$tstat" ] || continue
        # id|name|status|endpoint|ipv4|iface|ndms
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$tid" "${tname:-?}" "${tstat:-?}" "${tend:-}" "${taddr_v4:-}" "${tifc:-}" "${tndms:-}" >> "$out"
        ;;
    esac
  done < "$tmpc"
  rm -f "$tmpc" 2>/dev/null || true
  [ -s "$out" ]
}

# IPv4 из строки Address conf (без /prefix)
awg_conf_ipv4() {
  conf="$1"
  grep -iE '^[[:space:]]*Address[[:space:]]*=' "$conf" 2>/dev/null | head -1 | \
    sed 's/^[^=]*=[[:space:]]*//' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    sed -n 's|^\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\(/[0-9]*\)\{0,1\}$|\1|p' | head -1
}

# Подставить Address = IP/32 в conf (сохраняя остальное)
awg_patch_conf_address() {
  conf="$1"
  newip="$2"
  [ -f "$conf" ] || return 1
  [ -n "$newip" ] || return 1
  tmp="$conf.addrnew"
  if grep -qiE '^[[:space:]]*Address[[:space:]]*=' "$conf" 2>/dev/null; then
    # заменяем только первый IPv4 в значении; префикс /32 если был или по умолчанию
    sed -E "s|^([[:space:]]*[Aa][Dd][Dd][Rr][Ee][Ss][Ss][[:space:]]*=[[:space:]]*)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?|\1${newip}/32|" \
      "$conf" > "$tmp" 2>/dev/null || return 1
  else
    # добавить в [Interface]
    if grep -q '^\[Interface\]' "$conf" 2>/dev/null; then
      awk -v ip="$newip" '
        BEGIN { done=0 }
        /^\[Interface\]/ { inif=1 }
        inif && /^\[/ && !/^\[Interface\]/ {
          if (!done) { print "Address = " ip "/32"; done=1 }
          inif=0
        }
        { print }
        END { if (!done) print "Address = " ip "/32" }
      ' "$conf" > "$tmp" 2>/dev/null || return 1
    else
      { printf 'Address = %s/32\n' "$newip"; cat "$conf"; } > "$tmp" || return 1
    fi
  fi
  mv -f "$tmp" "$conf" || return 1
  return 0
}

# Адреса системных Wireguard* из RCI → файл: name|ipv4
# (Keenetic «Системный» туннель может не быть в awg-manager /tunnels/list)
rci_wireguard_addrs() {
  # out: id|description|ipv4
  out="$1"
  : > "$out"
  rci=$(curl -s --connect-timeout 1 --max-time 3 "http://127.0.0.1:79/rci/show/interface" 2>/dev/null) || rci=""
  [ -n "$rci" ] || return 1
  tmpc="$out.rci"
  printf '%s' "$rci" | tr '{' '\n' > "$tmpc" 2>/dev/null || true
  while IFS= read -r chunk || [ -n "$chunk" ]; do
    case "$chunk" in
      *Wireguard*) ;;
      *) continue ;;
    esac
    echo "$chunk" | grep -qE '"type"[[:space:]]*:[[:space:]]*"Wireguard"|"id"[[:space:]]*:[[:space:]]*"Wireguard[0-9]+"' \
      || continue
    id=$(printf '%s' "$chunk" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    case "$id" in
      Wireguard*|wireguard*) ;;
      *) continue ;;
    esac
    addr=$(printf '%s' "$chunk" | sed -n 's/.*"address"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' | head -1)
    [ -n "$addr" ] || continue
    desc=$(printf '%s' "$chunk" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    printf '%s|%s|%s\n' "$id" "${desc:-$id}" "$addr" >> "$out"
  done < "$tmpc"
  rm -f "$tmpc" 2>/dev/null || true
  [ -s "$out" ]
}

# Если IPv4 conf занят другими туннелями (awg-manager + системные Wireguard)
# кроме skip_id — взять свободный 172.16.0.x
# listf: id|name|status|endpoint|ipv4|iface|ndms
awg_ensure_free_address() {
  conf="$1"
  listf="$2"
  skip_id="${3:-}"

  # Исключаем только интерфейсы заменяемого туннеля (не «тот же IP»)
  skip_ndms=""
  skip_ifc=""
  skip_cur=""
  if [ -n "$skip_id" ] && [ -s "$listf" ]; then
    while IFS='|' read -r _aid _aname _astat _aend _aaddr _aifc _andms || [ -n "$_aid" ]; do
      if [ "$_aid" = "$skip_id" ]; then
        skip_cur="$_aaddr"
        skip_ndms="$_andms"
        skip_ifc="$_aifc"
        case "$skip_ifc" in
          *'|'*) skip_ifc=$(printf '%s' "$skip_ifc" | cut -d'|' -f1) ;;
        esac
        break
      fi
    done < "$listf"
  fi

  # При replace: сначала берём УЖЕ назначенный адрес туннеля (не из conf scan)
  if [ -n "$skip_cur" ]; then
    conf_cur=$(awg_conf_ipv4 "$conf")
    if [ -n "$conf_cur" ] && [ "$conf_cur" != "$skip_cur" ]; then
      info "Туннель $skip_id уже с Address $skip_cur — оставляем (в conf было $conf_cur)."
      awg_patch_conf_address "$conf" "$skip_cur" 2>/dev/null || true
      if [ "$conf" != "$CONF_OUT" ] && [ -f "$CONF_OUT" ]; then
        awg_patch_conf_address "$CONF_OUT" "$skip_cur" 2>/dev/null || true
      fi
    fi
    cur="$skip_cur"
  else
    cur=$(awg_conf_ipv4 "$conf")
  fi

  if [ -z "$cur" ]; then
    warn "В conf нет Address (IPv4) — пропускаем проверку конфликта."
    return 0
  fi

  usedf="$TMPDIR/used-addr.txt"
  used_src="$TMPDIR/used-addr-src.txt"
  mkdir -p "$TMPDIR" 2>/dev/null || true
  : > "$usedf"
  : > "$used_src"

  _used_add() {
    # _used_add IP SRC
    [ -n "$1" ] || return 0
    printf '%s\n' "$1" >> "$usedf"
    printf '%s|%s\n' "$1" "$2" >> "$used_src"
  }

  # 1) awg-manager tunnels
  if [ -s "$listf" ]; then
    while IFS='|' read -r _aid _aname _astat _aend _aaddr _aifc _andms || [ -n "$_aid" ]; do
      [ -n "$_aaddr" ] || continue
      if [ -n "$skip_id" ] && [ "$_aid" = "$skip_id" ]; then
        continue
      fi
      _used_add "$_aaddr" "awg-manager ${_aid} (${_aname:-?})"
    done < "$listf"
  fi

  # 2) RCI Wireguard* — кроме NDMS текущего туннеля
  rcif="$TMPDIR/rci-wg-addr.txt"
  if rci_wireguard_addrs "$rcif" 2>/dev/null; then
    while IFS='|' read -r rid rname raddr || [ -n "$rid" ]; do
      if [ -z "$raddr" ] && [ -n "$rname" ]; then
        raddr="$rname"; rname="$rid"; rid=""
      fi
      [ -n "$raddr" ] || continue
      if [ -n "$skip_ndms" ] && { [ "$rid" = "$skip_ndms" ] || [ "$rname" = "$skip_ndms" ]; }; then
        continue
      fi
      _used_add "$raddr" "RCI ${rname:-$rid}"
    done < "$rcif"
  fi

  # 3) Живые адреса nwg*/Wireguard*/awg* (ip addr) — UI/RCI могут расходиться
  for _path in /sys/class/net/nwg* /sys/class/net/Wireguard* /sys/class/net/wireguard* /sys/class/net/awg*; do
    [ -e "$_path" ] || continue
    _bif=$(basename "$_path")
    if [ -n "$skip_ifc" ] && [ "$_bif" = "$skip_ifc" ]; then
      continue
    fi
    if [ -n "$skip_ndms" ] && [ "$_bif" = "$skip_ndms" ]; then
      continue
    fi
    _a=""
    if command -v ip >/dev/null 2>&1; then
      _a=$(ip -4 -o addr show dev "$_bif" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    fi
    if [ -z "$_a" ] && command -v ifconfig >/dev/null 2>&1; then
      _a=$(ifconfig "$_bif" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p;s/.*inet \([0-9.]*\).*/\1/p' | head -1)
    fi
    [ -n "$_a" ] || continue
    _used_add "$_a" "iface ${_bif}"
  done

  conflict=0
  conflict_src=""
  if grep -qxF "$cur" "$usedf" 2>/dev/null; then
    conflict=1
    conflict_src=$(grep -F "${cur}|" "$used_src" 2>/dev/null | head -1 | cut -d'|' -f2-)
  fi

  if [ "$conflict" != "1" ]; then
    info "Address $cur оставляем (не занят другими)."
    return 0
  fi
  warn "Адрес $cur занят: ${conflict_src:-?} — ищем свободный."

  free=""
  n=2
  while [ "$n" -le 254 ]; do
    cand="172.16.0.$n"
    if ! grep -qxF "$cand" "$usedf" 2>/dev/null; then
      free="$cand"
      break
    fi
    n=$((n + 1))
  done

  if [ -z "$free" ]; then
    error "Нет свободного адреса в 172.16.0.0/24"
    return 1
  fi

  if awg_patch_conf_address "$conf" "$free"; then
    info "Address: $cur → $free"
    if [ "$conf" != "$CONF_OUT" ] && [ -f "$CONF_OUT" ]; then
      awg_patch_conf_address "$CONF_OUT" "$free" 2>/dev/null || true
    fi
    return 0
  fi
  error "Не удалось записать Address = $free"
  return 1
}

# Разбор секции «Best endpoint per node» из list → файл: NODE|ENDPOINT|TUN_PING|LOSS|LOCATION
# Пример строки:
# ARN    188.114.96.199:2408    27ms          25ms      0%     RU         Stockholm, SE
awg_parse_best_endpoints() {
  list="$1"
  out="$2"
  : > "$out"
  [ -f "$list" ] || return 1

  in_best=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'Best endpoint per node'*)
        in_best=1
        continue
        ;;
    esac
    [ "$in_best" = "1" ] || continue
    # пропускаем заголовок таблицы и пустые
    case "$line" in
      ''|\#*) continue ;;
      NODE[[:space:]]*) continue ;;
    esac
    # NODE ENDPOINT ... LOSS SEEN NODE_LOCATION...
    # awk: $1=NODE $2=ENDPOINT $5=LOSS $7+=location (после SEEN AS)
    set -- $line
    node="$1"
    ep="$2"
    # минимум: NODE + ip:port
    [ -n "$node" ] && [ -n "$ep" ] || continue
    case "$ep" in
      *:* ) ;;
      *) continue ;;
    esac
    # tun ping / loss — позиции зависят от выравнивания; ищем LOSS как *%
    loss=""
    tunp=""
    loc=""
    # проход по полям
    i=0
    for f in $line; do
      i=$((i + 1))
      case "$f" in
        *ms)
          # первое *ms после endpoint — ENDPOINT PING, второе — TUN PING
          if [ -z "$tunp" ]; then
            # пропускаем endpoint ping (первое ms после ep)
            if [ "$i" -gt 2 ]; then
              if [ -z "$_ep_ping" ]; then
                _ep_ping="$f"
              else
                tunp="$f"
              fi
            fi
          fi
          ;;
        *%)
          [ -z "$loss" ] && loss="$f"
          ;;
      esac
    done
    # location: всё после SEEN AS (обычно 2-буквенный код страны)
    # проще: с конца — NODE LOCATION = поля после LOSS и SEEN
    loc=$(printf '%s\n' "$line" | awk '{
      # найти поле с % (LOSS), следующее — SEEN AS, остальное — location
      for (i=1;i<=NF;i++) if ($i ~ /%$/) { start=i+2; break }
      loc=""
      for (j=start;j<=NF;j++) loc = (loc ? loc " " : "") $j
      print loc
    }')
    tunp=$(printf '%s\n' "$line" | awk '{
      n=0
      for (i=3;i<=NF;i++) if ($i ~ /ms$/) { n++; if (n==2) { print $i; exit } }
    }')
    loss=$(printf '%s\n' "$line" | awk '{
      for (i=1;i<=NF;i++) if ($i ~ /%$/) { print $i; exit }
    }')
    _ep_ping=""
    printf '%s|%s|%s|%s|%s\n' "$node" "$ep" "${tunp:-?}" "${loss:-?}" "${loc:-}" >> "$out"
  done < "$list"
  [ -s "$out" ]
}

# Выбор endpoint из best-per-node. Результат: SELECTED_EP, SELECTED_NODE
awg_pick_endpoint() {
  SELECTED_EP=""
  SELECTED_NODE=""
  bestf="$TMPDIR/best-ep.txt"
  mkdir -p "$TMPDIR" 2>/dev/null || true

  if [ ! -f "$SCAN_OUT" ] || [ ! -s "$SCAN_OUT" ]; then
    error "Нет списка: $SCAN_OUT (сначала п. 3)."
    return 1
  fi
  if ! awg_parse_best_endpoints "$SCAN_OUT" "$bestf"; then
    error "Не удалось разобрать «Best endpoint per node» в $SCAN_OUT"
    return 1
  fi

  echo
  printf '%s\n' "${BOLD}Лучший endpoint по нодам (из list):${NC}"
  i=0
  while IFS='|' read -r node ep tunp loss loc || [ -n "$node" ]; do
    [ -n "$node" ] || continue
    i=$((i + 1))
    mark=""
    case "$node" in
      DME) mark=" ${YELLOW}(часто DPI)${NC}" ;;
    esac
    printf '  %s%d)%s  %s%-4s%s  %s  %s[tun %s · loss %s]%s  %s%s\n' \
      "$BOLD" "$i" "$NC" "$CYAN" "$node" "$NC" "$ep" \
      "$DIM" "$tunp" "$loss" "$NC" "${loc}" "$mark"
  done < "$bestf"

  # текущий Endpoint из conf
  cur=$(grep -iE '^[[:space:]]*Endpoint[[:space:]]*=' "$CONF_OUT" 2>/dev/null | head -1 | sed 's/^[^=]*=[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$cur" ] && printf '%s\n' "${DIM}  сейчас в conf: Endpoint = ${cur}${NC}"

  echo "  0) Отмена"
  echo
  printf '  %sВыбор endpoint:%s ' "$BOLD" "$NC"
  sel=$(read_choice)
  echo

  case "$sel" in
    0|"") info "Отменено."; return 1 ;;
    *[!0-9]*) warn "Неверный выбор."; return 1 ;;
  esac
  if [ "$sel" -lt 1 ] || [ "$sel" -gt "$i" ]; then
    warn "Неверный номер."; return 1
  fi

  SELECTED_NODE=$(sed -n "${sel}p" "$bestf" | cut -d'|' -f1)
  SELECTED_EP=$(sed -n "${sel}p" "$bestf" | cut -d'|' -f2)
  if [ -z "$SELECTED_EP" ]; then
    error "Пустой endpoint."
    return 1
  fi
  info "Выбрано: $SELECTED_NODE → $SELECTED_EP"
  return 0
}

# Подставить Endpoint в conf → dest (остальное без изменений)
awg_patch_conf_endpoint() {
  src="$1"
  dest="$2"
  ep="$3"
  [ -f "$src" ] || return 1
  [ -n "$ep" ] || return 1

  if grep -qiE '^[[:space:]]*Endpoint[[:space:]]*=' "$src" 2>/dev/null; then
    # сохраняем отступ и регистр ключа
    sed -E "s|^([[:space:]]*[Ee][Nn][Dd][Pp][Oo][Ii][Nn][Tt][[:space:]]*=[[:space:]]*).*$|\1${ep}|" \
      "$src" > "$dest" 2>/dev/null || return 1
  else
    # добавить в конец секции [Peer], иначе в конец файла
    if grep -q '^\[Peer\]' "$src" 2>/dev/null; then
      awk -v ep="$ep" '
        BEGIN { done=0 }
        /^\[Peer\]/ { inpeer=1 }
        inpeer && /^\[/ && !/^\[Peer\]/ {
          if (!done) { print "Endpoint = " ep; done=1 }
          inpeer=0
        }
        { print }
        END { if (!done) print "Endpoint = " ep }
      ' "$src" > "$dest" 2>/dev/null || return 1
    else
      { cat "$src"; printf '\nEndpoint = %s\n' "$ep"; } > "$dest" || return 1
    fi
  fi
  # обновить и основной conf на диске
  cp -f "$dest" "$src" 2>/dev/null || true
  return 0
}


# Старт/рестарт туннеля через API (после replace, если был stopped — API сам не поднимает)
awg_control() {
  # awg_control start|stop|restart ID
  action="$1"
  tid="$2"
  key="$3"
  base="$4"
  [ -n "$tid" ] || return 1
  resp=$(curl -sS --connect-timeout 5 --max-time 30 \
    -X POST "${base}/control/${action}?id=${tid}" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null) || resp=""
  if printf '%s' "$resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
    info "control/${action} id=${tid}: OK"
    return 0
  fi
  err=$(printf '%s' "$resp" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -z "$err" ] && err=$(printf '%s' "$resp" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  warn "control/${action} id=${tid}: ${err:-fail}"
  [ -n "$resp" ] && printf '%s\n' "${DIM}$resp${NC}" | head -c 300 && echo
  return 1
}

do_apply_awg() {
  echo
  info "Применить conf в awg-manager"
  if ! is_awg_manager_installed; then
    error "awg-manager не установлен (opkg / /opt/etc/awg-manager)."
    return 1
  fi
  if ! has_conf; then
    error "Нет конфига: $CONF_OUT"
    error "Сначала выполните пункт 3 (сканирование)."
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    error "Нужен curl."
    return 1
  fi

  mkdir -p "$TMPDIR" 2>/dev/null || true

  # 1) выбор endpoint из list → правка conf
  if ! awg_pick_endpoint; then
    return 1
  fi
  conf_use="$TMPDIR/warpscout-awg-apply.conf"
  if ! awg_patch_conf_endpoint "$CONF_OUT" "$conf_use" "$SELECTED_EP"; then
    error "Не удалось подставить Endpoint = $SELECTED_EP в conf."
    return 1
  fi
  info "В $CONF_OUT: Endpoint = $SELECTED_EP"

  # 2) API
  base=$(awg_api_base)
  info "API: $base"

  if ! awg_load_api_key; then
    error "API-ключ не задан."
    return 1
  fi
  key="$AWG_KEY"

  listf="$TMPDIR/awg-tunnels.txt"
  info "Запрос списка туннелей..."
  if ! awg_list_tunnels "$base" "$key" "$listf"; then
    warn "Список туннелей пуст или недоступен — можно импортировать новый."
  fi

  echo
  printf '%s\n' "${BOLD}Туннели awg-manager:${NC}"
  i=0
  if [ -s "$listf" ]; then
    while IFS='|' read -r tid tname tstat tend taddr tifc tndms || [ -n "$tid" ]; do
      [ -n "$tid" ] || continue
      i=$((i + 1))
      print_tunnel_menu_line "$i" "$tid" "${tstat:-?}" "$tname" "$taddr" "$tend" "true"
    done < "$listf"
  fi
  new_idx=$((i + 1))
  printf '  %s%d)%s  Импорт нового туннеля (POST /import/conf)\n' "$BOLD" "$new_idx" "$NC"
  echo "  0) Отмена"
  echo
  printf '  %sВыбор туннеля:%s ' "$BOLD" "$NC"
  sel=$(read_choice)
  echo

  case "$sel" in
    0|"") info "Отменено."; return 0 ;;
  esac

  # импорт нового — конфликт Address со всеми существующими туннелями
  if [ "$sel" = "$new_idx" ]; then
    if ! awg_ensure_free_address "$conf_use" "$listf" ""; then
      return 1
    fi

    def_name="WARP-${SELECTED_NODE}"
    printf '%s' "${YELLOW}[?]${NC} Имя нового туннеля [${def_name}]: "
    tname=$(read_choice)
    echo
    [ -n "$tname" ] || tname="$def_name"
    printf '%s' "${YELLOW}[?]${NC} Backend (kernel/nativewg) [nativewg]: "
    backend=$(read_choice)
    echo
    [ -n "$backend" ] || backend="nativewg"

    bodyf="$TMPDIR/awg-import.json"
    {
      printf '{"content":"'
      tr -d '\r' < "$conf_use" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\t/\\t/g' | awk '{printf "%s\\n",$0}'
      printf '","name":"%s","backend":"%s"}' "$tname" "$backend"
    } > "$bodyf"

    info "POST ${base}/import/conf  name=$tname backend=$backend endpoint=$SELECTED_EP"
    resp=$(curl -sS --connect-timeout 5 --max-time 30 \
      -X POST "${base}/import/conf" \
      -H "Authorization: Bearer ${key}" \
      -H "Content-Type: application/json" \
      -d @"$bodyf" 2>/dev/null) || resp=""
    if printf '%s' "$resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
      info "Импорт успешен."
      printf '%s\n' "${DIM}$resp${NC}" | head -c 400
      echo
      new_id=$(printf '%s' "$resp" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
      if [ -n "$new_id" ]; then
        sleep 1
        info "Запуск $new_id..."
        if ! awg_control start "$new_id" "$key" "$base"; then
          warn "start не удался — restart..."
          awg_control restart "$new_id" "$key" "$base" || true
        fi
      else
        warn "id нового туннеля не найден в ответе — запустите вручную."
      fi
      return 0
    fi
    error "Импорт не удался."
    [ -n "$resp" ] && printf '%s\n' "$resp"
    return 1
  fi

  # выбор по номеру
  case "$sel" in
    *[!0-9]*) warn "Неверный выбор."; return 1 ;;
  esac
  if [ "$sel" -lt 1 ] || [ "$sel" -gt "$i" ]; then
    warn "Неверный номер."
    return 1
  fi

  tid=$(sed -n "${sel}p" "$listf" | cut -d'|' -f1)
  tname=$(sed -n "${sel}p" "$listf" | cut -d'|' -f2)
  if [ -z "$tid" ]; then
    error "Не удалось определить id туннеля."
    return 1
  fi

  # Замена конфига без delete (маршрутизация/привязки туннеля сохраняются).
  # API: stop (если running) → запись conf → start только если был running.
  # Поэтому после replace всегда явно start/restart.
  if ! awg_ensure_free_address "$conf_use" "$listf" "$tid"; then
    return 1
  fi

  def_name="WARP-${SELECTED_NODE}"
  printf '%s' "${YELLOW}[?]${NC} Имя туннеля [${def_name}] (Enter = ${def_name}, «-» = оставить «${tname}», 0 = отмена): "
  new_name=$(read_choice)
  echo
  case "$new_name" in
    0) info "Отменено."; return 0 ;;
    -) new_name="" ;;
    "") new_name="$def_name" ;;
  esac
  if [ -n "$new_name" ] && [ "$new_name" != "$tname" ]; then
    info "Замена: id=$tid  «${tname}» → «${new_name}»  Endpoint ${SELECTED_EP} [${SELECTED_NODE}]"
  else
    new_name=""
    info "Замена: id=$tid  «${tname}»  Endpoint ${SELECTED_EP} [${SELECTED_NODE}]"
  fi

  info "Остановка $tid (перед replace)..."
  awg_control stop "$tid" "$key" "$base" || true

  bodyf="$TMPDIR/awg-replace.json"
  {
    printf '{"content":"'
    tr -d '\r' < "$conf_use" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\t/\\t/g' | awk '{printf "%s\\n",$0}'
    if [ -n "$new_name" ]; then
      printf '","name":"%s"}' "$new_name"
    else
      printf '"}'
    fi
  } > "$bodyf"

  info "POST ${base}/tunnels/replace?id=${tid}"
  resp=$(curl -sS --connect-timeout 5 --max-time 30 \
    -X POST "${base}/tunnels/replace?id=${tid}" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -d @"$bodyf" 2>/dev/null) || resp=""
  if ! printf '%s' "$resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
    error "replace не удался."
    [ -n "$resp" ] && printf '%s\n' "$resp"
    return 1
  fi
  info "Конфиг туннеля $tid заменён (Endpoint = $SELECTED_EP)."
  printf '%s\n' "${DIM}$resp${NC}" | head -c 400
  echo

  # После replace (особенно если туннель был stopped) API может не поднять его.
  sleep 1
  info "Запуск $tid..."
  if ! awg_control start "$tid" "$key" "$base"; then
    warn "start не удался — restart..."
    awg_control restart "$tid" "$key" "$base" || true
  fi
  return 0
}


# ---------------------------------------------------------------------------
# 6) Проверка туннеля (через интерфейс nwg*/awg*)
# ---------------------------------------------------------------------------
lookup_colo() {
  code="$1"
  [ -n "$code" ] || return 1
  case "$code" in
    HEL) printf '%s' "Хельсинки, Финляндия"; return 0 ;;
    ARN) printf '%s' "Стокгольм, Швеция"; return 0 ;;
    OSL) printf '%s' "Осло, Норвегия"; return 0 ;;
    CPH) printf '%s' "Копенгаген, Дания"; return 0 ;;
    FRA) printf '%s' "Франкфурт, Германия"; return 0 ;;
    AMS) printf '%s' "Амстердам, Нидерланды"; return 0 ;;
    LHR|LON) printf '%s' "Лондон, Великобритания"; return 0 ;;
    WAW) printf '%s' "Варшава, Польша"; return 0 ;;
    VIE) printf '%s' "Вена, Австрия"; return 0 ;;
    PRG) printf '%s' "Прага, Чехия"; return 0 ;;
    LED|SVO|DME|VKO) printf '%s' "Москва, Россия"; return 0 ;;
    MSQ) printf '%s' "Минск, Беларусь"; return 0 ;;
    IST) printf '%s' "Стамбул, Турция"; return 0 ;;
    DXB) printf '%s' "Дубай, ОАЭ"; return 0 ;;
    SIN) printf '%s' "Сингапур"; return 0 ;;
    NRT|HND) printf '%s' "Токио, Япония"; return 0 ;;
    LAX) printf '%s' "Лос-Анджелес, США"; return 0 ;;
    EWR|JFK|LGA) printf '%s' "Нью-Йорк, США"; return 0 ;;
    CDG) printf '%s' "Париж, Франция"; return 0 ;;
  esac
  return 1
}

show_cf_trace() {
  ifc="$1"
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl нет — trace недоступен"
    return 1
  fi
  info "Cloudflare trace (cdn-cgi/trace) via $ifc..."
  trace=$(curl -sS --connect-timeout 5 --max-time 10 --interface "$ifc" \
    "https://cloudflare.com/cdn-cgi/trace" 2>/dev/null) || trace=""
  if [ -z "$trace" ]; then
    warn "trace: нет ответа via $ifc"
    return 1
  fi
  cf_ip=$(printf '%s\n' "$trace" | sed -n 's/^ip=//p' | head -1)
  cf_colo=$(printf '%s\n' "$trace" | sed -n 's/^colo=//p' | head -1)
  cf_loc=$(printf '%s\n' "$trace" | sed -n 's/^loc=//p' | head -1)
  cf_warp=$(printf '%s\n' "$trace" | sed -n 's/^warp=//p' | head -1)
  cf_http=$(printf '%s\n' "$trace" | sed -n 's/^http=//p' | head -1)
  cf_tls=$(printf '%s\n' "$trace" | sed -n 's/^tls=//p' | head -1)
  [ -n "$cf_ip" ] && info "  ip=$cf_ip"
  if [ -n "$cf_colo" ]; then
    colo_name=$(lookup_colo "$cf_colo" 2>/dev/null) || colo_name=""
    if [ -n "$colo_name" ]; then
      info "  colo=$cf_colo — $colo_name"
    else
      info "  colo=$cf_colo"
    fi
  fi
  [ -n "$cf_loc" ] && info "  loc=$cf_loc"
  [ -n "$cf_warp" ] && info "  warp=$cf_warp"
  [ -n "$cf_http" ] && info "  http=$cf_http"
  [ -n "$cf_tls" ] && info "  tls=$cf_tls"
  case "$cf_warp" in
    on|ON) info "  WARP: активен" ;;
    off|OFF) warn "  WARP: off (трафик не через WARP?)" ;;
  esac
  return 0
}

check_url_via_iface() {
  ifc="$1"
  url="$2"
  label="$3"
  code="000"
  if ! command -v curl >/dev/null 2>&1; then
    error "Нужен curl."
    return 1
  fi
  errf="$TMPDIR/curl-err-$$"
  mkdir -p "$TMPDIR" 2>/dev/null || true
  code=$(curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 10 \
    --interface "$ifc" -L "$url" 2>"$errf") || true
  code=$(printf '%s' "$code" | tr -d '\r\n ')
  case "$code" in
    ''|*[!0-9]*) code="000" ;;
  esac
  err=""
  [ -s "$errf" ] && err=$(tr '\n' ' ' < "$errf" | head -c 100)
  rm -f "$errf"
  case "$code" in
    2??|3??)
      info "$label: OK (HTTP $code) via $ifc"
      return 0
      ;;
    000)
      warn "$label: нет ответа via $ifc${err:+ — $err}"
      return 1
      ;;
    *)
      warn "$label: HTTP $code via $ifc${err:+ — $err}"
      return 1
      ;;
  esac
}

run_iface_probes() {
  _probe_ok=0
  check_url_via_iface "$1" "https://2ip.io/" "2ip.io" && _probe_ok=$((_probe_ok + 1))
  check_url_via_iface "$1" "https://www.google.com/" "google.com" && _probe_ok=$((_probe_ok + 1))
  check_url_via_iface "$1" "https://web.telegram.org/" "web.telegram.org" && _probe_ok=$((_probe_ok + 1))
}

list_tunnel_ifaces() {
  _if_list=""
  for n in /sys/class/net/*; do
    [ -e "$n" ] || continue
    b=$(basename "$n")
    case "$b" in
      nwg*|awg*|awgm*|opkgtun*|Wireguard*|wireguard*|t2s*) _if_list="${_if_list} $b" ;;
    esac
  done
  printf '%s\n' $_if_list | tr ' ' '\n' | grep -v '^$' | sort -u
}

_iflist_has() {
  grep -q "^${2}|" "$1" 2>/dev/null
}

_strip_q() {
  printf '%s' "$1" | sed 's/^["'"'"']*//;s/["'"'"']*$//;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Один curl RCI → map: ifc|name|addr|status  (nwg/t2s/opkgtun + raw id)
# Разбор одним awk, без циклов sed на каждый кусок.
_rci_tunnel_map() {
  out="$1"
  : > "$out"
  rci=$(curl -s --connect-timeout 1 --max-time 2 "http://127.0.0.1:79/rci/show/interface" 2>/dev/null) || rci=""
  [ -n "$rci" ] || return 1
  # Один проход awk: объекты по '{', только Wireguard/Proxy/OpkgTun
  printf '%s' "$rci" | awk '
    BEGIN { RS="{" }
    function get(s, key,    p, rest, q2) {
      p = index(s, "\"" key "\"")
      if (!p) return ""
      rest = substr(s, p + length(key) + 2)
      sub(/^[[:space:]]*:[[:space:]]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") return ""
      rest = substr(rest, 2)
      q2 = index(rest, "\"")
      if (!q2) return ""
      return substr(rest, 1, q2 - 1)
    }
    function digits(s,    i, c, out) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c >= "0" && c <= "9") out = out c
      }
      return out
    }
    {
      typ = get($0, "type")
      if (typ != "Wireguard" && typ != "Proxy" && typ != "OpkgTun") next
      id = get($0, "id")
      if (id == "") next
      desc = get($0, "description")
      addr = get($0, "address")
      link = get($0, "link")
      if (link == "") link = "up"
      num = digits(id)
      linux = id
      if (typ == "Wireguard" && num != "") linux = "nwg" num
      if (typ == "Proxy" && num != "") linux = "t2s" num
      if (typ == "OpkgTun" && num != "") linux = "opkgtun" num
      name = desc
      if (name == "") name = id
      glob = "false"
      if (index($0, "\"global\"") && index($0, "\"global\": true")) glob = "true"
      if (index($0, "\"global\":true")) glob = "true"
      print linux "|" name "|" addr "|" link "|" glob
    }
  ' > "$out" 2>/dev/null
  [ -s "$out" ]
}

do_check_tunnel() {
  echo
  info "Проверка туннеля"
  if ! command -v curl >/dev/null 2>&1; then
    error "Нужен curl."
    return 1
  fi

  ensure_tmpdir
  # ifc|name|status|addr|global|endpoint
  iflistf="$TMPDIR/ifaces.txt"
  : > "$iflistf"

  # --- один запрос RCI: имена + адреса + link ---
  mapf="$TMPDIR/rci-tun.map"
  _rci_tunnel_map "$mapf" 2>/dev/null || : > "$mapf"

  # --- интерфейсы из sysfs (без ifconfig/ip на каждый) ---
  # iflistf: ifc|name|status|addr|global
  for ifc in $(list_tunnel_ifaces); do
    [ -n "$ifc" ] || continue
    st="up"
    [ -e "/sys/class/net/$ifc/operstate" ] && st=$(cat "/sys/class/net/$ifc/operstate" 2>/dev/null || echo up)
    case "$st" in unknown|down) ;; *) st="up" ;; esac
    line=$(grep "^${ifc}|" "$mapf" 2>/dev/null | head -1)
    glob="false"
    if [ -n "$line" ]; then
      name=$(printf '%s' "$line" | cut -d'|' -f2)
      addr=$(printf '%s' "$line" | cut -d'|' -f3)
      rlink=$(printf '%s' "$line" | cut -d'|' -f4)
      glob=$(printf '%s' "$line" | cut -d'|' -f5)
      [ -n "$rlink" ] && st="$rlink"
    else
      name="$ifc"
      addr=""
    fi
    [ -n "$glob" ] || glob="false"
    # ifc|name|status|addr|global|endpoint
    printf '%s|%s|%s|%s|%s|%s\n' "$ifc" "$name" "$st" "$addr" "$glob" "" >> "$iflistf"
  done

  if [ ! -s "$iflistf" ] && [ -s "$mapf" ]; then
    while IFS='|' read -r ifc name addr st glob || [ -n "$ifc" ]; do
      case "$ifc" in nwg*|t2s*|opkgtun*|awg*) ;; *) continue ;; esac
      _iflist_has "$iflistf" "$ifc" && continue
      printf '%s|%s|%s|%s|%s|%s\n' "$ifc" "${name:-$ifc}" "${st:-up}" "$addr" "${glob:-false}" "" >> "$iflistf"
    done < "$mapf"
  fi

  # awg-manager: имена/status для awgm*/nwg* (один быстрый запрос)
  if is_awg_manager_installed && awg_load_api_key_quiet; then
    base=$(awg_api_base)
    listf="$TMPDIR/awg-tunnels-check.txt"
    if awg_list_tunnels "$base" "$AWG_KEY" "$listf" 2>/dev/null; then
      while IFS='|' read -r _tid tname tstat tend taddr tifc _tndms || [ -n "$_tid" ]; do
        tifc=$(_strip_q "$tifc")
        tname=$(_strip_q "$tname")
        tstat=$(_strip_q "$tstat")
        tend=$(_strip_q "$tend")
        [ -n "$tifc" ] || continue
        case "$tifc" in *'|'*) tifc=$(_strip_q "$(printf '%s' "$tifc" | cut -d'|' -f1)") ;; esac
        ta=$(printf '%s' "$taddr" | cut -d/ -f1)
        ta=$(_strip_q "$ta")
        if _iflist_has "$iflistf" "$tifc"; then
          tmpm="$iflistf.map"
          : > "$tmpm"
          while IFS='|' read -r _i _n _s _a _g _e || [ -n "$_i" ]; do
            _i=$(_strip_q "$_i")
            if [ "$_i" = "$tifc" ]; then
              printf '%s|%s|%s|%s|%s|%s\n' "$tifc" "${tname:-$_n}" "${tstat:-$_s}" "${ta:-$_a}" "true" "${tend:-$_e}" >> "$tmpm"
            else
              printf '%s|%s|%s|%s|%s|%s\n' "$_i" "$_n" "$_s" "$_a" "$_g" "$_e" >> "$tmpm"
            fi
          done < "$iflistf"
          mv -f "$tmpm" "$iflistf" 2>/dev/null || cp -f "$tmpm" "$iflistf"
        else
          printf '%s|%s|%s|%s|true|%s\n' "$tifc" "${tname:-$tifc}" "${tstat:-up}" "$ta" "$tend" >> "$iflistf"
        fi
      done < "$listf"
    fi
  fi

  # дедуп по ifc
  if [ -s "$iflistf" ]; then
    tmpd="$iflistf.dedup"
    : > "$tmpd"
    while IFS='|' read -r _i _n _s _a _g _e || [ -n "$_i" ]; do
      _i=$(_strip_q "$_i")
      [ -n "$_i" ] || continue
      _iflist_has "$tmpd" "$_i" && continue
      printf '%s|%s|%s|%s|%s|%s\n' "$_i" "$(_strip_q "$_n")" "$(_strip_q "$_s")" "$(_strip_q "$_a")" "$(_strip_q "${_g:-false}")" "$(_strip_q "${_e}")" >> "$tmpd"
    done < "$iflistf"
    mv -f "$tmpd" "$iflistf" 2>/dev/null || cp -f "$tmpd" "$iflistf"
  fi

  if [ ! -s "$iflistf" ]; then
    error "Не найдены туннели (nwg*/awgm*/t2s*/opkgtun*)."
    return 1
  fi

  i=$(wc -l < "$iflistf" 2>/dev/null | tr -d ' ')
  case "$i" in ''|*[!0-9]*) i=0 ;; esac

  # цикл: проверка → снова список (без выхода в главное меню)
  while true; do
    iface=""
    tlabel=""

    if [ "$i" -eq 1 ]; then
      iface=$(sed -n '1p' "$iflistf" | cut -d'|' -f1)
      tlabel=$(sed -n '1p' "$iflistf" | cut -d'|' -f2)
      tstat=$(sed -n '1p' "$iflistf" | cut -d'|' -f3)
      taddr=$(sed -n '1p' "$iflistf" | cut -d'|' -f4)
      tglob=$(sed -n '1p' "$iflistf" | cut -d'|' -f5)
      tend=$(sed -n '1p' "$iflistf" | cut -d'|' -f6)
      if [ "$tglob" = "true" ]; then
        info "Интерфейс: $iface · ${GREEN}${tlabel}${NC}${taddr:+ · $taddr}${tend:+ · $tend}  ${DIM}[${tstat}]${NC}"
      else
        info "Интерфейс: $iface · ${DIM}${tlabel}${NC}${taddr:+ · $taddr}${tend:+ · $tend}  ${DIM}[${tstat}]${NC}"
      fi
    else
      echo
      printf '%s\n' "${BOLD}Туннели / интерфейсы:${NC}"
      n=0
      while IFS='|' read -r ifc tlab tstat taddr tglob tend || [ -n "$ifc" ]; do
        [ -n "$ifc" ] || continue
        n=$((n + 1))
        print_tunnel_menu_line "$n" "$ifc" "${tstat:-?}" "$tlab" "$taddr" "$tend" "${tglob:-false}"
      done < "$iflistf"
      echo "  0) Выход"
      echo
      printf '  %sВыбор:%s ' "$BOLD" "$NC"
      sel=$(read_choice)
      echo
      case "$sel" in
        0|"") info "Выход из проверки."; return 0 ;;
        *[!0-9]*) warn "Неверный выбор."; continue ;;
      esac
      if [ "$sel" -lt 1 ] || [ "$sel" -gt "$n" ]; then
        warn "Неверный номер."
        continue
      fi
      iface=$(sed -n "${sel}p" "$iflistf" | cut -d'|' -f1)
      tlabel=$(sed -n "${sel}p" "$iflistf" | cut -d'|' -f2)
    fi

    [ -n "$iface" ] || { error "Пустой интерфейс."; return 1; }

    if ! ip link show "$iface" >/dev/null 2>&1 && [ ! -e "/sys/class/net/$iface" ]; then
      warn "Интерфейс $iface не найден (ip link)."
    fi

    echo
    info "Проверяем: $iface${tlabel:+ · $tlabel}"
    run_iface_probes "$iface"
    ok=$_probe_ok
    echo
    show_cf_trace "$iface" || true
    echo
    if [ "$ok" -ge 2 ]; then
      info "Проверка пройдена: $ok/3 хостов доступны через $iface"
    else
      error "Хосты недоступны через $iface ($ok/3)"
      printf '%s\n' "${DIM}Вручную: curl --interface $iface -m 10 -L https://2ip.io/${NC}"
    fi

    # один интерфейс — не крутить меню
    if [ "$i" -eq 1 ]; then
      return 0
    fi

    echo
    if confirm_Y "Проверить другой туннель?"; then
      continue
    fi
    return 0
  done
}

# ---------------------------------------------------------------------------
# 88) Удаление
# ---------------------------------------------------------------------------
do_remove() {
  echo
  info "Удаление warpscout"
  if ! is_installed && [ ! -f "$ACCOUNT_FILE" ] && [ ! -f "$SCAN_OUT" ] && [ ! -f "$CONF_OUT" ]; then
    warn "Ничего не найдено."
    return 0
  fi

  if ! confirm_yes "Удалить warpscout и связанные файлы?"; then
    info "Отменено."
    return 0
  fi

  remove_data=0
  if [ -f "$ACCOUNT_FILE" ] || [ -f "$SCAN_OUT" ] || [ -f "$CONF_OUT" ]; then
    confirm_yes "Также удалить аккаунт, list и conf?" && remove_data=1
  fi

  if [ -f "$BIN" ]; then
    rm -f "$BIN" "${BIN}.bak" 2>/dev/null || true
    info "  удалён: $BIN"
  fi

  if [ "$remove_data" = "1" ]; then
    [ -f "$ACCOUNT_FILE" ] && rm -f "$ACCOUNT_FILE" && info "  удалён: $ACCOUNT_FILE"
    [ -f "$SCAN_OUT" ] && rm -f "$SCAN_OUT" && info "  удалён: $SCAN_OUT"
    [ -f "$CONF_OUT" ] && rm -f "$CONF_OUT" && info "  удалён: $CONF_OUT"
    [ -f "$JUNK_FILE" ] && rm -f "$JUNK_FILE" && info "  удалён: $JUNK_FILE"
    [ -f "$FIND_JUNK_LOG" ] && rm -f "$FIND_JUNK_LOG" && info "  удалён: $FIND_JUNK_LOG"
  fi

  info "Готово."
  return 0
}

# ---------------------------------------------------------------------------
# Меню
# ---------------------------------------------------------------------------
main_menu() {
  while true; do
    clear 2>/dev/null || true
    printf '%s\n' "${CYAN}================================================${NC}"
    printf '%s\n' "${CYAN}${BOLD}           warpscout  v${SCRIPT_VERSION}${NC}"
    printf '%s\n' "${CYAN}================================================${NC}"
    echo
    printf '%s\n' "${DIM}  Поиск рабочих эндпоинтов Cloudflare WARP${NC}"
    printf '%s\n' "${DIM}  https://github.com/${GITHUB_REPO}  (mipsel+arm)${NC}"
    printf '%s\n' "${DIM}  upstream: github.com/${OFFICIAL_REPO}  ·  fallback pin v${PIN_VERSION}${NC}"
    printf '%s\n' "${DIM}  bin → ${BIN}${NC}"
    echo
    show_status
    echo
    printf '%s\n' "${DIM}  ──────────────────────────────────────────${NC}"
    echo "  1) Установка / обновление warpscout"
    echo "  2) Создать аккаунт (register)"
    echo "  3) Сканирование адресов (AWG → list + conf)"
    echo "  4) Автоматический поиск / apply junk (find-junk)"
    if is_awg_manager_installed; then
      echo "  5) Применить conf в awg-manager"
    else
      printf '  %s5) Применить conf в awg-manager%s  %s(нужен awg-manager)%s\n' \
        "$DIM" "$NC" "$DIM" "$NC"
    fi
    echo "  6) Проверка туннеля"
    printf '%s\n' "${DIM}  ──────────────────────────────────────────${NC}"
    echo "  88) Удаление"
    echo "  0) Выход"
    printf '%s\n' "${DIM}  ──────────────────────────────────────────${NC}"
    echo
    printf '  %sВыбор:%s ' "$BOLD" "$NC"
    choice=$(read_choice)
    echo
    case "$choice" in
      1) do_install; pause ;;
      2) do_register; pause ;;
      3) do_scan; pause ;;
      4) do_find_junk; pause ;;
      5)
        if is_awg_manager_installed; then
          do_apply_awg; pause
        else
          error "awg-manager не установлен."
          pause
        fi
        ;;
      6) do_check_tunnel; pause ;;
      88) do_remove; pause ;;
      0|"") info "Выход."; exit 0 ;;
      *) warn "Неверный пункт"; pause ;;
    esac
  done
}

main_menu
