#!/bin/sh
# telemt / telemt-panel — единый установщик (меню + telemt + panel)
# Репозиторий: https://github.com/rndnaame/nfqws-menu

set -e
set -o pipefail 2>/dev/null || true

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
YELLOW=$(printf '\033[1;33m')
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')

TELEMT_SYSTEMCTL_URL="${TELEMT_SYSTEMCTL_URL:-https://raw.githubusercontent.com/anch665/keendev/main/systemctl.sh}"
TELEMT_JOURNALCTL_URL="${TELEMT_JOURNALCTL_URL:-https://raw.githubusercontent.com/anch665/keendev/main/journalctl.sh}"

info()  { printf '%s\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%s\n' "${RED}[!]${NC} $*"; }
ask()   { printf '%s' "$*"; }

is_telemt_installed() {
    [ -x /opt/usr/bin/telemt ] || [ -x /opt/etc/init.d/S99telemt ] || \
        [ -d /opt/etc/telemt ] || [ -x /opt/sbin/telemt-panel ] || \
        [ -x /opt/etc/init.d/S99telemt-panel ] || [ -d /opt/etc/telemt-panel ]
}

_download() {
    _url="$1"
    _out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$_url" -o "$_out"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$_out" "$_url"
    else
        error "Нужны curl или wget"
        return 1
    fi
}

read_choice() {
    if [ -r /dev/tty ]; then
        read _ch < /dev/tty || _ch=""
    else
        read _ch || _ch=""
    fi
    printf '%s' "$_ch"
}

confirm_yes() {
    ask "$1 [y/N]: "
    _c=$(read_choice)
    case "$_c" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

install_telemt_systemd_emu() {
    echo
    info "Эмуляция systemD (systemctl / journalctl) для панели и логов"
    info "systemctl:  $TELEMT_SYSTEMCTL_URL"
    info "journalctl: $TELEMT_JOURNALCTL_URL"
    echo
    mkdir -p /opt/usr/bin
    if ! _download "$TELEMT_SYSTEMCTL_URL" /opt/usr/bin/systemctl; then
        error "Не удалось скачать systemctl"
        return 1
    fi
    if ! _download "$TELEMT_JOURNALCTL_URL" /opt/usr/bin/journalctl; then
        error "Не удалось скачать journalctl"
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

remove_telemt_all() {
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
    rm -rf /opt/tmp/telemt_dl /opt/tmp/telemt-panel-install
    rm -rf /tmp/telemt_dl /tmp/telemt-panel-dl
    rm -f /tmp/log/telemt.log
    rm -f /tmp/cache/beobachten.txt
    info "telemt / telemt-panel удалены."
}

# =============================================================================
# 1) telemt (вложенный subshell — exit не закрывает меню)
# =============================================================================
install_telemt_core() {
    echo
    info "Установка telemt"
    (
        set -e
        set -o pipefail 2>/dev/null || true
echo "=== Telemt installer for Entware (v3) ==="

# ANSI-цвета (printf — portable для ash/BusyBox)
RED=$(printf '\033[0;31m')
YELLOW=$(printf '\033[1;33m')
GREEN=$(printf '\033[0;32m')
BOLD=$(printf '\033[1m')
NC=$(printf '\033[0m')

CONFIG_DIR="/opt/etc/telemt"
CONFIG_FILE="$CONFIG_DIR/config.toml"
VERSION_FILE="$CONFIG_DIR/.version"
BIN_PATH="/opt/usr/bin/telemt"
INIT_SCRIPT="/opt/etc/init.d/S99telemt"
TMPDIR="/tmp/telemt_dl"

# --- Detect architecture (как в nfqws-menu.sh) ---
# На Keenetic uname -m для mips/mipsel часто врёт → сначала opkg / opkg.conf.
# mipsel* проверяем ДО mips*.

_arch_normalize() {
    case "$1" in
        aarch64*|arm64*)             echo "aarch64" ;;
        mipsel*|mipselsf*|mips64el*) echo "mipsel" ;;
        mips*|mipssf*)               echo "mips" ;;
        x86_64*|amd64*|x64*)         echo "x86_64" ;;
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
    name=$(grep -E '^[[:space:]]*arch[[:space:]]+' "$conf" 2>/dev/null | _arch_pick_best) || true
    if [ -n "$name" ]; then
        printf '%s\n' "$name"
        return 0
    fi
    from_url=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            src/gz*|src\ *)
                case "$line" in
                    *mipselsf*|*mips64el*|*mipsel*) from_url="mipsel"; break ;;
                    *mipssf*|*mips*)                from_url="mips"; break ;;
                    *aarch64*|*arm64*)              from_url="aarch64"; break ;;
                    *x86_64*|*amd64*)               from_url="x86_64"; break ;;
                esac
                ;;
        esac
    done < "$conf"
    [ -n "$from_url" ] && printf '%s\n' "$from_url"
}

detect_telemt_arch() {
    ARCH=""
    ARCH_RAW=""
    ARCH_SOURCE=""

    ARCH_RAW=$(_arch_from_opkg) || true
    ARCH=$(_arch_normalize "$ARCH_RAW")
    [ -n "$ARCH" ] && ARCH_SOURCE="opkg"

    if [ -z "$ARCH" ]; then
        ARCH_RAW=$(_arch_from_opkg_conf /opt/etc/opkg.conf) || true
        ARCH=$(_arch_normalize "$ARCH_RAW")
        [ -n "$ARCH" ] && ARCH_SOURCE="conf"
    fi

    # uname: mips/mipsel на Keenetic не доверяем
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
}

detect_telemt_arch

case "$ARCH" in
    aarch64)
        TELEMT_SOURCE="github"
        TELEMT_FILE="telemt-aarch64-linux-musl.tar.gz"
        ;;
    x86_64)
        TELEMT_SOURCE="github"
        TELEMT_FILE="telemt-x86_64-linux-musl.tar.gz"
        ;;
    mipsel)
        # GitHub releases без mipsel — ставим .ipk с test.entware (нет Packages.gz)
        TELEMT_SOURCE="ipk"
        TELEMT_IPK_BASE="https://test.entware.net/mipssf-k3.4/4test/le"
        TELEMT_IPK_ARCH="mipsel-3.4"
        TELEMT_FILE=""
        ;;
    mips)
        TELEMT_SOURCE="ipk"
        TELEMT_IPK_BASE="https://test.entware.net/mipssf-k3.4/4test/be"
        TELEMT_IPK_ARCH="mips-3.4"
        TELEMT_FILE=""
        ;;
    *)
        echo "ERROR: Unsupported or unknown architecture: '${ARCH:-?}' (raw=${ARCH_RAW:-?}, src=${ARCH_SOURCE:-none})"
        echo "uname -m: $(uname -m 2>/dev/null || true)"
        echo "opkg print-architecture:"
        opkg print-architecture 2>/dev/null || true
        echo "Supported: aarch64, x86_64, mipsel, mips"
        exit 1
        ;;
esac
if [ "$TELEMT_SOURCE" = "ipk" ]; then
    echo "Architecture: $ARCH → ipk from $TELEMT_IPK_BASE (detect: ${ARCH_SOURCE:-?}, raw: ${ARCH_RAW:-?})"
else
    echo "Architecture: $ARCH → $TELEMT_FILE (detect: ${ARCH_SOURCE:-?}, raw: ${ARCH_RAW:-?})"
fi

# --- Helpers ---

# Свободное место на /opt (kB). $1 = минимум kB
check_opt_space() {
    _need_kb="${1:-11000}"
    _avail=$(df -k /opt 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -z "$_avail" ] || ! [ "$_avail" -ge 0 ] 2>/dev/null; then
        _avail=$(df -P -k /opt 2>/dev/null | awk 'NR==2 {print $4}')
    fi
    if [ -z "$_avail" ] || ! [ "$_avail" -ge 0 ] 2>/dev/null; then
        echo "WARNING: не удалось определить свободное место на /opt"
        df -h /opt 2>/dev/null || true
        return 0
    fi
    echo "Свободно на /opt: ${_avail} kB (нужно ≥ ${_need_kb} kB)"
    if [ "$_avail" -lt "$_need_kb" ]; then
        echo ""
        printf '%s\n' "${RED}ERROR: недостаточно места на /opt${NC}"
        echo "  Доступно: ${_avail} kB"
        echo "  Требуется: ≥ ${_need_kb} kB"
        echo "  Освободите место (логи, старые пакеты, /opt/tmp) и повторите."
        echo ""
        df -h /opt 2>/dev/null || df -h 2>/dev/null || true
        return 1
    fi
    return 0
}

get_local_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" 2>/dev/null | head -n1 | tr -d ' \r\n'
        return
    fi
    if [ -x "$BIN_PATH" ]; then
        ver=$("$BIN_PATH" --version 2>/dev/null | head -n1 | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
        if [ -n "$ver" ]; then
            echo "$ver"
            return
        fi
    fi
    echo ""
}

_http_get() {
    if command -v wget >/dev/null 2>&1; then
        wget -qO- "$1" 2>/dev/null
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" 2>/dev/null
    fi
}

