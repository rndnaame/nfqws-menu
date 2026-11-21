#!/bin/sh
# installer_tgws_rs.sh — TG WS Proxy Rust (tg-ws-proxy-rs) для Entware (Keenetic)
# Репозиторий: https://github.com/rndnaame/nfqws-menu
# Upstream:    https://github.com/valnesfjord/tg-ws-proxy-rs
#
# Запуск:
#   sh installer_tgws_rs.sh
#   curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_tgws_rs.sh | sh
#
# Вызов из nfqws-menu (пункт 16):
#   run_menu_remote_sh "16" "TG WS Proxy Rust" "$TGWS_RS_INSTALL_URL" 2000

# ANSI (portable для ash/BusyBox)
if [ -t 1 ]; then
  ESC=$(printf '\033')
  RED="${ESC}[0;31m"
  GREEN="${ESC}[0;32m"
  YELLOW="${ESC}[1;33m"
  CYAN="${ESC}[0;36m"
  BOLD="${ESC}[1m"
  DIM="${ESC}[2m"
  NC="${ESC}[0m"
else
  RED= GREEN= YELLOW= CYAN= BOLD= DIM= NC=
fi

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[x]${NC} $*"; }
ask()   { printf '%s' "${CYAN}[?]${NC} $*"; }

read_menu() { read -r "$1"; }

confirm_yes() {
  ask "${1:-Continue?} [Y/n]: "
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

backup_file() {
  local f="$1" dest
  [ -f "$f" ] || return 0
  dest="${f}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "$f" "$dest" && info "Бэкап: $dest"
}

# Минимальная проверка opkg-пакета (без кэша меню)
is_installed() {
  opkg list-installed 2>/dev/null | grep -q "^$1 "
}

service_is_up() {
  case "$1" in
    tg-ws-proxy)
      ps w 2>/dev/null | grep -v grep | grep -q '[t]g-ws-proxy ' || \
        ps 2>/dev/null | grep -v grep | grep -q '[t]g-ws-proxy'
      ;;
    tg-ws-proxy-rs)
      ps w 2>/dev/null | grep -v grep | grep -q 'tg-ws-proxy-rs' || \
        ps 2>/dev/null | grep -v grep | grep -q 'tg-ws-proxy-rs'
      ;;
    *) return 1 ;;
  esac
}

# Порт слушается? (0 = занят, 1 = свободен) — как в nfqws-menu.sh
port_is_open() {
  local port="$1" ok=1
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]" && ok=0
  elif command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | grep -qE "[.:]${port}[[:space:]]" && ok=0
  elif [ -r /proc/net/tcp ]; then
    grep -q ":$(printf '%04X' "$port") " /proc/net/tcp 2>/dev/null && ok=0
  fi
  return "$ok"
}

# Подпись для ask (в меню задаётся ui_apply_lang)
: "${LBL_YOUR_CHOICE:=Ваш выбор}"

