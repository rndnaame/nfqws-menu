#!/bin/sh
# Тесты меню «Привязать домен к DNS (Пресеты)» — add_domain_menu в
# nfqws-menu.sh (п. 8 «Управление DoT/DoH») и в отдельном menu-dns.sh.
# ndmc заменён заглушкой: она только записывает команды в журнал и по
# требованию возвращает ошибку; настоящий DNS роутера не трогается.
#
#   sh tests/dns-domain-presets.sh
#   dash tests/dns-domain-presets.sh
#
# shellcheck disable=SC1007,SC2016,SC2034,SC2329
set -u

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/bin"
cat > "$root/bin/ndmc" <<'EOF'
#!/bin/sh
# ndmc -c "<команда>" (nfqws-menu.sh) или ndmc -c слова команды (menu-dns.sh)
[ "$1" = "-c" ] && shift
cmd="$*"
printf '%s\n' "$cmd" >> "$NDMC_LOG"
if [ -s "$NDMC_FAIL" ]; then
  while IFS= read -r pattern; do
    case "$cmd" in *"$pattern"*) echo "Command::Base error" >&2; exit 1 ;; esac
  done < "$NDMC_FAIL"
fi
exit 0
EOF
chmod +x "$root/bin/ndmc"
PATH="$root/bin:$PATH"
NDMC_LOG="$root/ndmc.log"
NDMC_FAIL="$root/ndmc.fail"
export PATH NDMC_LOG NDMC_FAIL

results="$root/results"
: > "$results"
ok()    { echo ok >> "$results"; }
fail()  { echo fail >> "$results"; printf 'FAIL: %s: %s: %s\n' "$suite" "$case_name" "$1" >&2; }
check() { if eval "$1"; then ok; else fail "$2"; fi; }

YA="dns-proxy tls upstream 77.88.8.8 853 sni common.dot.dns.yandex.net domain"
SAVE="system configuration save"

# run <ответы через \n> [шаблоны ошибок ndmc через \n] — запуск меню в текущей оболочке
run() {
  : > "$NDMC_LOG"
  printf '%b' "${2:-}" > "$NDMC_FAIL"
  printf '%b' "$1" > "$root/input"
  add_domain_menu < "$root/input" > "$root/out" 2>&1 || true
}

# expect <ожидаемые строки журнала ndmc> — журнал должен совпасть целиком
expect() {
  printf '%b' "$1" > "$root/expected"
  if cmp -s "$root/expected" "$NDMC_LOG"; then ok; else
    fail "журнал ndmc отличается"
    diff "$root/expected" "$NDMC_LOG" >&2 || true
  fi
}

saves() { grep -c "^$SAVE\$" "$NDMC_LOG"; }
out_has() { grep -q -- "$1" "$root/out"; }

YA3="$YA ru\n$YA su\n$YA xn--p1ai\n"

# Общие сценарии для обеих реализаций.
# $1 — ожидаемые команды старых пресетов в новой нумерации: «номер|команды».
common_cases() {
  case_name="1: три зоны Яндекс DoT"
  run '1\n'
  expect "$YA3$SAVE\n"
  check '[ "$(grep -c "77.88.8.8 853 sni common.dot.dns.yandex.net domain " "$NDMC_LOG")" -eq 3 ]' "не три команды с IP/портом/SNI Яндекса"
  check 'grep -q " domain xn--p1ai$" "$NDMC_LOG"' ".рф не в Punycode"
  check '! grep -q "рф" "$NDMC_LOG"' "кириллица в команде ndmc"
  check '! grep -q "^no " "$NDMC_LOG"' "есть удаляющие команды"
  check 'out_has "Яндекс DoT привязан к зонам .ru, .su, .рф"' "нет сообщения об успехе"
  check 'out_has "ГОТОВО"' "нет сообщения о сохранении"

  case_name="0 и пустой ввод — отмена"
  run '0\n'; expect ""
  run '\n';  expect ""

  case_name="повторный выбор 1"
  run '1\n'; cp "$NDMC_LOG" "$root/first"
  run '1\n'
  check 'cmp -s "$root/first" "$NDMC_LOG"' "повтор даёт другие команды"
  expect "$YA3$SAVE\n"

  case_name="ошибка ndmc для одной зоны"
  run '1\n' 'domain su\n'
  expect "$YA3$SAVE\n"
  check '! out_has "Яндекс DoT привязан к зонам"' "частичный сбой показан как успех"
  check 'out_has "не привязан к зонам: su"' "не названа зона с ошибкой"
  check '! out_has "зонам: ru"' "успешная зона ru названа ошибочной"

  case_name="ошибка ndmc для всех зон"
  run '1\n' '77.88.8.8\n'
  expect "$YA3"
  check '[ "$(saves)" -eq 0 ]' "конфигурация сохранена без единой привязки"
  check 'out_has "не привязан к зонам: ru su xn--p1ai"' "не названы зоны с ошибкой"
  check '! out_has "ГОТОВО"' "сбой показан как успех"

  case_name="ошибка сохранения конфигурации"
  run '1\n' "$SAVE\n"
  expect "$YA3$SAVE\n"
  check 'out_has "ОШИБКА"' "нет сообщения об ошибке сохранения"
  check '! out_has "ГОТОВО"' "ошибка сохранения показана как успех"

  # Старые пресеты: те же команды, что и до сдвига номеров.
  # Без конвейера: цикл идёт в текущей оболочке, обрыв ловит маркер набора.
  printf '%s\n' "$1" > "$root/presets"
  while IFS='|' read -r n cmds; do
    [ -n "$n" ] || continue
    case_name="старый пресет $n"
    run "$n\n"
    expect "$cmds$SAVE\n"
  done < "$root/presets"
}