# latest telemt_X.Y.Z-N_<arch>.ipk из directory listing (без Packages.gz)
get_latest_ipk_meta() {
    # выставляет: LATEST_VER, LATEST_IPK_NAME, LATEST_IPK_URL
    LATEST_VER=""
    LATEST_IPK_NAME=""
    LATEST_IPK_URL=""
    html=$(_http_get "$TELEMT_IPK_BASE/") || true
    [ -n "$html" ] || return 1
    # telemt_3.5.7-1_mipsel-3.4.ipk
    names=$(printf '%s\n' "$html" | grep -oE "telemt_[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+_${TELEMT_IPK_ARCH}\\.ipk" | sort -u) || true
    [ -n "$names" ] || return 1
    # выбрать максимальный X.Y.Z-N (portable, без sort -V)
    best_name=""
    best_a=0; best_b=0; best_c=0; best_r=0
    for n in $names; do
        ver=$(printf '%s\n' "$n" | sed -n "s/^telemt_\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)-.*/\1/p")
        rev=$(printf '%s\n' "$n" | sed -n "s/^telemt_[0-9.]*-\([0-9][0-9]*\)_.*/\1/p")
        a=$(echo "$ver" | cut -d. -f1)
        b=$(echo "$ver" | cut -d. -f2)
        c=$(echo "$ver" | cut -d. -f3)
        r=${rev:-0}
        newer=0
        if [ "$a" -gt "$best_a" ] 2>/dev/null; then newer=1
        elif [ "$a" -eq "$best_a" ] 2>/dev/null; then
            if [ "$b" -gt "$best_b" ] 2>/dev/null; then newer=1
            elif [ "$b" -eq "$best_b" ] 2>/dev/null; then
                if [ "$c" -gt "$best_c" ] 2>/dev/null; then newer=1
                elif [ "$c" -eq "$best_c" ] 2>/dev/null && [ "$r" -gt "$best_r" ] 2>/dev/null; then newer=1
                fi
            fi
        fi
        if [ -z "$best_name" ] || [ "$newer" -eq 1 ]; then
            best_name="$n"
            best_a=$a; best_b=$b; best_c=$c; best_r=$r
            LATEST_VER="$ver"
        fi
    done
    [ -n "$best_name" ] || return 1
    LATEST_IPK_NAME="$best_name"
    LATEST_IPK_URL="$TELEMT_IPK_BASE/$best_name"
    return 0
}

get_latest_version() {
    ver=""
    if [ "${TELEMT_SOURCE:-github}" = "ipk" ]; then
        if get_latest_ipk_meta; then
            echo "$LATEST_VER"
            return 0
        fi
        echo ""
        return 0
    fi
    ver=$(_http_get https://api.github.com/repos/telemt/telemt/releases/latest | \
        grep '"tag_name"' | head -n1 | cut -d '"' -f 4) || true
    echo "$ver"
}

ensure_deps() {
    # $1 = force (1 = всегда opkg update, 0 = только если чего-то не хватает)
    _force="${1:-0}"
    _need=0
    command -v openssl >/dev/null 2>&1 || _need=1
    command -v jq >/dev/null 2>&1 || _need=1
    command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || _need=1
    if [ "$_force" = "1" ] || [ "$_need" -eq 1 ]; then
        echo "Установка/проверка зависимостей..."
        opkg update
        opkg install openssl-util 2>/dev/null || true
        opkg install jq 2>/dev/null || true
        opkg install wget-ssl 2>/dev/null || opkg install wget 2>/dev/null || true
    fi
}

telemt_is_running() {
    if [ -x "$INIT_SCRIPT" ]; then
        out=$("$INIT_SCRIPT" check 2>/dev/null) || true
        echo "$out" | grep -qi alive && return 0
    fi
    pidof telemt >/dev/null 2>&1 && return 0
    return 1
}

init_script_ok() {
    [ -x "$INIT_SCRIPT" ] || return 1
    # в файле литералы $LOG_FILE / $PROCS (heredoc с кавычками)
    grep -qF 'ARGS="--log-file $LOG_FILE /opt/etc/$PROCS/config.toml"' "$INIT_SCRIPT" 2>/dev/null
}

install_init_script() {
    mkdir -p /opt/etc/init.d /tmp/log /tmp/cache /opt/var/run
    cat > "$INIT_SCRIPT" <<'EOF'
#!/bin/sh

ENABLED=yes
PROCS=telemt
LOG_FILE="/tmp/log/telemt.log"
ARGS="--log-file $LOG_FILE /opt/etc/$PROCS/config.toml"
PREARGS=""
DESC="Telemt MTProxy"
PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
EOF
    chmod +x "$INIT_SCRIPT"
}

download_and_install_binary() {
    _ver="$1"
    mkdir -p "$TMPDIR" /opt/usr/bin "$CONFIG_DIR"

    if [ "${TELEMT_SOURCE:-github}" = "ipk" ]; then
        # mips/mipsel: .ipk с test.entware (нет Packages.gz)
        # config.toml в conffiles — opkg не перезапишет существующий
        if [ -z "${LATEST_IPK_URL:-}" ] || [ -z "${LATEST_IPK_NAME:-}" ]; then
            get_latest_ipk_meta || true
        fi
        if [ -z "${LATEST_IPK_URL:-}" ]; then
            echo "ERROR: не найден telemt_*.ipk в $TELEMT_IPK_BASE/"
            return 1
        fi
        echo "Downloading Telemt ipk $_ver..."
        echo "  $LATEST_IPK_URL"
        # /tmp обычно tmpfs — не жрём место на /opt
        IPK_PATH="/tmp/telemt_$$.ipk"
        if command -v wget >/dev/null 2>&1; then
            wget -O "$IPK_PATH" "$LATEST_IPK_URL" || { rm -f "$IPK_PATH"; return 1; }
        else
            curl -fL -o "$IPK_PATH" "$LATEST_IPK_URL" || { rm -f "$IPK_PATH"; return 1; }
        fi
        echo "opkg install $IPK_PATH ..."
        # --force-reinstall: обновить уже стоящий пакет; conffiles сохранят config.toml
        if ! opkg install --force-reinstall "$IPK_PATH"; then
            echo "opkg install --force-reinstall failed, trying plain install..."
            if ! opkg install "$IPK_PATH"; then
                echo "ERROR: opkg install failed (мало места на /opt? df -h /opt)"
                rm -f "$IPK_PATH"
                return 1
            fi
        fi
        rm -f "$IPK_PATH"
        if [ ! -x "$BIN_PATH" ]; then
            # на всякий случай — путь из пакета
            if [ -x /opt/usr/bin/telemt ]; then
                BIN_PATH=/opt/usr/bin/telemt
            else
                echo "ERROR: telemt binary missing after opkg install"
                return 1
            fi
        fi
        mkdir -p "$CONFIG_DIR"
        echo "$_ver" > "$VERSION_FILE"
        echo "Package installed: telemt $_ver [opkg/ipk]"
        return 0
    fi

    echo "Downloading Telemt $_ver ($TELEMT_FILE)..."
    TARBALL_URL="https://github.com/telemt/telemt/releases/download/${_ver}/${TELEMT_FILE}"
    TARBALL_PATH="$TMPDIR/telemt.tar.gz"
    echo "  $TARBALL_URL"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$TARBALL_PATH" "$TARBALL_URL" || return 1
    else
        curl -fL -o "$TARBALL_PATH" "$TARBALL_URL" || return 1
    fi
    echo "Extracting..."
    tar -xzf "$TARBALL_PATH" -C "$TMPDIR"
    TELEMT_BIN=$(find "$TMPDIR" -maxdepth 2 -type f -name telemt 2>/dev/null | head -n 1)
    if [ -z "$TELEMT_BIN" ]; then
        echo "ERROR: telemt binary not found in archive!"
        rm -rf "$TMPDIR"
        return 1
    fi
    cp "$TELEMT_BIN" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    echo "$_ver" > "$VERSION_FILE"
    echo "Binary installed: $BIN_PATH ($_ver)"
    rm -rf "$TMPDIR"
    return 0
}

start_telemt() {
    mkdir -p /tmp/log /tmp/cache
    if [ -x "$INIT_SCRIPT" ]; then
        if "$INIT_SCRIPT" restart; then
            echo "Telemt started OK."
            return 0
        fi
    fi
    echo "WARNING: init start reported failure. Checking manually..."
    "$BIN_PATH" --log-file /tmp/log/telemt.log "$CONFIG_FILE" >/tmp/log/telemt-start.err 2>&1 &
    TPID=$!
    sleep 2
    if kill -0 "$TPID" 2>/dev/null; then
        echo "Process is running (pid $TPID)."
        return 0
    fi
    echo "Manual start also failed. Last errors:"
    tail -n 40 /tmp/log/telemt-start.err 2>/dev/null || true
    tail -n 40 /tmp/log/telemt.log 2>/dev/null || true
    return 1
}


