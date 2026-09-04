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

SCRIPT_VERSION="0.3.6"

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
  NC="${ESC}[0m"
  BOLD="${ESC}[1m"
else
  RED= GREEN= YELLOW= BLUE= CYAN= NC= BOLD=
fi

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[x]${NC} $*"; }
ask()   { printf '%s' "${CYAN}[?]${NC} $*"; }

# ---------------------------------------------------------------------------
# Определение архитектуры
# ---------------------------------------------------------------------------
detect_arch() {
  A=$(opkg print-architecture 2>/dev/null | sort -k3 -nr | awk '$2!="all"{print $2;exit}')
  case "$A" in
    aarch64*|arm*) ARCH="aarch64" ;;
    mipsel*)       ARCH="mipsel"  ;;
    mips*)         ARCH="mips"    ;;
    x86_64*|amd64) ARCH="x86_64"  ;;
    x86*)          ARCH="x86"     ;;
    *)
      error "Неизвестная архитектура: $A"
      exit 1
      ;;
  esac
  info "Архитектура: $ARCH ($A)"
}

# ---------------------------------------------------------------------------
# Проверка установленных пакетов
# ---------------------------------------------------------------------------
is_installed() {
  opkg list-installed 2>/dev/null | grep -q "^$1 "
}

pkg_version() {
  opkg info "$1" 2>/dev/null | awk -F': ' '/^Version:/{print $2; exit}'
}

# Проверка, слушает ли кто-то порт (для веб-интерфейса :90)
port_is_open() {
  local port="$1"
  # netstat (busybox) или ss
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]"
    return $?
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]"
    return $?
  fi
  # fallback: попытка подключиться к localhost
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1
    return $?
  fi
  return 1
}

service_status() {
  # $1 = тип: nfqws | nfqws2 | web
  case "$1" in
    nfqws)
      if [ -x /opt/etc/init.d/S51nfqws ] && /opt/etc/init.d/S51nfqws status 2>/dev/null | grep -qiE 'running|started|is running'; then
        echo "запущен"
      elif pgrep -f '/opt/usr/bin/nfqws ' >/dev/null 2>&1; then
        echo "запущен"
      else
        echo "остановлен"
      fi
      ;;
    nfqws2)
      if [ -x /opt/etc/init.d/S51nfqws2 ] && /opt/etc/init.d/S51nfqws2 status 2>/dev/null | grep -qiE 'running|started|is running'; then
        echo "запущен"
      elif pgrep -f '/opt/usr/bin/nfqws2' >/dev/null 2>&1; then
        echo "запущен"
      else
        echo "остановлен"
      fi
      ;;
    web)
      # nfqws-keenetic-web = lighttpd на порту 90
      if port_is_open 90; then
        echo "запущен (:90)"
      elif pgrep -f 'lighttpd.*nfqws|nfqws.*lighttpd|/opt/etc/lighttpd' >/dev/null 2>&1; then
        echo "запущен"
      elif [ -x /opt/etc/init.d/S80lighttpd ] && /opt/etc/init.d/S80lighttpd status 2>/dev/null | grep -qiE 'running|started'; then
        # если lighttpd общий — всё равно проверяем порт
        if port_is_open 90; then
          echo "запущен (:90)"
        else
          echo "остановлен"
        fi
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
    local ver status
    ver=$(pkg_version "$name")
    status=$(service_status "$kind")
    printf '  %s%-22s%s версия: %-12s статус: %s\n' "$GREEN" "$name" "$NC" "$ver" "$status"
  else
    printf '  %s%-22s%s не установлен\n' "$YELLOW" "$name" "$NC"
  fi
}

