#!/bin/sh
# installer_rci79.sh — RCI :79 → ndm SCGI (KeeneticOS / Netcraze 5.1.9)
# Upstream: https://git.bobyrev.com/PCA/rci79
# Бинарники зеркалируются в nfqws-menu/rci79/ (v1.0.0); fallback — релизы upstream.
#
# Установка:  sh installer_rci79.sh
# Удаление:   sh installer_rci79.sh remove
# Принудительно: RCI79_FORCE=1 sh installer_rci79.sh

export PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:${PATH:-}

# Зеркало репозитория nfqws-menu (бинари в rci79/)
NFQWS_RAW="${RCI79_MIRROR:-https://raw.githubusercontent.com/rndnaame/nfqws-menu/main}"
NFQWS_JSDELIVR="${RCI79_JSDELIVR:-https://cdn.jsdelivr.net/gh/rndnaame/nfqws-menu@main}"
# Upstream релизы
UPSTREAM_URL="${RCI79_URL:-https://git.bobyrev.com/PCA/rci79/releases/download/v1.0.0}"

RULE="-d 127.0.0.1 -p tcp --dport 79 -j REDIRECT --to-ports 7979"

info()  { printf '[+] %s\n' "$*"; }
warn()  { printf '[!] %s\n' "$*"; }
error() { printf '[!] %s\n' "$*" >&2; }

restart_hr() {
  for s in /opt/etc/init.d/S99hrneo /opt/etc/init.d/S99hrweb; do
    [ -x "$s" ] && "$s" restart 2>/dev/null || true
  done
}

do_remove() {
  [ -x /opt/etc/init.d/S98rci79 ] && /opt/etc/init.d/S98rci79 stop 2>/dev/null || true
  iptables -t nat -D OUTPUT $RULE 2>/dev/null || true
  rm -f /opt/etc/init.d/S98rci79 /opt/etc/ndm/netfilter.d/50-rci79.sh /opt/sbin/rci79
  restart_hr
  info "rci79 удалён"
  exit 0
}

[ "$1" = remove ] || [ "$1" = uninstall ] && do_remove

[ -d /opt/sbin ] || { error "Нужен Entware (/opt)"; exit 1; }

# Нужен 403 0x1867; иначе — только force или уже обновление существующего
code=$(curl -s -o /dev/null -D - --connect-timeout 2 --max-time 4 \
  "http://127.0.0.1:79/rci/show/version" 2>/dev/null | grep -E '^HTTP|X-Detail' | tr '\r\n' '  ')
case "$code" in
  *0x1867*) ;;
  *)
    if [ ! -x /opt/sbin/rci79 ]; then
      info "RCI :79 отвечает: ${code:-ok}. Это не поломка 5.1.9 (нужен 403 0x1867) — ставить не обязательно."
      if [ "${RCI79_FORCE:-0}" != "1" ]; then
        exit 0
      fi
      warn "RCI79_FORCE=1 — ставим всё равно"
    fi
    ;;
esac

# Архитектура
arch=""
arch=$(opkg print-architecture 2>/dev/null | awk '
  $1=="arch" && $2!="" && $2!="all" {
    p=$3+0; n=$2; b=0
    if (n ~ /^mipsel/ || n ~ /^mipselsf/) b=2
    else if (n ~ /^aarch64/) b=2
    s=p*10+b
    if (s>best) { best=s; name=n }
  }
  END { print name }
')
case "$arch" in
  aarch64*|arm64*) arch=aarch64 ;;
  mipsel*|mipselsf*) arch=mipsel ;;
  mips*) arch=mips ;;
  *)
    arch=$(uname -m 2>/dev/null || true)
    case "$arch" in
      aarch64|arm64) arch=aarch64 ;;
      mipsel) arch=mipsel ;;
      mips) arch=mips ;;
      *) arch="" ;;
    esac
    ;;
esac
[ -n "$arch" ] || { error "Не определена архитектура (нужны aarch64 / mipsel / mips)"; exit 1; }

bin_name="rci79-$arch"
tmp="/opt/sbin/rci79.tmp.$$"
rm -f "$tmp"

# Кандидаты: 1) raw GitHub  2) jsDelivr  3) upstream releases
download_ok=0
for src in \
  "$NFQWS_RAW/rci79/$bin_name" \
  "$NFQWS_JSDELIVR/rci79/$bin_name" \
  "$UPSTREAM_URL/$bin_name"
do
  info "Пробуем: $src"
  if curl -fsSL --connect-timeout 10 --max-time 180 -o "$tmp" "$src" 2>/dev/null; then
    sz=$(wc -c < "$tmp" 2>/dev/null | tr -d ' \t\n')
    case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
    if [ "$sz" -ge 100000 ]; then
      download_ok=1
      info "Скачано ($sz байт)"
      break
    fi
    warn "Файл слишком маленький ($sz) — следующий источник"
    rm -f "$tmp"
  else
    warn "Не удалось"
    rm -f "$tmp"
  fi
done

if [ "$download_ok" != "1" ]; then
  error "Не удалось скачать $bin_name ни из зеркала, ни с upstream"
  exit 1
fi

chmod 755 "$tmp" && mv "$tmp" /opt/sbin/rci79

cat > /opt/etc/init.d/S98rci79 <<'INEOF'
#!/bin/sh
ENABLED=yes
PROCS=rci79
ARGS="127.0.0.1:7979"
PREARGS=""
DESC="RCI 79 -> ndm SCGI (KeeneticOS 5.1.9)"
PATH=/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin
. /opt/etc/init.d/rc.func
INEOF
chmod 755 /opt/etc/init.d/S98rci79

mkdir -p /opt/etc/ndm/netfilter.d
cat > /opt/etc/ndm/netfilter.d/50-rci79.sh <<'INEOF'
#!/bin/sh
# Keenetic перестраивает iptables — возвращаем заворот :79 -> rci79.
[ "$type" = ip6tables ] && exit 0
[ "$table" = nat ] || exit 0
iptables -t nat -C OUTPUT -d 127.0.0.1 -p tcp --dport 79 -j REDIRECT --to-ports 7979 2>/dev/null ||
  iptables -t nat -I OUTPUT -d 127.0.0.1 -p tcp --dport 79 -j REDIRECT --to-ports 7979
INEOF
chmod 755 /opt/etc/ndm/netfilter.d/50-rci79.sh

/opt/etc/init.d/S98rci79 restart 2>/dev/null || /opt/etc/init.d/S98rci79 start 2>/dev/null || true
type=iptables table=nat /opt/etc/ndm/netfilter.d/50-rci79.sh 2>/dev/null || true
sleep 1
http=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 \
  "http://127.0.0.1:79/rci/show/version" 2>/dev/null || echo "000")
restart_hr
if [ "$http" = "200" ]; then
  info "RCI :79 отвечает 200"
else
  warn "RCI :79 отвечает $http (ожидался 200) — проверьте права/сокет ndm"
fi
if [ -x /opt/etc/init.d/S99hrneo ]; then
  sleep 5
  m=$(iptables -t mangle -S HRNEO_CONNMARK 2>/dev/null | grep -c set-xmark || echo 0)
  if [ "$m" -gt 0 ] 2>/dev/null; then
    info "HydraRoute: правила маркировки ($m)"
  else
    info "Правил HRNEO пока нет — проверьте позже: iptables -t mangle -S HRNEO_CONNMARK"
  fi
fi
info "Готово. Upstream: https://git.bobyrev.com/PCA/rci79"