sync_telemt_panel() {
    PANEL_CFG="/opt/etc/telemt-panel/config.toml"
    PANEL_INIT="/opt/etc/init.d/S99telemt-panel"
    [ -f "$PANEL_CFG" ] || return 0
    [ -f "$CONFIG_FILE" ] || return 0

    echo "Проверка связи telemt-panel ↔ telemt..."

    # auth_header / listen из [server.api] — значение после "=", кавычки снимаем
    TM_AUTH=$(awk '
        /^\[server\.api\]/ { inapi=1; next }
        /^\[/ { inapi=0 }
        inapi && $0 ~ /^[[:space:]]*auth_header[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/["'\'' ]/, "")
            print
            exit
        }
    ' "$CONFIG_FILE" 2>/dev/null) || true

    TM_LISTEN=$(awk '
        /^\[server\.api\]/ { inapi=1; next }
        /^\[/ { inapi=0 }
        inapi && $0 ~ /^[[:space:]]*listen[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/["'\'' ]/, "")
            print
            exit
        }
    ' "$CONFIG_FILE" 2>/dev/null) || true
    TM_LISTEN=${TM_LISTEN:-127.0.0.1:9091}
    case "$TM_LISTEN" in
        *://*) TM_URL="$TM_LISTEN" ;;
        *) TM_URL="http://$TM_LISTEN" ;;
    esac

    TM_BIN="$BIN_PATH"

    if [ -z "$TM_AUTH" ]; then
        echo "WARNING: auth_header не найден в $CONFIG_FILE — panel не синхронизируем"
        return 0
    fi

    # текущие значения panel
    PN_AUTH=$(awk '
        /^\[telemt\]/ { insec=1; next }
        /^\[/ { insec=0 }
        insec && $0 ~ /^[[:space:]]*auth_header[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, ""); gsub(/["'\'' ]/, ""); print; exit
        }
    ' "$PANEL_CFG" 2>/dev/null) || true
    PN_URL=$(awk '
        /^\[telemt\]/ { insec=1; next }
        /^\[/ { insec=0 }
        insec && $0 ~ /^[[:space:]]*url[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, ""); gsub(/["'\'' ]/, ""); print; exit
        }
    ' "$PANEL_CFG" 2>/dev/null) || true
    PN_BIN=$(awk '
        /^\[telemt\]/ { insec=1; next }
        /^\[/ { insec=0 }
        insec && $0 ~ /^[[:space:]]*binary_path[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, ""); gsub(/["'\'' ]/, ""); print; exit
        }
    ' "$PANEL_CFG" 2>/dev/null) || true

    NEED=0
    [ "$PN_AUTH" != "$TM_AUTH" ] && NEED=1
    [ "$PN_URL" != "$TM_URL" ] && NEED=1
    [ "$PN_BIN" != "$TM_BIN" ] && NEED=1

    if [ "$NEED" -eq 0 ]; then
        echo "telemt-panel: url/auth_header/binary_path уже совпадают с telemt"
        return 0
    fi

    echo "telemt-panel: обновляем [telemt] секцию..."
    echo "  url:          ${PN_URL:-<empty>} → $TM_URL"
    echo "  auth_header:  ${PN_AUTH:-<empty>} → $TM_AUTH"
    echo "  binary_path:  ${PN_BIN:-<empty>} → $TM_BIN"

    # правка через awk: если секция [telemt] есть — обновить поля; иначе дописать
    PANEL_TMP="${PANEL_CFG}.tmp.$$"
    awk -v url="$TM_URL" -v auth="$TM_AUTH" -v bin="$TM_BIN" '
        BEGIN { insec=0; done_url=0; done_auth=0; done_bin=0; has_sec=0 }
        /^\[telemt\]/ {
            print
            insec=1; has_sec=1
            next
        }
        /^\[/ {
            if (insec) {
                if (!done_url)  print "url = \"" url "\""
                if (!done_auth) print "auth_header = \"" auth "\""
                if (!done_bin)  print "binary_path = \"" bin "\""
                insec=0
            }
            print
            next
        }
        insec && /^url[[:space:]]*=/ {
            print "url = \"" url "\""
            done_url=1
            next
        }
        insec && /^auth_header[[:space:]]*=/ {
            print "auth_header = \"" auth "\""
            done_auth=1
            next
        }
        insec && /^binary_path[[:space:]]*=/ {
            print "binary_path = \"" bin "\""
            done_bin=1
            next
        }
        { print }
        END {
            if (insec) {
                if (!done_url)  print "url = \"" url "\""
                if (!done_auth) print "auth_header = \"" auth "\""
                if (!done_bin)  print "binary_path = \"" bin "\""
            } else if (!has_sec) {
                print ""
                print "[telemt]"
                print "url = \"" url "\""
                print "auth_header = \"" auth "\""
                print "binary_path = \"" bin "\""
            }
        }
    ' "$PANEL_CFG" > "$PANEL_TMP" && mv "$PANEL_TMP" "$PANEL_CFG"

    if [ -x "$PANEL_INIT" ]; then
        echo "Перезапуск telemt-panel..."
        "$PANEL_INIT" restart >/dev/null 2>&1 || "$PANEL_INIT" start >/dev/null 2>&1 || true
        echo "telemt-panel restart done."
    else
        echo "WARNING: $PANEL_INIT не найден — перезапустите panel вручную"
    fi
}

# --- Existing install detection ---
HAS_CONFIG=0
HAS_BIN=0
[ -f "$CONFIG_FILE" ] && HAS_CONFIG=1
[ -x "$BIN_PATH" ] && HAS_BIN=1

# Для проверки версии нужен wget/curl; тяжёлый opkg update — только если чего-то нет
ensure_deps 0

LOCAL_VER=$(get_local_version)
if [ "${TELEMT_SOURCE:-github}" = "ipk" ]; then
    echo "Detecting latest Telemt version from $TELEMT_IPK_BASE ..."
else
    echo "Detecting latest Telemt version from GitHub..."
fi
LATEST_VER=$(get_latest_version)
if [ -z "$LATEST_VER" ]; then
    echo "WARNING: не удалось получить latest с GitHub, пробуем с обновлением зависимостей..."
    ensure_deps 1
    LATEST_VER=$(get_latest_version)
fi
if [ -z "$LATEST_VER" ]; then
    echo "ERROR: Cannot detect latest Telemt version!"
    exit 1
fi
echo "Latest version: $LATEST_VER"
[ -n "$LOCAL_VER" ] && echo "Installed version: $LOCAL_VER" || echo "Installed version: (none)"

# Сразу после определения версии — проверка места (перед любой установкой/обновлением)
# Пропускаем только если бинарник уже актуален
if ! [ -n "$LOCAL_VER" ] || [ "$LOCAL_VER" != "$LATEST_VER" ] || [ ! -x "$BIN_PATH" ]; then
    check_opt_space 11000 || exit 1
fi

# =====================================================================
# UPDATE PATH: config already exists — preserve it, only update binary
# =====================================================================
if [ "$HAS_CONFIG" -eq 1 ]; then
    echo ""
    echo "Найден существующий конфиг: $CONFIG_FILE"
    echo "Настройки сохраняются без изменений."

    if [ -n "$LOCAL_VER" ] && [ "$LOCAL_VER" = "$LATEST_VER" ] && [ "$HAS_BIN" -eq 1 ]; then
        echo "Уже установлена актуальная версия ($LOCAL_VER)."
        mkdir -p "$CONFIG_DIR"
        echo "$LOCAL_VER" > "$VERSION_FILE"
        # init только если отсутствует/устарел (со старым -d)
        if ! init_script_ok; then
            echo "Обновление init-скрипта..."
            install_init_script
        fi
        if telemt_is_running; then
            echo "Telemt уже запущен — restart не требуется."
        else
            echo "Telemt не запущен — стартуем..."
            start_telemt || true
        fi
        echo ""
        echo "=== Telemt up-to-date ($LOCAL_VER) ==="
        echo "Config: $CONFIG_FILE"
        echo "Log: /tmp/log/telemt.log"
        sync_telemt_panel || true
        exit 0
    fi

    # Нужно обновление бинарника — зависимости на всякий случай
    ensure_deps 1
    echo "Обновление бинарника: ${LOCAL_VER:-unknown} → $LATEST_VER"
    if [ -x "$INIT_SCRIPT" ]; then
        echo "Stopping Telemt..."
        "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
    fi

    if ! download_and_install_binary "$LATEST_VER"; then
        echo "ERROR: failed to download/install binary"
        start_telemt || true
        exit 1
    fi

    install_init_script
    start_telemt || true

    echo ""
    echo "=== Telemt updated to $LATEST_VER ==="
    echo "Config preserved: $CONFIG_FILE"
    echo "Log: /tmp/log/telemt.log"
    sync_telemt_panel || true
    exit 0
fi

# =====================================================================
# FRESH INSTALL PATH: no config — interactive setup
# =====================================================================
echo ""
echo "Конфиг не найден — полная установка."
ensure_deps 1

echo "Detecting default route interface..."

# НЕ используем «ip route get 1.1.1.1» — на Keenetic часто уходит в WARP/WG
# (host-route 1.1.1.1 → nwg*), хотя default — ppp0.
DEF_IFACE=$(ip -4 route show default 2>/dev/null | awk '
    /^default/ {
        for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }
    }
')
if [ -z "$DEF_IFACE" ]; then
    DEF_IFACE=$(ip route 2>/dev/null | awk '
        /^default/ {
            for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }
        }
    ')
fi
if [ -z "$DEF_IFACE" ]; then
    # fallback: route -n
    DEF_IFACE=$(route -n 2>/dev/null | awk '$1 == "0.0.0.0" { print $NF; exit }')
fi
if [ -z "$DEF_IFACE" ]; then
    echo "ERROR: Cannot detect default route interface!"
    exit 1
fi
case "$DEF_IFACE" in
    *@*) DEF_IFACE=$(echo "$DEF_IFACE" | cut -d'@' -f1) ;;
esac
echo "Default route interface: $DEF_IFACE"

# IP с интерфейса default route (не src из route get 1.1.1.1)
AUTO_IP=$(ip -4 -o addr show dev "$DEF_IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | awk '!/^127\./ {print; exit}')
if [ -z "$AUTO_IP" ]; then
    AUTO_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
fi
if [ -z "$AUTO_IP" ]; then
    echo "ERROR: Cannot detect WAN IP on $DEF_IFACE!"
    exit 1
fi
echo "Detected WAN IP ($DEF_IFACE): $AUTO_IP"

echo "Detecting TLS domain (ACME / netcraze.io)..."
AUTO_DOMAIN=$(ndmc -c 'ip http ssl acme list' 2>/dev/null | grep "domain:" | awk '{print $2}' | grep "netcraze.io" | head -n 1) || true
if [ -z "$AUTO_DOMAIN" ]; then
    AUTO_DOMAIN=$(ndmc -c 'ip http ssl acme list' 2>/dev/null | grep "domain:" | awk '{print $2}' | head -n 1) || true
fi
# telemt требует непустой валидный домен (fake-TLS / mask)
DEFAULT_TLS_DOMAIN="${AUTO_DOMAIN:-vk.com}"
echo "Suggested TLS domain: $DEFAULT_TLS_DOMAIN"

printf "Enter port (default 1443): "
read PORT || true
PORT=${PORT:-1443}

printf "Enter listen IP (default 0.0.0.0, detected WAN $AUTO_IP): "
read LISTEN_IP || true
LISTEN_IP=${LISTEN_IP:-0.0.0.0}
case "$LISTEN_IP" in
    *[!0-9a-fA-F:.]*|"")
        echo "WARNING: '$LISTEN_IP' is not a valid IP, using 0.0.0.0"
        LISTEN_IP="0.0.0.0"
        ;;
    *.*|*:*) ;;
    *)
        echo "WARNING: '$LISTEN_IP' is not a valid IP, using 0.0.0.0"
        LISTEN_IP="0.0.0.0"
        ;;
esac

printf "Enter public host for links (IP or domain, default $AUTO_IP): "
read PUBLIC_HOST || true
PUBLIC_HOST=${PUBLIC_HOST:-$AUTO_IP}

# TLS domain обязателен — пустая строка ломает запуск telemt
_is_valid_domain() {
    case "$1" in
        ""|*[!a-zA-Z0-9.-]*|.*|*..*|*.) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}
while true; do
    printf "Enter TLS domain (default %s): " "$DEFAULT_TLS_DOMAIN"
    read TLS_DOMAIN || true
    TLS_DOMAIN=${TLS_DOMAIN:-$DEFAULT_TLS_DOMAIN}
    TLS_DOMAIN=$(printf '%s' "$TLS_DOMAIN" | tr -d ' \t\r')
    if _is_valid_domain "$TLS_DOMAIN"; then
        break
    fi
    echo "ERROR: нужен валидный домен (например vk.com, google.com). Пустое значение нельзя."
done
echo "TLS domain: $TLS_DOMAIN"

printf "Enter username (default user1): "
read USERNAME || true
USERNAME=${USERNAME:-user1}

echo ""
echo "Режим read_only API (telemt):"
echo "  1 — (true)  только чтение: статистика и просмотр конфига в панели"
echo "  2 — (false) полный доступ API: пользователи, секреты, управление"
printf "Включить режим только чтения? (1/2, по умолчанию: 1): "
read READONLY || true
READONLY=${READONLY:-1}
case "$READONLY" in
    1|y|Y) READONLY_FLAG=true ;;
    2|n|N) READONLY_FLAG=false ;;
    *) echo "Неверный ввод, оставляем read-only = true"; READONLY_FLAG=true ;;
esac
echo "API read_only: $READONLY_FLAG"

echo "Generating HEX16 secret..."
USER_SECRET=$(openssl rand -hex 16)
echo "Generated secret: $USER_SECRET"

echo "Generating API auth_header..."
AUTH_HEADER=$(openssl rand -hex 32)
echo "Generated auth_header: $AUTH_HEADER"

echo "Выберите интерфейс, через который прокси будет выходить в мир"
echo "(рекомендуется: $DEF_IFACE — default route)"

_is_junk_iface() {
    case "$1" in
        lo|sit*|ip6tnl*|tunl*|gre*|gretap*|ethoip*|dummy*|ezcfg*|ntce*|xfrms*)
            return 0 ;;
        ra*|rai*|apcli*|apclii*)
            return 0 ;;
        br[0-9]*)
            # LAN bridge — не для upstream
            return 0 ;;
        *)
            return 1 ;;
    esac
}

_get_ipv4() {
    ip -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | \
        awk '!/^127\./ {print; exit}'
}

# RCI: description по IPv4 (http://127.0.0.1:79/rci/show/interface)
_RCI_DESC_FILE="/tmp/telemt_rci_iface_desc.$$"
rm -f "$_RCI_DESC_FILE"
_rci_json=""
if command -v curl >/dev/null 2>&1; then
    _rci_json=$(curl -s --connect-timeout 2 --max-time 4 "http://127.0.0.1:79/rci/show/interface" 2>/dev/null) || true
elif command -v wget >/dev/null 2>&1; then
    _rci_json=$(wget -qO- -T 4 "http://127.0.0.1:79/rci/show/interface" 2>/dev/null) || true
fi
if [ -n "$_rci_json" ] && command -v jq >/dev/null 2>&1; then
    # address|description (или interface-name / id)
    printf '%s\n' "$_rci_json" | jq -r '
        .. | objects |
        select(has("address") and (.address | type == "string") and (.address | test("^[0-9]+\\."))) |
        "\(.address)|\(if (.description // "") != "" then .description
            elif (.["interface-name"] // "") != "" then .["interface-name"]
            else (.id // "") end)"
    ' 2>/dev/null | while IFS= read -r _line; do
        [ -n "$_line" ] && printf '%s\n' "$_line"
    done > "$_RCI_DESC_FILE" || true
elif [ -n "$_rci_json" ]; then
    # без jq: грубый разбор пар address + ближайший description
    printf '%s\n' "$_rci_json" | awk '
        /"address"[[:space:]]*:[[:space:]]*"[0-9]+\./ {
            if (match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
                addr = substr($0, RSTART, RLENGTH)
            }
        }
        /"description"[[:space:]]*:/ {
            if (match($0, /"description"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
                line = substr($0, RSTART, RLENGTH)
                sub(/.*"description"[[:space:]]*:[[:space:]]*"/, "", line)
                sub(/".*/, "", line)
                desc = line
            }
        }
        /"interface-name"[[:space:]]*:/ {
            if (desc == "" && match($0, /"interface-name"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
                line = substr($0, RSTART, RLENGTH)
                sub(/.*"interface-name"[[:space:]]*:[[:space:]]*"/, "", line)
                sub(/".*/, "", line)
                iname = line
            }
        }
        /^[[:space:]]*\}/ {
            if (addr != "") {
                d = desc
                if (d == "") d = iname
                if (d != "") print addr "|" d
            }
            addr = ""; desc = ""; iname = ""
        }
    ' > "$_RCI_DESC_FILE" 2>/dev/null || true
fi

_get_rci_desc() {
    _ip="$1"
    [ -n "$_ip" ] && [ -f "$_RCI_DESC_FILE" ] || { echo ""; return 0; }
    awk -F'|' -v ip="$_ip" '$1 == ip { print $2; exit }' "$_RCI_DESC_FILE" 2>/dev/null
}

_IFACE_LIST=""
_IFACE_HAS_DEF=0
_raw_list=$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1 | tr '\n' ' ') || true
for _raw in $_raw_list; do
    [ -n "$_raw" ] || continue
    if _is_junk_iface "$_raw"; then
        continue
    fi
    _ip4=$(_get_ipv4 "$_raw") || true
    [ -n "$_ip4" ] || continue
    if [ "$_raw" = "$DEF_IFACE" ]; then
        _IFACE_HAS_DEF=1
        _IFACE_LIST="$_raw $_IFACE_LIST"
    else
        _IFACE_LIST="$_IFACE_LIST $_raw"
    fi
done
if [ "$_IFACE_HAS_DEF" -eq 0 ] && [ -n "$DEF_IFACE" ]; then
    _IFACE_LIST="$DEF_IFACE $_IFACE_LIST"
fi
_IFACE_LIST=$(echo "$_IFACE_LIST" | awk '{for(i=1;i<=NF;i++) if(!seen[$i]++) printf "%s%s", (n++?" ":""), $i}')

echo "Доступные интерфейсы (UP + IPv4):"
i=1
for iface in $_IFACE_LIST; do
    [ -n "$iface" ] || continue
    _ip4=$(_get_ipv4 "$iface") || true
    _desc=$(_get_rci_desc "$_ip4") || true
    _mark=""
    [ "$iface" = "$DEF_IFACE" ] && _mark=" ← default route"
    _extra=""
    [ -n "$_desc" ] && _extra=" — $_desc"
    if [ -n "$_ip4" ]; then
        echo "  $i) $iface ($_ip4)$_extra$_mark"
    else
        echo "  $i) $iface$_extra$_mark"
    fi
    eval "iface_$i=\$iface"
    i=$((i+1))
done
rm -f "$_RCI_DESC_FILE" 2>/dev/null || true

COUNT=$((i-1))
if [ "$COUNT" -lt 1 ]; then
    echo "WARNING: не найдено подходящих интерфейсов, используем $DEF_IFACE"
    UP_IFACE="$DEF_IFACE"
else
    printf "Интерфейс (номер 1-%s или имя, по умолчанию 1 = %s): " "$COUNT" "$DEF_IFACE"
    read IFSEL || true
    IFSEL=$(echo "${IFSEL:-1}" | tr -d ' \t\r')
    UP_IFACE=""
    # число из списка
    if [ "$IFSEL" -ge 1 ] 2>/dev/null && [ "$IFSEL" -le "$COUNT" ] 2>/dev/null; then
        eval "UP_IFACE=\$iface_$IFSEL"
    else
        # имя интерфейса (eth3, ppp0, nwg1, ...)
        case "$IFSEL" in
            *@*) IFSEL=$(echo "$IFSEL" | cut -d'@' -f1) ;;
        esac
        # есть в нашем списке?
        for iface in $_IFACE_LIST; do
            if [ "$iface" = "$IFSEL" ]; then
                UP_IFACE="$IFSEL"
                break
            fi
        done
        # вручную: проверяем существование в системе
        if [ -z "$UP_IFACE" ]; then
            if ip link show dev "$IFSEL" >/dev/null 2>&1; then
                UP_IFACE="$IFSEL"
                echo "Интерфейс $UP_IFACE принят (вне списка)."
            else
                echo "Интерфейс '$IFSEL' не найден — используем default: $DEF_IFACE"
                UP_IFACE="$DEF_IFACE"
            fi
        fi
    fi
fi
UP_IFACE=${UP_IFACE:-$DEF_IFACE}
# финальная проверка
if ! ip link show dev "$UP_IFACE" >/dev/null 2>&1; then
    echo "ERROR: интерфейс '$UP_IFACE' не существует в системе!"
    exit 1
fi
echo "Selected interface: $UP_IFACE"

while true; do
    echo "Checking if port $PORT is free..."
    if netstat -tuln 2>/dev/null | grep -E "[:.]$PORT\b" >/dev/null 2>&1; then
        echo "Port $PORT is already in use!"
        printf "Enter another port: "
        read PORT || true
    else
        echo "Port OK."
        break
    fi
done

echo "Checking domain resolution ($TLS_DOMAIN)..."
if [ -z "$TLS_DOMAIN" ]; then
    echo "ERROR: TLS domain пустой — установка прервана."
    exit 1
fi
if ! nslookup "$TLS_DOMAIN" 2>/dev/null | grep -q 'Address'; then
    echo "WARNING: Domain $TLS_DOMAIN does not resolve (для fake-TLS это часто нормально)."
    echo "Press Enter to continue or Ctrl+C to abort."
    read _ || true
else
    echo "Domain OK."
fi

echo "=== Installing Telemt $LATEST_VER ==="
if [ -x "$INIT_SCRIPT" ]; then
    "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
fi
download_and_install_binary "$LATEST_VER" || exit 1
install_init_script

mkdir -p "$CONFIG_DIR/tlsfront" /tmp/log /tmp/cache
cd "$CONFIG_DIR"

echo "Writing config.toml..."

cat > config.toml <<EOF
[general]
use_middle_proxy = false
log_level = "silent"
upstream_connect_failfast_hard_errors = false
beobachten_file = "/tmp/cache/beobachten.txt"

[general.links]
show = "*"
public_host = "$PUBLIC_HOST"
public_port = $PORT

[server]
port = $PORT

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = [ "127.0.0.1/32", "::1/128" ]
minimal_runtime_enabled = true
minimal_runtime_cache_ttl_ms = 1000
read_only = $READONLY_FLAG
auth_header = "$AUTH_HEADER"

[[server.listeners]]
ip = "$LISTEN_IP"

[censorship]
tls_domain = "$TLS_DOMAIN"
mask = true
tls_emulation = true
tls_front_dir = "tlsfront"
mask_host = "$TLS_DOMAIN"
mask_shape_hardening_aggressive_mode = true

[access.users]
$USERNAME = "$USER_SECRET"

[[upstreams]]
type = "direct"
bindtodevice = "$UP_IFACE"
EOF

start_telemt || true

echo ""
echo "=== Telemt installed ==="
echo "Version: $LATEST_VER"
echo "Port: $PORT"
echo "Listen IP: $LISTEN_IP"
echo "Public host (links): $PUBLIC_HOST"
echo "TLS domain: $TLS_DOMAIN"
echo "User: $USERNAME"
echo "Secret: $USER_SECRET"
echo "Upstream interface: $UP_IFACE"
echo "tlsfront directory: $CONFIG_DIR/tlsfront"
echo "Log: /tmp/log/telemt.log"
echo ""
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    curl -H "Authorization: $AUTH_HEADER" -s --connect-timeout 3 http://127.0.0.1:9091/v1/users 2>/dev/null | \
        jq -r '.data[] | "[\(.username)]", (.links.classic[]? | "classic: \(.)"), (.links.secure[]? | "secure: \(.)"), (.links.tls[]? | "tls: \(.)"), ""' 2>/dev/null || true
fi
echo ""
printf '%s\n' "${RED}${BOLD}⚠️  Не забудьте открыть порт $PORT в межсетевом экране!${NC}"
printf '%s\n' "${RED}   Межсетевой экран → Добавить правило → Порт назначения = $PORT → ✅ Включить → Сохранить${NC}"

# «Серый» IP: RFC1918 + CGNAT 100.64/10 — только тогда предупреждаем
_is_grey_ip() {
    _ip="$1"
    case "$_ip" in
        10.*|192.168.*|127.*) return 0 ;;
        169.254.*) return 0 ;;
        100.*)
            _o2=$(echo "$_ip" | cut -d. -f2)
            [ "$_o2" -ge 64 ] 2>/dev/null && [ "$_o2" -le 127 ] 2>/dev/null && return 0
            return 1
            ;;
        172.*)
            _o2=$(echo "$_ip" | cut -d. -f2)
            [ "$_o2" -ge 16 ] 2>/dev/null && [ "$_o2" -le 31 ] 2>/dev/null && return 0
            return 1
            ;;
        *) return 1 ;;
    esac
}
_check_ip="$AUTO_IP"
# если public_host — тоже IP, проверяем его
case "$PUBLIC_HOST" in
    *[!0-9.]*|"") ;;
    *) _check_ip="$PUBLIC_HOST" ;;
esac
if _is_grey_ip "$_check_ip"; then
    echo ""
    printf '%s\n' "${RED}${BOLD}⚠️  Обнаружен «серый» IP: $_check_ip${NC}"
    printf '%s\n' "${RED}   Адрес из частных/CGNAT диапазонов (10.x / 100.64–127.x / 172.16–31.x / 192.168.x).${NC}"
    printf '%s\n' "${RED}   С интернета к прокси, скорее всего, не подключиться — только из вашей локальной сети.${NC}"
    printf '%s\n' "${RED}   Нужен белый IP, проброс порта у провайдера или туннель (VPN/WARP и т.п.).${NC}"
fi
sync_telemt_panel || true
    ) || true
    info "Установщик telemt завершил работу."
}