show_installed() {
  echo
  printf '%s\n' "${BOLD}Установленные компоненты:${NC}"
  print_pkg_info "nfqws-keenetic"     "nfqws"
  print_pkg_info "nfqws2-keenetic"    "nfqws2"
  print_pkg_info "nfqws-keenetic-web" "web"
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
  echo "src/gz nfqws-keenetic https://nfqws.github.io/nfqws-keenetic/all" > /opt/etc/opkg/nfqws-keenetic.conf
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
  echo "src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/all" > /opt/etc/opkg/nfqws2-keenetic.conf
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
DOT_DOH_STRATEGY='#DNS
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
  #     многострочный \
  #     контент
  #   "
  local found=0
  local in_block=0
  local has_content=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" -eq 0 ]; then
      case "$line" in
        NFQWS_ARGS_CUSTOM=\")
          # многострочный блок: открывающая кавычка на этой строке
          found=1
          in_block=1
          printf '%s\n' "$line" >> "$tmp"
          ;;
        NFQWS_ARGS_CUSTOM=\"\")
          # пустой однострочный — заменить на многострочный с DNS
          found=1
          printf 'NFQWS_ARGS_CUSTOM="\n' >> "$tmp"
          cat "$strat_tmp" >> "$tmp"
          printf '"\n' >> "$tmp"
          ;;
        NFQWS_ARGS_CUSTOM=\"*\")
          # однострочный с контентом: NFQWS_ARGS_CUSTOM="...content..."
          found=1
          # снять префикс и суффикс кавычек, дописать DNS перед закрытием
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
        *)
          printf '%s\n' "$line" >> "$tmp"
          ;;
      esac
    else
      # внутри многострочного NFQWS_ARGS_CUSTOM
      # закрывающая строка: только пробелы и "
      case "$line" in
        \"|[[:space:]]*\")
          # перед закрывающей кавычкой — вставить DNS
          if [ "$has_content" -eq 1 ]; then
            printf -- '--new\n' >> "$tmp"
          fi
          cat "$strat_tmp" >> "$tmp"
          printf '%s\n' "$line" >> "$tmp"
          in_block=0
          ;;
        *)
          # обычная строка контента
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
  local self url tmp remote_ver dest
  self=$(resolve_script_path)
  # cache-bust: иначе raw.githubusercontent.com может отдать старую копию
  url="${RAW_BASE}/nfqws-menu.sh?t=$(date +%s)"

  echo
  info "Локальная версия:  $SCRIPT_VERSION"
  info "Текущий файл:      $self"
  info "Источник:          ${RAW_BASE}/nfqws-menu.sh"
  ask "Скачать свежую версию и перезапустить меню? [Y/n]: "
  read -r ans
  case "$ans" in
    n|N|н|Н) info "Отменено."; return 0 ;;
  esac

  tmp="/tmp/nfqws-menu-update-$$.sh"
  info "Скачивание..."
  if ! download_file "$url" "$tmp"; then
    # fallback без query-string
    url="${RAW_BASE}/nfqws-menu.sh"
    if ! download_file "$url" "$tmp"; then
      error "Не удалось скачать обновление."
      rm -f "$tmp"
      return 1
    fi
  fi

  if ! head -1 "$tmp" | grep -qE '^#!/(usr/)?bin/(sh|bash)'; then
    error "Скачанный файл не похож на shell-скрипт."
    rm -f "$tmp"
    return 1
  fi
  if ! grep -q 'SCRIPT_VERSION=' "$tmp" 2>/dev/null; then
    error "В скачанном файле нет SCRIPT_VERSION — отмена."
    rm -f "$tmp"
    return 1
  fi

  remote_ver=$(extract_script_version "$tmp")
  [ -z "$remote_ver" ] && remote_ver="?"
  info "Версия в репозитории: $remote_ver"

  if [ "$remote_ver" = "$SCRIPT_VERSION" ]; then
    info "Уже актуальная версия ($SCRIPT_VERSION)."
    ask "Всё равно перезаписать и перезапустить? [y/N]: "
    read -r ans
    case "$ans" in
      y|Y|д|Д) ;;
      *) rm -f "$tmp"; info "Отменено."; return 0 ;;
    esac
  fi

  # Канонический путь + текущий файл + типичные места копий
  mkdir -p /opt/bin 2>/dev/null || true
  dest="/opt/bin/nfqws-menu.sh"

  install_copy() {
    local target="$1"
    [ -z "$target" ] && return 1
    # каталог должен существовать и быть доступен на запись
    local dir
    dir=$(dirname "$target")
    [ -d "$dir" ] || return 1
    [ -w "$dir" ] || return 1
    cat "$tmp" > "$target" || return 1
    chmod +x "$target" 2>/dev/null || true
    # проверка, что записалось
    local v
    v=$(extract_script_version "$target")
    if [ "$v" != "$remote_ver" ] && [ "$remote_ver" != "?" ]; then
      warn "  после записи версия не совпала: $target → $v (ожидали $remote_ver)"
      return 1
    fi
    info "  обновлён: $target (v$v)"
    return 0
  }

  info "Установка v${remote_ver}..."
  install_copy "$dest" || true

  if [ -n "$self" ] && [ "$self" != "$dest" ]; then
    install_copy "$self" || true
  fi
  # типичные копии на роутере
  for extra in /opt/root/nfqws-menu.sh /tmp/nfqws-menu.sh; do
    if [ -f "$extra" ] && [ "$extra" != "$self" ] && [ "$extra" != "$dest" ]; then
      install_copy "$extra" || true
    fi
  done

  rm -f "$tmp"

  # Запуск с канонического пути, если он есть
  local run="$dest"
  if [ ! -f "$run" ]; then
    run="$self"
  fi
  if [ ! -f "$run" ]; then
    error "Некуда сохранить скрипт — обновление не применено."
    return 1
  fi

  info "Перезапуск: $run (v$(extract_script_version "$run"))"
  # сбросить унаследованный SCRIPT_PATH, чтобы новый процесс определил путь сам
  unset SCRIPT_PATH
  export SCRIPT_PATH="$run"
  exec sh "$run"
}

