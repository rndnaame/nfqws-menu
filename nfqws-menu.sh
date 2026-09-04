#!/bin/sh
# nfqws-menu.sh — интерактивное меню установки/управления
# nfqws-keenetic / nfqws2-keenetic / nfqws-keenetic-web для Entware (Keenetic / Netcraze)
# Репозиторий стратегий: https://github.com/rndnaame/nfqws-menu

set -e

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

# Проверка необходимых blobs
check_blobs() {
  local ver="$1"
  local missing=0
  local f

  if [ "$ver" = "1" ]; then
    # nfqws v1: blobs обычно рядом с конфигом
    for f in \
      /opt/etc/nfqws/tls_clienthello.bin \
      /opt/etc/nfqws/quic_initial.bin
    do
      if [ -f "$f" ]; then
        info "blob OK: $f"
      else
        warn "blob отсутствует: $f"
        missing=1
      fi
    done
  else
    for f in \
      /opt/etc/nfqws2/blobs/tls_clienthello.bin \
      /opt/etc/nfqws2/blobs/quic_initial.bin
    do
      if [ -f "$f" ]; then
        info "blob OK: $f"
      else
        warn "blob отсутствует: $f"
        missing=1
      fi
    done
  fi

  if [ "$missing" -eq 1 ]; then
    warn "Часть blobs отсутствует. Стратегии с fake-пакетами могут не работать."
    ask "Скачать blobs из репозитория strategies/blobs/? [Y/n]: "
    read -r ans
    case "$ans" in
      n|N|н|Н) return 0 ;;
    esac
    download_blobs "$ver"
  fi
}

download_file() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -qO "$dest" "$url"
  fi
}

download_blobs() {
  local ver="$1"
  local base="${RAW_BASE}/strategies/blobs"
  local dest_dir
  if [ "$ver" = "1" ]; then
    dest_dir="/opt/etc/nfqws"
  else
    dest_dir="/opt/etc/nfqws2/blobs"
  fi
  mkdir -p "$dest_dir"
  for name in tls_clienthello.bin quic_initial.bin; do
    info "Скачивание $name ..."
    if download_file "${base}/${name}" "${dest_dir}/${name}"; then
      info "  → ${dest_dir}/${name}"
    else
      warn "  не удалось скачать $name (файл может отсутствовать в репозитории)"
    fi
  done
}

# Обновление lists из репозитория
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
    conf_path="${RAW_BASE}/strategies/nfqws1/${conf_name}"
  else
    conf_dest="/opt/etc/nfqws2/nfqws2.conf"
    conf_path="${RAW_BASE}/strategies/nfqws2/${conf_name}"
  fi

  if [ ! -f "$conf_dest" ]; then
    error "Конфиг $conf_dest не найден. Сначала установите соответствующий пакет."
    return 1
  fi

  info "Скачивание стратегии: $conf_name"
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
  check_blobs "$ver"

  echo
  ask "Обновить lists (user/exclude/ipset) из репозитория? [y/N]: "
  read -r ans
  case "$ans" in
    y|Y|д|Д) update_lists "$ver" ;;
    *) info "Списки не обновлялись." ;;
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

  local dir="nfqws${ver}"
  echo
  info "Доступные стратегии ($dir):"
  local list
  list=$(list_strategies "$dir")
  if [ -z "$list" ]; then
    warn "Список стратегий пуст или недоступен (проверьте интернет / репозиторий)."
    warn "Ожидаемые файлы: $REPO_URL/tree/main/strategies/$dir"
    return
  fi

  local i=1
  local files=""
  # shellcheck disable=SC2086
  for f in $list; do
    printf "  %2d) %s\n" "$i" "$f"
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
# 4. Удаление
# ---------------------------------------------------------------------------
menu_remove() {
  echo
  printf '%s\n' "${BOLD}Установленные компоненты:${NC}"
  local items=""
  is_installed "nfqws-keenetic"     && items="$items nfqws-keenetic"
  is_installed "nfqws2-keenetic"    && items="$items nfqws2-keenetic"
  is_installed "nfqws-keenetic-web" && items="$items nfqws-keenetic-web"

  if [ -z "$items" ]; then
    warn "Нечего удалять."
    return
  fi

  local i=1
  for p in $items; do
    printf "  %d) %s\n" "$i" "$p"
    i=$((i + 1))
  done
  echo "  a) Удалить всё"
  echo "  0) Назад"
  ask "Что удалить? (номер / a / 0): "
  read -r choice

  case "$choice" in
    0|"") return ;;
    a|A|а|А)
      ask "Точно удалить все пакеты NFQWS? [y/N]: "
      read -r ans
      case "$ans" in
        y|Y|д|Д)
          opkg remove --autoremove nfqws-keenetic-web nfqws2-keenetic nfqws-keenetic 2>/dev/null || true
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
      if [ -n "$target" ]; then
        ask "Удалить $target? [y/N]: "
        read -r ans
        case "$ans" in
          y|Y|д|Д)
            opkg remove --autoremove "$target"
            info "$target удалён."
            ;;
        esac
      else
        warn "Неверный выбор"
      fi
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
    printf '%s\n' "${BOLD}${BLUE}          NFQWS-MENU (Entware)          ${NC}"
    printf '%s\n' "${BOLD}${BLUE}========================================${NC}"
    echo
    detect_arch
    show_installed
    printf '%s\n' "${BOLD}Меню:${NC}"
    echo "  1. Установка NFQWS, NFQWS2"
    echo "  2. Установка веб-интерфейса"
    echo "  3. Установка стратегии"
    echo "  4. Удаление NFQWS, NFQWS2"
    echo "  00. Выход"
    echo
    ask "Выберите пункт [Enter = выход]: "
    read -r choice

    case "$choice" in
      1)  menu_install_nfqws ;;
      2)  install_web ;;
      3)  menu_strategy ;;
      4)  menu_remove ;;
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
if ! command -v opkg >/dev/null 2>&1; then
  error "opkg не найден. Скрипт предназначен для Entware (Keenetic/Netcraze)."
  exit 1
fi

main_menu