# =============================================================================
# 2) telemt-panel
# =============================================================================
install_telemt_panel_pkg() {
    echo
    info "Установка telemt-panel"
    (
        set -e
        set -o pipefail 2>/dev/null || true
echo "=== telemt-panel installer for Entware (nfqws-menu) ==="

# ANSI
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
BOLD=$(printf '\033[1m')
NC=$(printf '\033[0m')

PANEL_DIR="/opt/etc/telemt-panel"
PANEL_CONFIG="$PANEL_DIR/config.toml"
VERSION_FILE="$PANEL_DIR/.version"
BIN_PATH="/opt/sbin/telemt-panel"
INIT_SCRIPT="/opt/etc/init.d/S99telemt-panel"
TELEMT_CONFIG="/opt/etc/telemt/config.toml"
TMPDIR="/tmp/telemt-panel-dl"
GITHUB_REPO="amirotin/telemt_panel"

# --- Arch (как installer_telemt_v3 / nfqws-menu) ---
_arch_normalize() {
    case "$1" in
        aarch64*|arm64*)             echo "aarch64" ;;
        mipsel*|mipselsf*|mips64el*) echo "mipsel" ;;
        mips*|mipssf*)               echo "mips" ;;
        x86_64*|amd64*|x64*)         echo "x86_64" ;;
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
    name=$(grep -E '^[[:space:]]*arch[[:space:]]+' "$conf" 2>/dev/null | _arch_pick_best) || true
    if [ -n "$name" ]; then
        printf '%s\n' "$name"
        return 0
    fi
    from_url=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            src/gz*|src\ *)
                case "$line" in
                    *mipselsf*|*mips64el*|*mipsel*) from_url="mipsel"; break ;;
                    *mipssf*|*mips*)                from_url="mips"; break ;;
                    *aarch64*|*arm64*)              from_url="aarch64"; break ;;
                    *x86_64*|*amd64*)               from_url="x86_64"; break ;;
                esac
                ;;
        esac
    done < "$conf"
    [ -n "$from_url" ] && printf '%s\n' "$from_url"
}