# ---------------------------------------------------------------------------
# 10. dpi-detector (rust/4Mb) Pre-release
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
  info "dpi-detector (rust, ~4Mb) — Pre-release v4.0.0-rust"

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
# 11. Удаление пакетов
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

menu_remove() {
  echo
  printf '%s\n' "${BOLD}Удаление:${NC}"

  # Собираем список только установленных
  local items="" types=""
  is_installed "nfqws-keenetic"     && items="$items nfqws-keenetic"     && types="$types opkg"
  is_installed "nfqws2-keenetic"    && items="$items nfqws2-keenetic"    && types="$types opkg"
  is_installed "nfqws-keenetic-web" && items="$items nfqws-keenetic-web" && types="$types opkg"
  is_dpi_detector_installed         && items="$items dpi-detector"      && types="$types bin"

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
    printf '%s\n' "${BOLD}Меню:${NC}"
    echo "  1.  Установка NFQWS, NFQWS2"
    echo "  2.  Установка веб-интерфейса"
    echo "  3.  Установка стратегии"
    echo "  4.  Обновление IPSet List"
    echo "  5.  Обход блокировки DoT/DoH"
    echo "  10. dpi-detector (rust/4Mb) (Pre-release)"
    echo "  11. Удаление пакетов"
    echo "  99. Обновить скрипт"
    echo "  00. Выход"
    echo
    ask "Выберите пункт [Enter = выход]: "
    read -r choice

    case "$choice" in
      1)   menu_install_nfqws ;;
      2)   install_web ;;
      3)   menu_strategy ;;
      4)   update_ipset_list ;;
      5)   menu_dot_doh ;;
      10)  menu_dpi_detector ;;
      11)  menu_remove ;;
      99)  update_self ;;
      00|0|"")
        info "Выход."
        exit 0
        ;;
      *)  warn "Неверный пункт меню" ;;
    esac

    echo
    ask "Нажмите Enter для возврата в меню..."
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

if ! command -v opkg >/dev/null 2>&1; then
  error "opkg не найден. Скрипт предназначен для Entware (Keenetic/Netcraze)."
  exit 1
fi

main_menu