# Простое скачивание install.sh (с зеркалами raw.githubusercontent)
download_sh_validated() {
  local url="$1" dest="$2" min_bytes="${3:-1000}"
  local body alt
  rm -f "$dest"
  for alt in \
    "$url" \
    "https://ghproxy.net/${url}" \
    "https://cdn.jsdelivr.net/gh/$(echo "$url" | sed -n 's|https://raw.githubusercontent.com/\([^/]*\)/\([^/]*\)/\(.*\)|\1/\2@\3|p')"
  do
    [ -n "$alt" ] || continue
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout 10 --max-time 60 "$alt" -o "$dest" 2>/dev/null || continue
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$dest" -T 25 "$alt" 2>/dev/null || continue
    else
      error "Нужны curl или wget."
      return 1
    fi
    if [ -s "$dest" ]; then
      sz=$(wc -c < "$dest" | tr -d ' \r\n')
      if [ -n "$sz" ] && [ "$sz" -ge "$min_bytes" ] 2>/dev/null; then
        return 0
      fi
    fi
    rm -f "$dest"
  done
  return 1
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

# Бэкапы:
#  - config.conf.bak.* в /opt/etc/tg-ws-proxy-rs (подбор параметров)
#  - /opt/var/tg-ws-proxy-backups/install-* (upstream install.sh копирует бинарь)
# На Keenetic 3 копии install-* легко съедают 10–15 МБ флеша. Держим по 1.
TG_WS_PROXY_RS_BACKUP_ROOT="/opt/var/tg-ws-proxy-backups"

tg_ws_proxy_rs_prune_backups() {
  local dir="$TG_WS_PROXY_RS_CONF_DIR" root="$TG_WS_PROXY_RS_BACKUP_ROOT" keep=1 old n=0
  # config.bak — только последний
  if [ -d "$dir" ]; then
    # shellcheck disable=SC2012
    for old in $(ls -1 "$dir"/config.conf.bak.* 2>/dev/null | sort -r | tail -n +$((keep + 1))); do
      rm -f "$old"
      n=$((n + 1))
    done
  fi
  # install-* — полный бинарь; upstream keep=3 слишком жирно для Entware
  if [ -d "$root" ]; then
    # shellcheck disable=SC2012
    for old in $(ls -1d "$root"/install-* 2>/dev/null | sort -r | tail -n +$((keep + 1))); do
      rm -rf "$old"
      n=$((n + 1))
    done
  fi
  [ "$n" -gt 0 ] && info "Очищены старые бэкапы tg-ws-proxy ($n)."
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

# Запуск upstream install.sh. $1=script $2=upx_arg $3=GH_MIRROR (пусто = прямой GitHub).
# stdout — вывод установщика; return = его код.
tg_ws_proxy_rs_run_upstream() {
  local script="$1" upx_arg="$2" mirror="$3"
  if [ -n "$mirror" ]; then
    # upstream: dl() → $GH_MIRROR${url#https://github.com}
    # пример: https://ghproxy.net/https://github.com + /owner/repo/releases/...
    GH_MIRROR="$mirror" sh "$script" --platform entware $upx_arg 2>&1
  else
    # ash/BusyBox: без env -u; сбрасываем только в подshell
    ( unset GH_MIRROR; sh "$script" --platform entware $upx_arg ) 2>&1
  fi
}

tg_ws_proxy_rs_install() {
  local url="https://raw.githubusercontent.com/${TG_WS_PROXY_RS_REPO}/main/install.sh"
  local script="/tmp/tgws-install.$$.sh" out rc upx_arg='' bin_size size_text
  local mirror mirrors tried
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
  #
  # Upstream install.sh качает релиз с github.com; при DPI/блокировке нужен
  # GH_MIRROR (см. upstream README). Пробуем: прямой → пользовательский →
  # известные прокси.
  mirrors=""
  # если пользователь уже задал GH_MIRROR — пробуем его вторым (после прямого)
  [ -n "${GH_MIRROR:-}" ] && mirrors="$mirrors ${GH_MIRROR}"
  mirrors="$mirrors https://ghproxy.net/https://github.com"
  mirrors="$mirrors https://mirror.ghproxy.com/https://github.com"
  mirrors="$mirrors https://gh.ddlc.top/https://github.com"
  mirrors="$mirrors https://gitclone.com/github.com"

  tried=0
  rc=1
  out=""
  # 1) без зеркала
  out=$(tg_ws_proxy_rs_run_upstream "$script" "$upx_arg" "")
  rc=$?
  tried=$((tried + 1))
  # 2) зеркала, только если упало на скачивании архива
  if [ "$rc" -ne 0 ]; then
    case "$out" in
      *'cannot download'*|*'set GH_MIRROR'*|*'Failed to connect'*|*'Could not resolve'*)
        for mirror in $mirrors; do
          [ -n "$mirror" ] || continue
          warn "GitHub недоступен — повтор через зеркало: $mirror"
          out=$(tg_ws_proxy_rs_run_upstream "$script" "$upx_arg" "$mirror")
          rc=$?
          tried=$((tried + 1))
          [ "$rc" -eq 0 ] && break
        done
        ;;
    esac
  fi
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
    error "install.sh завершился с ошибкой (попыток: $tried)."
    warn "Задайте зеркало вручную: GH_MIRROR=https://ghproxy.net/https://github.com"
    warn "и повторите пункт 16, либо скачайте tar.gz с релизов и укажите --archive."
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
  tg_ws_proxy_rs_prune_backups || true
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
# Порядок перебора: сначала CF-first (не начинать с ws — долгий таймаут
# → клиент Telegram помечает прокси «неверным»). --default-domains нужен
# для cfproxy/cfworker без своего домена. Индекс 5 — запасной TLS-MITM.
tg_ws_proxy_rs_variant() {
  case "$1" in
    1) printf '%s|%s|%s\n' "$TG_WS_PROXY_RS_DC_TARGETS" \
         "--default-domains --pinned-upstream cfworker,cfproxy,ws,tcp" \
         "CF-first: cfworker → cfproxy → ws (рекомендуется)" ;;
    2) printf '%s|%s|%s\n' "$TG_WS_PROXY_RS_DC_TARGETS" \
         "--default-domains --pinned-upstream cfproxy,ws,tcp" \
         "cfproxy → ws → tcp" ;;
    3) printf '%s|%s|%s\n' "$TG_WS_PROXY_RS_DC_TARGETS" \
         "--default-domains --pinned-upstream ws,cfproxy,tcp" \
         "прямой WebSocket (ws → cfproxy → tcp)" ;;
    4) printf '%s|%s|%s\n' "$TG_WS_PROXY_RS_DC_TARGETS" \
         "--default-domains --pinned-upstream ws,cfproxy,tcp --fronting-domain $TG_WS_PROXY_RS_FRONTING_DOMAIN" \
         "прямой WebSocket с фронтингом SNI" ;;
    5) printf '%s|%s|%s\n' "$TG_WS_PROXY_RS_DC_TARGETS" \
         "--default-domains --cf-disable-tls --pinned-upstream cfproxy,ws" \
         "cfproxy по ws://:80 (TLS-MITM / CF TLS режется)" ;;
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
# запасной TLS-MITM (индекс 5) — отдельной строкой. Если обычные все FAIL, а
# fallback OK — он становится «быстрейшим» (раньше BEST был пуст и скрипт
# писал «ни один путь не ответил» при живом [5]).
tg_ws_proxy_rs_show_variants() {
  local rows normal fallback
  rows=$(printf '%s' "$TG_WS_PROXY_RS_RESULTS" | grep -v '^$')
  [ -n "$rows" ] || return 1
  normal=$(printf '%s\n' "$rows" | awk -F'|' '$1 != 5')
  fallback=$(printf '%s\n' "$rows" | awk -F'|' '$1 == 5')

  TG_WS_PROXY_RS_BEST_IDX=$(printf '%s\n' "$normal" \
    | awk -F'|' '$3 == "OK" { print $2 " " $1 }' \
    | sort -n | awk 'NR == 1 { print $2 }')
  # если обычные мертвы — взять fallback, если он OK
  if [ -z "$TG_WS_PROXY_RS_BEST_IDX" ] && [ -n "$fallback" ]; then
    TG_WS_PROXY_RS_BEST_IDX=$(printf '%s\n' "$fallback" \
      | awk -F'|' '$3 == "OK" { print $1; exit }')
  fi

  echo
  printf '%s\n' "${BOLD}Проверенные пути:${NC}"
  printf '%s\n' "$normal" | awk -F'|' -v best="$TG_WS_PROXY_RS_BEST_IDX" '
    {
      mark = ($1 == best) ? "   <- быстрейший" : ""
      if ($3 == "OK") printf "  [%d] OK   %5sms  %s%s\n", $1, $2, $4, mark
      else            printf "  [%d] FAIL         %s\n", $1, $4
    }'
  if [ -n "$fallback" ]; then
    echo
    printf '%s\n' "  запасной режим (TLS-MITM, метаданные идут открыто):"
    printf '%s\n' "$fallback" | awk -F'|' -v best="$TG_WS_PROXY_RS_BEST_IDX" '
      {
        mark = ($1 == best) ? "   <- быстрейший" : ""
        if ($3 == "OK") printf "  [%d] OK   %5sms  %s%s\n", $1, $2, $4, mark
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
    warn "Если CF/workers режет провайдер: добавьте cloudflare.com и workers.dev"
    warn "в hostlist nfqws2 (или свой --cf-domain в Cloudflare, SSL Flexible)."
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
    # подчистить install-* / config.bak, если накопились с прошлых прогонов
    tg_ws_proxy_rs_prune_backups 2>/dev/null || true
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
  # install-* с копиями бинаря — основной «пожиратель» флеша
  if [ -d "$TG_WS_PROXY_RS_BACKUP_ROOT" ]; then
    if confirm_yes "Удалить бэкапы установки ($TG_WS_PROXY_RS_BACKUP_ROOT)?"; then
      rm -rf "$TG_WS_PROXY_RS_BACKUP_ROOT"
      info "Бэкапы установки удалены."
    else
      tg_ws_proxy_rs_prune_backups || true
    fi
  fi
  return 0
}


# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------
if ! command -v opkg >/dev/null 2>&1; then
  error "opkg не найден. Скрипт для Entware (Keenetic/Netcraze)."
  exit 1
fi

# Если вызвали с аргументом remove — только удаление
case "${1:-}" in
  remove|uninstall)
    remove_tg_ws_proxy_rs
    exit $?
    ;;
esac

menu_tg_ws_proxy_rs
exit $?