detect_arch() {
    ARCH=""
    ARCH_RAW=""
    ARCH_SOURCE=""
    ARCH_RAW=$(_arch_from_opkg) || true
    ARCH=$(_arch_normalize "$ARCH_RAW")
    [ -n "$ARCH" ] && ARCH_SOURCE="opkg"
    if [ -z "$ARCH" ]; then
        ARCH_RAW=$(_arch_from_opkg_conf /opt/etc/opkg.conf) || true
        ARCH=$(_arch_normalize "$ARCH_RAW")
        [ -n "$ARCH" ] && ARCH_SOURCE="conf"
    fi
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
}

detect_arch

PANEL_SOURCE="github"
PANEL_IPK_BASE=""
PANEL_IPK_ARCH=""
PANEL_ARCHIVE=""

PANEL_VARIANT="full"   # full | lite (только github)
PANEL_ARCH_TAG=""      # aarch64 | x86_64 для имени архива

case "$ARCH" in
    aarch64)
        PANEL_SOURCE="github"
        PANEL_ARCH_TAG="aarch64"
        PANEL_ARCHIVE="telemt-panel-aarch64-linux-gnu.tar.gz"
        ;;
    x86_64)
        PANEL_SOURCE="github"
        PANEL_ARCH_TAG="x86_64"
        PANEL_ARCHIVE="telemt-panel-x86_64-linux-gnu.tar.gz"
        ;;
    mipsel)
        PANEL_SOURCE="ipk"
        PANEL_IPK_BASE="https://test.entware.net/mipssf-k3.4/4test/le"
        PANEL_IPK_ARCH="mipsel-3.4"
        ;;
    mips)
        PANEL_SOURCE="ipk"
        PANEL_IPK_BASE="https://test.entware.net/mipssf-k3.4/4test/be"
        PANEL_IPK_ARCH="mips-3.4"
        ;;
    *)
        echo "ERROR: Unsupported architecture: '${ARCH:-?}' (raw=${ARCH_RAW:-?}, src=${ARCH_SOURCE:-none})"
        exit 1
        ;;
esac

if [ "$PANEL_SOURCE" = "ipk" ]; then
    echo "Architecture: $ARCH → ipk $PANEL_IPK_BASE (detect: ${ARCH_SOURCE:-?})"
else
    echo "Architecture: $ARCH → $PANEL_ARCHIVE (detect: ${ARCH_SOURCE:-?})"
fi

# --- Helpers ---
_http_get() {
    if command -v wget >/dev/null 2>&1; then
        wget -qO- "$1" 2>/dev/null
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" 2>/dev/null
    fi
}

_http_download() {
    _url="$1"
    _out="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$_out" "$_url"
    else
        curl -fL -o "$_out" "$_url"
    fi
}

ensure_deps() {
    _force="${1:-0}"
    _need=0
    command -v openssl >/dev/null 2>&1 || _need=1
    command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || _need=1
    if [ "$_force" = "1" ] || [ "$_need" -eq 1 ]; then
        echo "Установка/проверка зависимостей..."
        opkg update 2>/dev/null || true
        opkg install openssl-util 2>/dev/null || true
        opkg install wget-ssl 2>/dev/null || opkg install wget 2>/dev/null || true
    fi
}


# Свободное место на /opt (kB). $1 = минимум kB
check_opt_space() {
    _need_kb="${1:-12000}"
    _avail=$(df -k /opt 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -z "$_avail" ] || ! [ "$_avail" -ge 0 ] 2>/dev/null; then
        _avail=$(df -P -k /opt 2>/dev/null | awk 'NR==2 {print $4}')
    fi
    if [ -z "$_avail" ] || ! [ "$_avail" -ge 0 ] 2>/dev/null; then
        echo "WARNING: не удалось определить свободное место на /opt"
        df -h /opt 2>/dev/null || true
        return 0
    fi
    echo "Свободно на /opt: ${_avail} kB (нужно ≥ ${_need_kb} kB)"
    if [ "$_avail" -lt "$_need_kb" ]; then
        echo ""
        printf '%s\n' "${RED}ERROR: недостаточно места на /opt${NC}"
        echo "  Доступно: ${_avail} kB"
        echo "  Требуется: ≥ ${_need_kb} kB"
        echo "  Освободите место (логи, старые пакеты, /opt/tmp) и повторите."
        echo ""
        df -h /opt 2>/dev/null || df -h 2>/dev/null || true
        return 1
    fi
    return 0
}