# Набор должен дойти до конца: оболочка может молча выйти посреди меню.
suite_done() { echo "done $suite" >> "$results"; }

# ---------------------------------------------------------------------------
suite="nfqws-menu.sh"
(
  set +u  # меню не рассчитаны на set -u: apply_dot читает необязательный $4
  # Функции меню без точки входа; ndmc_cli — настоящая обёртка над ndmc.
  eval "$(sed -n '/^ndmc_cli() {/,/^}/p; /^dns_save_config() {/,/^}/p; /^apply_dot() {/,/^}/p; /^apply_doh() {/,/^}/p; /^add_domain_menu() {/,/^}/p' "$repo_dir/nfqws-menu.sh")"
  GREEN="" RED="" CYAN="" YELLOW="" BOLD="" DIM="" NC=""
  info()  { printf '%s\n' "[+] $*"; }
  warn()  { printf '%s\n' "[!] $*"; }
  error() { printf '%s\n' "[x] $*"; }
  ask()   { printf '%s' "[?] $*"; }
  sleep() { :; }

  common_cases "$(cat <<'EOF'
2|dns-proxy tls upstream 185.228.168.9 853 sni security-filter-dns.cleanbrowsing.org domain instagram.com\n
3|dns-proxy https upstream https://doh.cleanbrowsing.org/doh/security-filter/ domain instagram.com\n
4|dns-proxy tls upstream 185.228.168.9 853 sni security-filter-dns.cleanbrowsing.org domain cdninstagram.com\n
5|dns-proxy https upstream https://doh.cleanbrowsing.org/doh/security-filter/ domain cdninstagram.com\n
6|dns-proxy tls upstream sw.ext.io domain rutor.is\ndns-proxy tls upstream sw.ext.io domain rutor.info\n
7|dns-proxy https upstream https://dns.malw.link/dns-query domain ntc.party\n
8|dns-proxy tls upstream xbox-dns.ru sni xbox-dns.ru domain gql.twitch.tv\ndns-proxy tls upstream xbox-dns.ru sni xbox-dns.ru domain usher.ttvnw.net\n
9|dns-proxy https upstream https://xbox-dns.ru/dns-query domain gql.twitch.tv\ndns-proxy https upstream https://xbox-dns.ru/dns-query domain usher.ttvnw.net\n
10|dns-proxy tls upstream dns.nullsproxy.com sni dns.nullsproxy.com domain supercell.com\ndns-proxy tls upstream dns.nullsproxy.com sni dns.nullsproxy.com domain supercellid.com\ndns-proxy tls upstream dns.nullsproxy.com sni dns.nullsproxy.com domain brawlstarsgame.com\ndns-proxy tls upstream dns.nullsproxy.com sni dns.nullsproxy.com domain clashofclans.com\ndns-proxy tls upstream dns.nullsproxy.com sni dns.nullsproxy.com domain clashroyaleapp.com\n
11|dns-proxy https upstream https://dns.nullsproxy.com/dns-query domain supercell.com\ndns-proxy https upstream https://dns.nullsproxy.com/dns-query domain supercellid.com\ndns-proxy https upstream https://dns.nullsproxy.com/dns-query domain brawlstarsgame.com\ndns-proxy https upstream https://dns.nullsproxy.com/dns-query domain clashofclans.com\ndns-proxy https upstream https://dns.nullsproxy.com/dns-query domain clashroyaleapp.com\n
EOF
)"

  case_name="12: свой домен (DoT и DoH)"
  run '12\nexample.com\n1\n9.9.9.9\ndns.quad9.net\n853\n'
  expect "dns-proxy tls upstream 9.9.9.9 853 sni dns.quad9.net domain example.com\n$SAVE\n"
  run '12\nexample.com\n2\nhttps://dns.quad9.net/dns-query\n'
  expect "dns-proxy https upstream https://dns.quad9.net/dns-query domain example.com\n$SAVE\n"

  case_name="1,2,4: несколько пресетов, одно сохранение"
  run '1,2,4\n'
  expect "${YA3}dns-proxy tls upstream 185.228.168.9 853 sni security-filter-dns.cleanbrowsing.org domain instagram.com\ndns-proxy tls upstream 185.228.168.9 853 sni security-filter-dns.cleanbrowsing.org domain cdninstagram.com\n$SAVE\n"

  # В меню add_domain_menu вызывается из menu_dns_manage || true при set -e:
  # ошибка apply_dot не должна обрывать перебор зон.
  case_name="set -e: ошибка одной зоны не прерывает остальные"
  : > "$NDMC_LOG"; printf 'domain ru\n' > "$NDMC_FAIL"; printf '1\n' > "$root/input"
  ( set -e; add_domain_menu < "$root/input" > /dev/null 2>&1 || true ) 2>/dev/null
  expect "$YA3$SAVE\n"
  suite_done
)