get_local_version() {
    if [ -f "$VERSION_FILE" ]; then
        ver=$(cat "$VERSION_FILE" 2>/dev/null | head -n1 | tr -d ' \r\n')
        case "$ver" in v*|V*) ver=$(printf '%s' "$ver" | sed 's/^[vV]//') ;; esac
        echo "$ver"
        return
    fi
    # telemt-panel не поддерживает --version
    ver=$(opkg list-installed 2>/dev/null | awk '/^telemt-panel[ -]/{print $3; exit}') || true
    case "$ver" in *-* ) ver=$(printf '%s' "$ver" | cut -d- -f1) ;; esac
    echo "${ver:-}"
}

get_latest_ipk_meta() {
    LATEST_VER=""
    LATEST_IPK_NAME=""
    LATEST_IPK_URL=""
    html=$(_http_get "$PANEL_IPK_BASE/") || true
    [ -n "$html" ] || return 1
    names=$(printf '%s\n' "$html" | grep -oE "telemt-panel_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+_${PANEL_IPK_ARCH}\.ipk" | sort -u) || true
    [ -n "$names" ] || return 1
    best_name=""
    best_a=0; best_b=0; best_c=0; best_r=0
    for n in $names; do
        ver=$(printf '%s\n' "$n" | sed -n "s/^telemt-panel_\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)-.*/\1/p")
        rev=$(printf '%s\n' "$n" | sed -n "s/^telemt-panel_[0-9.]*-\([0-9][0-9]*\)_.*/\1/p")
        a=$(echo "$ver" | cut -d. -f1)
        b=$(echo "$ver" | cut -d. -f2)
        c=$(echo "$ver" | cut -d. -f3)
        r=${rev:-0}
        newer=0
        if [ "$a" -gt "$best_a" ] 2>/dev/null; then newer=1
        elif [ "$a" -eq "$best_a" ] 2>/dev/null; then
            if [ "$b" -gt "$best_b" ] 2>/dev/null; then newer=1
            elif [ "$b" -eq "$best_b" ] 2>/dev/null; then
                if [ "$c" -gt "$best_c" ] 2>/dev/null; then newer=1
                elif [ "$c" -eq "$best_c" ] 2>/dev/null && [ "$r" -gt "$best_r" ] 2>/dev/null; then newer=1
                fi
            fi
        fi
        if [ -z "$best_name" ] || [ "$newer" -eq 1 ]; then
            best_name="$n"
            best_a=$a; best_b=$b; best_c=$c; best_r=$r
            LATEST_VER="$ver"
        fi
    done
    [ -n "$best_name" ] || return 1
    LATEST_IPK_NAME="$best_name"
    LATEST_IPK_URL="$PANEL_IPK_BASE/$best_name"
    return 0
}

get_latest_version() {
    ver=""
    if [ "$PANEL_SOURCE" = "ipk" ]; then
        if get_latest_ipk_meta; then
            ver="$LATEST_VER"
        fi
    else
        ver=$(_http_get "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | \
            grep '"tag_name"' | head -n1 | cut -d '"' -f 4) || true
    fi
    case "$ver" in v*|V*) ver=$(printf '%s' "$ver" | sed 's/^[vV]//') ;; esac
    echo "$ver"
}

install_init_script() {
    mkdir -p /opt/etc/init.d /tmp/log /opt/var/run
    cat > "$INIT_SCRIPT" <<'EOF'
#!/bin/sh

ENABLED=yes
PROCS=telemt-panel
ARGS="-config /opt/etc/$PROCS/config.toml"
PREARGS=""
DESC="Telemt Panel"
PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
EOF
    chmod +x "$INIT_SCRIPT"
}

download_and_install_binary() {
    _ver="$1"
    mkdir -p "$TMPDIR" /opt/sbin "$PANEL_DIR"

    if [ "$PANEL_SOURCE" = "ipk" ]; then
        if [ -z "${LATEST_IPK_URL:-}" ]; then
            get_latest_ipk_meta || true
        fi
        if [ -z "${LATEST_IPK_URL:-}" ]; then
            echo "ERROR: не найден telemt-panel_*.ipk в $PANEL_IPK_BASE/"
            return 1
        fi
        echo "Downloading telemt-panel ipk $_ver..."
        echo "  $LATEST_IPK_URL"
        IPK_PATH="/tmp/telemt-panel_$$.ipk"
        _http_download "$LATEST_IPK_URL" "$IPK_PATH" || { rm -f "$IPK_PATH"; return 1; }
        echo "opkg install $IPK_PATH ..."
        # Depends: telemt — если telemt стоит бинарником без opkg-пакета, нужен --force-depends
        if ! opkg install --force-reinstall "$IPK_PATH"; then
            echo "retry: --force-reinstall --force-depends..."
            if ! opkg install --force-reinstall --force-depends "$IPK_PATH"; then
                if ! opkg install --force-depends "$IPK_PATH"; then
                    echo "ERROR: opkg install failed"
                    rm -f "$IPK_PATH"
                    return 1
                fi
            fi
        fi
        rm -f "$IPK_PATH"
        if [ ! -x "$BIN_PATH" ] && [ -x /opt/sbin/telemt-panel ]; then
            BIN_PATH=/opt/sbin/telemt-panel
        fi
        if [ ! -x "$BIN_PATH" ]; then
            echo "ERROR: binary missing after opkg install"
            return 1
        fi
        _wv=$(printf '%s' "$_ver" | sed 's/^[vV]//')
        echo "$_wv" > "$VERSION_FILE"
        echo "Package installed: telemt-panel $_wv [opkg/ipk]"
        rm -rf "$TMPDIR"
        return 0
    fi

    # GitHub tar.gz (aarch64 / x86_64)
    # тег релиза на GitHub обычно с v (v1.0.0-rc.3)
    _tag="$_ver"
    case "$_tag" in
        v*|V*) ;;
        *) _tag="v$_tag" ;;
    esac
    # на случай если PANEL_ARCHIVE ещё не выставлен (env override)
    if [ -z "${PANEL_ARCHIVE:-}" ] && [ -n "${PANEL_ARCH_TAG:-}" ]; then
        if [ "${PANEL_VARIANT:-full}" = "lite" ]; then
            PANEL_ARCHIVE="telemt-panel-lite-${PANEL_ARCH_TAG}-linux-gnu.tar.gz"
        else
            PANEL_ARCHIVE="telemt-panel-${PANEL_ARCH_TAG}-linux-gnu.tar.gz"
        fi
    fi
    echo "Downloading telemt-panel $_tag ($PANEL_ARCHIVE) [${PANEL_VARIANT:-full}]..."
    URL="https://github.com/$GITHUB_REPO/releases/download/${_tag}/${PANEL_ARCHIVE}"
    echo "  $URL"
    ARCHIVE_PATH="$TMPDIR/telemt-panel.tar.gz"
    if ! _http_download "$URL" "$ARCHIVE_PATH"; then
        # lite мог отсутствовать в выбранном теге — fallback на full
        if [ "${PANEL_VARIANT:-full}" = "lite" ]; then
            PANEL_VARIANT="full"
            PANEL_ARCHIVE="telemt-panel-${PANEL_ARCH_TAG}-linux-gnu.tar.gz"
            URL="https://github.com/$GITHUB_REPO/releases/download/${_tag}/${PANEL_ARCHIVE}"
            echo "WARNING: lite-архив не найден (404). Пробуем full:"
            echo "  $URL"
            _http_download "$URL" "$ARCHIVE_PATH" || return 1
        else
            return 1
        fi
    fi
    echo "Extracting..."
    tar -xzf "$ARCHIVE_PATH" -C "$TMPDIR"
    BINARY=$(find "$TMPDIR" -type f \( -name 'telemt-panel' -o -name 'telemt-panel-*' \) ! -name '*.tar.gz' 2>/dev/null | head -n1)
    if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
        echo "ERROR: telemt-panel binary not found in archive"
        ls -la "$TMPDIR" || true
        rm -rf "$TMPDIR"
        return 1
    fi
    cp "$BINARY" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    _wv=$(printf '%s' "$_ver" | sed 's/^[vV]//')
    echo "$_wv" > "$VERSION_FILE"
    echo "Binary installed: $BIN_PATH ($_wv)"
    rm -rf "$TMPDIR"
    return 0
}

panel_is_running() {
    if [ -x "$INIT_SCRIPT" ]; then
        out=$("$INIT_SCRIPT" check 2>/dev/null) || true
        echo "$out" | grep -qi alive && return 0
    fi
    pidof telemt-panel >/dev/null 2>&1 && return 0
    return 1
}

start_panel() {
    install_init_script
    if [ -x "$INIT_SCRIPT" ]; then
        if "$INIT_SCRIPT" restart; then
            echo "telemt-panel started OK."
            return 0
        fi
    fi
    echo "WARNING: init start failed, trying foreground check..."
    "$BIN_PATH" -config "$PANEL_CONFIG" >/tmp/telemt-panel-start.err 2>&1 &
    TPID=$!
    sleep 2
    if kill -0 "$TPID" 2>/dev/null; then
        echo "Process running (pid $TPID)."
        return 0
    fi
    tail -n 30 /tmp/telemt-panel-start.err 2>/dev/null || true
    return 1
}

extract_telemt_auth() {
    # auth_header из [server.api]
    awk '
        /^\[server\.api\]/ { inapi=1; next }
        /^\[/ { inapi=0 }
        inapi && $0 ~ /^[[:space:]]*auth_header[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/["'\'' ]/, "")
            print
            exit
        }
    ' "$TELEMT_CONFIG" 2>/dev/null
}

extract_telemt_api_url() {
    listen=$(awk '
        /^\[server\.api\]/ { inapi=1; next }
        /^\[/ { inapi=0 }
        inapi && $0 ~ /^[[:space:]]*listen[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/["'\'' ]/, "")
            print
            exit
        }
    ' "$TELEMT_CONFIG" 2>/dev/null) || true
    listen=${listen:-127.0.0.1:9091}
    case "$listen" in
        *://*) echo "$listen" ;;
        *) echo "http://$listen" ;;
    esac
}

# --- deps + versions ---
ensure_deps 0

HAS_CONFIG=0
HAS_BIN=0
[ -f "$PANEL_CONFIG" ] && HAS_CONFIG=1
[ -x "$BIN_PATH" ] && HAS_BIN=1

LOCAL_VER=$(get_local_version)

# --- 5 последних релизов GitHub (включая Pre-release) ---
# stdout: "tag prerelease" (0|1)
list_panel_releases() {
    _json=""
    for _url in \
        "https://api.github.com/repos/$GITHUB_REPO/releases?per_page=8" \
        "https://ghproxy.net/https://api.github.com/repos/$GITHUB_REPO/releases?per_page=8"
    do
        _json=$(_http_get "$_url") || _json=""
        [ -n "$_json" ] || continue
        case "$_json" in *'"message":'*) continue ;; esac
        printf '%s\n' "$_json" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"|"prerelease"[[:space:]]*:[[:space:]]*(true|false)' | \
        {
            _tag=""; _n=0
            while IFS= read -r _line || [ -n "$_line" ]; do
                case "$_line" in
                    *'"tag_name"'*)
                        _tag=$(printf '%s' "$_line" | sed -n 's/.*"\([^"]*\)"$/\1/p')
                        ;;
                    *'"prerelease"'*)
                        if [ -n "$_tag" ]; then
                            case "$_line" in
                                *true*) printf '%s 1\n' "$_tag" ;;
                                *)      printf '%s 0\n' "$_tag" ;;
                            esac
                            _tag=""
                            _n=$((_n + 1))
                            [ "$_n" -ge 5 ] && break
                        fi
                        ;;
                esac
            done
        }
        return 0
    done
    return 1
}