# ---------------------------------------------------------------------------
suite="menu-dns.sh"
(
  set +u
  # Только функции; главный цикл в конце файла не выполняется.
  eval "$(sed -n '/^save_config() {/,/^}/p; /^apply_dot() {/,/^}/p; /^apply_doh() {/,/^}/p; /^add_domain_menu() {/,/^}/p' "$repo_dir/menu-dns.sh")"
  C_RESET="" C_BOLD="" C_CYAN="" C_GREEN="" C_YELLOW="" C_MAGENTA="" C_RED="" C_DIM=""
  sleep() { :; }

  common_cases "$(cat <<'EOF'
2|dns-proxy tls upstream 185.228.168.9 853 sni security-filter-dns.cleanbrowsing.org domain instagram.com\n
3|dns-proxy https upstream https://doh.cleanbrowsing.org/doh/security-filter/ domain instagram.com\n
4|dns-proxy tls upstream sw.ext.io domain rutor.is\ndns-proxy tls upstream sw.ext.io domain rutor.info\n
5|dns-proxy https upstream https://dns.malw.link/dns-query domain ntc.party\n
EOF
)"

  case_name="6: свой домен (DoT и DoH)"
  run '6\nexample.com\n1\n9.9.9.9\ndns.quad9.net\n853\n'
  expect "dns-proxy tls upstream 9.9.9.9 853 sni dns.quad9.net domain example.com\n$SAVE\n"
  run '6\nexample.com\n2\nhttps://dns.quad9.net/dns-query\n'
  expect "dns-proxy https upstream https://dns.quad9.net/dns-query domain example.com\n$SAVE\n"

  case_name="1,2,4: несколько пресетов, одно сохранение"
  run '1,2,4\n'
  expect "${YA3}dns-proxy tls upstream 185.228.168.9 853 sni security-filter-dns.cleanbrowsing.org domain instagram.com\ndns-proxy tls upstream sw.ext.io domain rutor.is\ndns-proxy tls upstream sw.ext.io domain rutor.info\n$SAVE\n"

  case_name="save_config возвращает ошибку"
  : > "$NDMC_LOG"; printf '%s\n' "$SAVE" > "$NDMC_FAIL"
  check '! save_config > /dev/null 2>&1' "save_config вернул успех при ошибке ndmc"
  suite_done
)

passes=$(grep -c '^ok$' "$results")
failures=$(grep -c '^fail$' "$results")
for s in nfqws-menu.sh menu-dns.sh; do
  grep -qx "done $s" "$results" || { printf "FAIL: %s: набор оборвался до конца\n" "$s" >&2; failures=$((failures + 1)); }
done
printf 'Итого: %s успешно, %s с ошибкой\n' "$passes" "$failures"
[ "$failures" -eq 0 ]