# lite есть только в релизах 1.0.0+ (rc); в 0.6.x — только full
_panel_supports_lite() {
    _v=$(printf '%s' "${1:-}" | sed 's/^[vV]//')
    case "$_v" in
        1.*|2.*|3.*|4.*|5.*|6.*|7.*|8.*|9.*) return 0 ;;
        *) return 1 ;;
    esac
}

# Выбор варианта full/lite (только GitHub aarch64/x86_64)
pick_panel_variant() {
    PANEL_VARIANT="full"
    if ! _panel_supports_lite "${LATEST_VER:-}"; then
        PANEL_ARCHIVE="telemt-panel-${PANEL_ARCH_TAG}-linux-gnu.tar.gz"
        echo ""
        echo "Сборка lite недоступна для ${LATEST_VER:-этой версии} (только 1.0.0+)."
        echo "Используем full → $PANEL_ARCHIVE"
        return 0
    fi
    echo ""
    printf '%s\n' "${BOLD}Сборка telemt-panel:${NC}"
    echo "  1. full — SQLite или memory, бинарник ~25–32 МБ"
    echo "  2. lite — только memory, бинарник ~12–16 МБ (роутеры / мало места)"
    echo ""
    printf "Вариант [1=full]: "
    read _vc || true
    case "$_vc" in
        2|lite|l|L) PANEL_VARIANT="lite" ;;
        *) PANEL_VARIANT="full" ;;
    esac
    if [ "$PANEL_VARIANT" = "lite" ]; then
        PANEL_ARCHIVE="telemt-panel-lite-${PANEL_ARCH_TAG}-linux-gnu.tar.gz"
    else
        PANEL_ARCHIVE="telemt-panel-${PANEL_ARCH_TAG}-linux-gnu.tar.gz"
    fi
    echo "Выбрана сборка: $PANEL_VARIANT → $PANEL_ARCHIVE"
}

# Выбор версии → LATEST_VER (+ LATEST_IPK_* для mips). Отмена → exit 0.
pick_panel_version() {
    LATEST_VER=""
    LATEST_IPK_NAME=""
    LATEST_IPK_URL=""

    # ----- mips/mipsel: только .ipk с test.entware -----
    if [ "$PANEL_SOURCE" = "ipk" ]; then
        _tmp="/tmp/telemt-panel-ipks-$$"
        html=$(_http_get "$PANEL_IPK_BASE/") || true
        if [ -z "$html" ]; then
            echo "WARNING: не удалось получить список ipk — пробуем latest."
            get_latest_ipk_meta || true
            return 0
        fi
        names=$(printf '%s\n' "$html" | grep -oE "telemt-panel_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+_${PANEL_IPK_ARCH}\.ipk" | sort -u) || true
        if [ -z "$names" ]; then
            echo "WARNING: ipk не найдены в $PANEL_IPK_BASE/"
            return 0
        fi
        # сортировка версий по убыванию (простая)
        : > "$_tmp"
        for n in $names; do
            ver=$(printf '%s\n' "$n" | sed -n "s/^telemt-panel_\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)-.*/\1/p")
            rev=$(printf '%s\n' "$n" | sed -n "s/^telemt-panel_[0-9.]*-\([0-9][0-9]*\)_.*/\1/p")
            printf '%s %s %s\n' "$ver" "${rev:-0}" "$n" >> "$_tmp"
        done
        # bubble-ish: sort -k1,1V -k2,2nr if available
        # убывающий список версий (без tail -r / sort -V — portable BusyBox)
        _sorted=$(sort -t' ' -k1,1 -k2,2n "$_tmp" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}')
        printf '%s\n' "$_sorted" | head -8 > "${_tmp}.list"

        echo ""
        printf '%s\n' "${BOLD}Выберите версию telemt-panel (.ipk):${NC}"
        _i=1
        while IFS=' ' read -r _ver _rev _name; do
            [ -n "$_name" ] || continue
            if [ "$_i" -eq 1 ]; then
                printf '  %d. %s  %s(ipk — Latest)%s\n' "$_i" "$_ver" "$GREEN" "$NC"
            else
                printf '  %d. %s  (ipk)\n' "$_i" "$_ver"
            fi
            _i=$((_i + 1))
        done < "${_tmp}.list"
        _max=$((_i - 1))
        echo "  0. Отмена"
        echo ""
        printf "Номер версии [1]: "
        read _choice || true
        case "$_choice" in
            "") _choice=1 ;;
            0|q|Q)
                rm -f "$_tmp" "${_tmp}.list"
                echo "Отменено."
                exit 0
                ;;
        esac
        if ! echo "$_choice" | grep -qE '^[0-9]+$' || [ "$_choice" -lt 1 ] || [ "$_choice" -gt "$_max" ]; then
            rm -f "$_tmp" "${_tmp}.list"
            echo "ERROR: неверный выбор."
            exit 1
        fi
        _line=$(sed -n "${_choice}p" "${_tmp}.list")
        LATEST_VER=$(echo "$_line" | awk '{print $1}')
        LATEST_IPK_NAME=$(echo "$_line" | awk '{print $3}')
        LATEST_IPK_URL="$PANEL_IPK_BASE/$LATEST_IPK_NAME"
        rm -f "$_tmp" "${_tmp}.list"
        echo "Выбрана версия: $LATEST_VER ($LATEST_IPK_NAME)"
        return 0
    fi

    # ----- aarch64/x86_64: GitHub releases -----
    _tmp="/tmp/telemt-panel-rels-$$"
    _list=$(list_panel_releases 2>/dev/null) || _list=""
    if [ -z "$_list" ]; then
        echo "WARNING: не удалось получить список релизов GitHub — будет latest."
        LATEST_VER=""
        rm -f "$_tmp"
        return 0
    fi
    printf '%s\n' "$_list" | head -5 > "$_tmp"
    _latest_stable=$(awk '$2==0 {print $1; exit}' "$_tmp")

    echo ""
    printf '%s\n' "${BOLD}Выберите версию telemt-panel:${NC}"
    _i=1
    while IFS=' ' read -r _tag _pre; do
        [ -n "$_tag" ] || continue
        if [ "$_pre" = "1" ]; then
            printf '  %d. %s%s%s  %s(Pre-release)%s\n' "$_i" "$YELLOW" "$_tag" "$NC" "$YELLOW" "$NC"
        elif [ -n "$_latest_stable" ] && [ "$_tag" = "$_latest_stable" ]; then
            printf '  %d. %s%s%s  %s(Release — Latest)%s\n' "$_i" "$GREEN" "$_tag" "$NC" "$GREEN" "$NC"
        else
            printf '  %d. %s  (Release)\n' "$_i" "$_tag"
        fi
        _i=$((_i + 1))
    done < "$_tmp"
    echo "  0. Отмена"
    echo ""
    printf "Номер версии [1]: "
    read _choice || true
    case "$_choice" in
        "") _choice=1 ;;
        0|q|Q)
            rm -f "$_tmp"
            echo "Отменено."
            exit 0
            ;;
    esac
    if ! echo "$_choice" | grep -qE '^[0-9]+$' || [ "$_choice" -lt 1 ] || [ "$_choice" -gt 5 ]; then
        rm -f "$_tmp"
        echo "ERROR: неверный выбор."
        exit 1
    fi
    LATEST_VER=$(sed -n "${_choice}p" "$_tmp" | awk '{print $1}')
    rm -f "$_tmp"
    if [ -z "$LATEST_VER" ]; then
        echo "ERROR: версия не найдена."
        exit 1
    fi
    echo "Выбрана версия: $LATEST_VER"
    pick_panel_variant
    return 0
}

# Внешний override (env) или интерактивный выбор
if [ -n "${TELEMT_PANEL_VERSION:-}" ]; then
    LATEST_VER="$TELEMT_PANEL_VERSION"
    echo "Requested version: $LATEST_VER (TELEMT_PANEL_VERSION)"
    if [ "$PANEL_SOURCE" = "github" ]; then
        pick_panel_variant
    fi
else
    pick_panel_version
    if [ -z "$LATEST_VER" ]; then
        if [ "$PANEL_SOURCE" = "ipk" ]; then
            echo "Detecting latest telemt-panel from $PANEL_IPK_BASE ..."
        else
            echo "Detecting latest telemt-panel from GitHub ($GITHUB_REPO)..."
        fi
        LATEST_VER=$(get_latest_version)
        if [ -z "$LATEST_VER" ]; then
            ensure_deps 1
            LATEST_VER=$(get_latest_version)
        fi
    fi
fi
if [ -z "$LATEST_VER" ]; then
    echo "ERROR: Cannot detect latest telemt-panel version"
    exit 1
fi
# единый вид версии без ведущей v (тег для GitHub собирается при скачивании)
case "$LATEST_VER" in v*|V*) LATEST_VER=$(printf '%s' "$LATEST_VER" | sed 's/^[vV]//') ;; esac
echo "Target version: $LATEST_VER"
[ -n "$LOCAL_VER" ] && echo "Installed version: $LOCAL_VER" || echo "Installed version: (none)"
[ "$PANEL_SOURCE" = "github" ] && echo "Build variant: ${PANEL_VARIANT:-full}"

# Сразу после определения версии — проверка места
if ! [ -n "$LOCAL_VER" ] || [ "$LOCAL_VER" != "$LATEST_VER" ] || [ ! -x "$BIN_PATH" ]; then
    if [ "$PANEL_SOURCE" = "github" ] && [ "${PANEL_VARIANT:-full}" = "lite" ]; then
        check_opt_space 9000 || exit 1
    else
        check_opt_space 12000 || exit 1
    fi
fi

# =====================================================================
# UPDATE: config exists — preserve, update binary only
# =====================================================================
if [ "$HAS_CONFIG" -eq 1 ]; then
    echo ""
    echo "Найден существующий конфиг: $PANEL_CONFIG"
    echo "Настройки сохраняются."

    # подтянуть auth_header из telemt если изменился
    if [ -f "$TELEMT_CONFIG" ]; then
        TM_AUTH=$(extract_telemt_auth) || true
        TM_URL=$(extract_telemt_api_url) || true
        if [ -n "$TM_AUTH" ]; then
            PN_AUTH=$(awk '
                /^\[telemt\]/ { insec=1; next }
                /^\[/ { insec=0 }
                insec && $0 ~ /^[[:space:]]*auth_header[[:space:]]*=/ {
                    sub(/^[^=]*=[[:space:]]*/, ""); gsub(/["'\'' ]/, ""); print; exit
                }
            ' "$PANEL_CONFIG" 2>/dev/null) || true
            if [ -n "$PN_AUTH" ] && [ "$PN_AUTH" != "$TM_AUTH" ]; then
                echo "Синхронизация auth_header telemt → panel..."
                # простое обновление строк
                sed -i "s|^auth_header *=.*|auth_header = \"$TM_AUTH\"|" "$PANEL_CONFIG" 2>/dev/null || true
            fi
            if [ -n "$TM_URL" ]; then
                sed -i "s|^url *=.*|url = \"$TM_URL\"|" "$PANEL_CONFIG" 2>/dev/null || true
            fi
            sed -i "s|^binary_path *=.*telemt\"|binary_path = \"/opt/usr/bin/telemt\"|" "$PANEL_CONFIG" 2>/dev/null || true
        fi
    fi

    if [ -n "$LOCAL_VER" ] && [ "$LOCAL_VER" = "$LATEST_VER" ] && [ "$HAS_BIN" -eq 1 ]; then
        echo "Уже установлена актуальная версия ($LOCAL_VER)."
        echo "$LOCAL_VER" > "$VERSION_FILE"
        install_init_script
        if panel_is_running; then
            echo "telemt-panel уже запущен — restart не требуется."
        else
            start_panel || true
        fi
        echo ""
        echo "=== telemt-panel up-to-date ($LOCAL_VER) ==="
        echo "Config: $PANEL_CONFIG"
        exit 0
    fi

    ensure_deps 1
    echo "Обновление: ${LOCAL_VER:-unknown} → $LATEST_VER"
    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
    fi
    download_and_install_binary "$LATEST_VER" || exit 1
    install_init_script
    start_panel || true
    echo ""
    echo "=== telemt-panel updated to $LATEST_VER ==="
    echo "Config preserved: $PANEL_CONFIG"
    exit 0
fi

# =====================================================================
# FRESH INSTALL
# =====================================================================
echo ""
echo "Конфиг не найден — полная установка."
ensure_deps 1

if [ ! -f "$TELEMT_CONFIG" ]; then
    printf '%s\n' "${RED}ERROR: $TELEMT_CONFIG не найден. Сначала установите telemt.${NC}"
    exit 1
fi

DEFAULT_PORT=8080
echo "Проверка порта $DEFAULT_PORT..."
if netstat -tuln 2>/dev/null | grep -E "[:.]$DEFAULT_PORT\b" >/dev/null 2>&1; then
    echo "Порт $DEFAULT_PORT занят."
    printf "Введите порт для telemt-panel: "
    read LISTEN_PORT || true
    while [ -z "$LISTEN_PORT" ] || netstat -tuln 2>/dev/null | grep -E "[:.]$LISTEN_PORT\b" >/dev/null 2>&1; do
        echo "Порт занят или пустой."
        printf "Введите другой порт: "
        read LISTEN_PORT || true
    done
else
    LISTEN_PORT=$DEFAULT_PORT
fi
echo "Порт: $LISTEN_PORT"

echo "Введите пароль для входа в панель (admin):"
read PASS || true
if [ -z "$PASS" ]; then
    echo "ERROR: пароль не может быть пустым"
    exit 1
fi

# бинарник нужен для hash-password — ставим сначала
if [ -x "$INIT_SCRIPT" ]; then
    "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
fi
download_and_install_binary "$LATEST_VER" || exit 1

echo "Генерация password_hash..."
PASSWORD_HASH=$(echo "$PASS" | "$BIN_PATH" hash-password 2>&1 | tail -n1)
if [ -z "$PASSWORD_HASH" ]; then
    echo "ERROR: не удалось получить password_hash"
    exit 1
fi
echo "password_hash получен."

JWT_SECRET=$(openssl rand -hex 32)
AUTH_HEADER=$(extract_telemt_auth) || true
if [ -z "$AUTH_HEADER" ]; then
    # fallback: любая строка auth_header
    AUTH_HEADER=$(grep -E '^[[:space:]]*auth_header[[:space:]]*=' "$TELEMT_CONFIG" | head -n1 | sed -E 's/.*=[[:space:]]*"?([^"]*)"?.*/\1/') || true
fi
if [ -z "$AUTH_HEADER" ]; then
    printf '%s\n' "${RED}ERROR: auth_header не найден в $TELEMT_CONFIG${NC}"
    exit 1
fi
TELEMT_URL=$(extract_telemt_api_url)

mkdir -p "$PANEL_DIR"
cat > "$PANEL_CONFIG" <<EOF
listen = "0.0.0.0:$LISTEN_PORT"

[telemt]
url = "$TELEMT_URL"
auth_header = "$AUTH_HEADER"
binary_path = "/opt/usr/bin/telemt"

[panel]
binary_path = "/opt/sbin/telemt-panel"

[tls]

[geoip]

[auth]
username = "admin"
password_hash = "$PASSWORD_HASH"
jwt_secret = "$JWT_SECRET"
session_ttl = "24h"

[users]
EOF

install_init_script
start_panel || true

# LAN IP for URL
IP=$(ip -4 -o addr show br0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
if [ -z "$IP" ]; then
    IP=$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' | head -n1)
fi

echo ""
echo "=== telemt-panel installed ==="
echo "Version: $LATEST_VER"
echo "Config: $PANEL_CONFIG"
echo "Port: $LISTEN_PORT"
echo "Login: admin"
echo "Init: $INIT_SCRIPT"
echo ""
printf '%s\n' "${GREEN}http://${IP:-192.168.1.1}:$LISTEN_PORT${NC}"
printf '%s\n' "${RED}${BOLD}⚠️  Откройте порт $LISTEN_PORT в межсетевом экране (если заходите извне).${NC}"
    ) || true
    info "Установщик telemt-panel завершил работу."
}

show_banner() {
    clear 2>/dev/null || true
    printf '%s\n' "${CYAN}================================================${NC}"
    printf '%s\n' "${CYAN}${BOLD}           telemt / telemt-panel${NC}"
    printf '%s\n' "${CYAN}================================================${NC}"
    echo
    printf '%s\n' "${DIM}Telemt — быстрый, безопасный и функциональный сервер на Rust:${NC}"
    printf '%s\n' "${DIM}полностью реализует официальный алгоритм Telegram-прокси${NC}"
    printf '%s\n' "${DIM}и добавляет множество улучшений.${NC}"
    echo
    printf '%s\n' "${DIM}panel upstream: https://github.com/amirotin/telemt_panel${NC}"
    printf '%s\n' "${DIM}(Entware / Keenetic; aarch64, x86_64, mipsel, mips)${NC}"
    echo
    if is_telemt_installed; then
        _tm_st=""
        # telemt + версия
        if [ -x /opt/usr/bin/telemt ] || [ -x /opt/etc/init.d/S99telemt ] || [ -d /opt/etc/telemt ]; then
            _v=""
            [ -f /opt/etc/telemt/.version ] && _v=$(head -n1 /opt/etc/telemt/.version 2>/dev/null | tr -d ' \r\n')
            case "$_v" in v*|V*) _v=$(printf '%s' "$_v" | sed 's/^[vV]//') ;; esac
            if [ -z "$_v" ] && [ -x /opt/usr/bin/telemt ]; then
                _v=$(/opt/usr/bin/telemt --version 2>/dev/null | head -n1 | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
            fi
            if [ -n "$_v" ]; then
                _tm_st="${_tm_st}telemt $_v "
            else
                _tm_st="${_tm_st}telemt "
            fi
        fi
        # telemt-panel + версия
        if [ -x /opt/sbin/telemt-panel ] || [ -x /opt/etc/init.d/S99telemt-panel ] || [ -d /opt/etc/telemt-panel ]; then
            _v=""
            [ -f /opt/etc/telemt-panel/.version ] && _v=$(head -n1 /opt/etc/telemt-panel/.version 2>/dev/null | tr -d ' \r\n')
            case "$_v" in v*|V*) _v=$(printf '%s' "$_v" | sed 's/^[vV]//') ;; esac
            if [ -n "$_v" ]; then
                _tm_st="${_tm_st}telemt-panel $_v "
            else
                _tm_st="${_tm_st}telemt-panel "
            fi
        fi
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
}

while true; do
    show_banner
    ask "Выбор: "
    tchoice=$(read_choice)
    case "$tchoice" in
        1) install_telemt_core || true ;;
        2) install_telemt_panel_pkg || true ;;
        3) install_telemt_systemd_emu || true ;;
        4)
            if confirm_yes "Удалить telemt и telemt-panel?"; then
                remove_telemt_all || true
            else
                info "Отменено."
            fi
            ;;
        0|"")
            exit 0
            ;;
        *)
            warn "Неверный пункт"
            ;;
    esac
    echo
    ask "Нажмите Enter для возврата в меню..."
    read_choice >/dev/null
done
