### 0.11.07

- **CLI** — быстрый запуск пункта: `menu 18`, `menu u` / `menu U`, `menu S`, `menu 99` (`run_menu_choice`); `menu -h` — справка

### 0.11.06

- **awg / sing-box** — с релиза **41** бинарь `awgm-box` (`/opt/etc/awg-manager/singbox/awgm-box`, [hoaxisr/awgm-box](https://github.com/hoaxisr/awgm-box)); статус, U-auto и версия учитывают `awgm-box` и старый `sing-box`

### 0.11.05

- удалены неиспользуемые константы: `REPO_URL`, `TELEMT_SYSTEMCTL_URL`, `TELEMT_JOURNALCTL_URL`

### 0.11.04

- **U / awg UPX auto** — прогон awg-compressed не только при новой версии awg, но и если стоит **sing-box** (иначе SB не обновлялся при актуальном awg)

### 0.11.03

- **U / awg UPX auto** — если есть `sing-box` рядом с awg-manager → `INSTALL_AWG=1 INSTALL_SB=1` (оба), без порога размера UPX


# Changelog

История изменений **nfqws-menu**. Актуальная версия скрипта — в [`README.md`](README.md).

### Не выпущено

- **п. 19 Antiscan** — `installer_antiscan.sh`: установка из opkg-репозитория [Antiscan](https://github.com/dimon27254/antiscan) (зеркало — по выбору), проверка компонента Netfilter, статус, start/stop/restart, настройка `ISP_INTERFACES` / `PORTS` / `PORTS_FORWARDED` с подсказкой WAN и бэкапом, `antiscan edit config`, списки блокировки, обновление и удаление
- **show_installed** — строка `antiscan` (⚡ по `/tmp/ascn.run`), `S99ascn` не дублируется в «прочие init.d»
- тесты: `tests/antiscan-installer.sh` (заглушки opkg / RCI / iptables / ipset) по поведению Antiscan 1.10.6: состояние правил, `/tmp/ascn.lock`, кэш индексов opkg
- **п. 8 DoT/DoH → Пресеты** — новый пресет **1) Яндекс DoT (77.88.8.8) → .ru / .su / .рф** (`.рф` = `xn--p1ai`, SNI `common.dot.dns.yandex.net`, порт 853); прежние пресеты сдвинуты на +1 без изменения команд. Ошибка `ndmc` по зоне показывается и не выдаётся за успех (`apply_dot` возвращает код ошибки). То же в отдельном `menu-dns.sh`, где `save_config` больше не пишет `[ГОТОВО]` при ошибке сохранения
- тесты: `tests/dns-domain-presets.sh` (заглушка `ndmc`) — команды пресетов, мультивыбор, отмена, повтор, частичный сбой, ошибка сохранения

### 0.10.26

- **show_installed** — оптимизация: `emit_opkg`, без `opkg list-installed` / `command -v dpi-detector`; telemt-panel версия из status-кэша; тот же порядок строк

### 0.10.25

- **show_installed** — firc больше не дублируется (S99firc в «прочие init.d» пропускается: уже выводится из opkg)

### 0.10.24

- **п. 88** — после `opkg remove nfqws2-ui` запрос на удаление хвостов: `/opt/etc/nfqws-ui`, `/opt/etc/nfqws2/.snapshots`, `/opt/etc/nfqws2/.history` (`[y/N]`)

### 0.10.23

- **статус** — в установленных компонентах показывается **nfqws2-ui** (версия opkg, ⚡ при открытом порте **8090**)
- **п. 88** — удаление **nfqws2-ui** (`opkg remove nfqws2-ui`); также входит в «удалить все пакеты NFQWS»

### 0.10.22

- **п. 1** — пункт **4) nfqws-ui от zemidala** ([nfqws2-ui](https://github.com/zemidala/nfqws2-ui)): установка через `releases/latest/download/install.sh`; предупреждение, если нет nfqws2-keenetic; подсказка `:8090` / `nfqws-ui-setup`
- **п. 1** — взаимное исключение **nfqws-keenetic ↔ nfqws2-keenetic**: при установке одной версии предлагается удалить другую (иначе opkg conflict); сообщение «установлен» только после реального успеха

### 0.10.21

- **п. 18 warpscout** — `installer_warpscout.sh` v0.1.16: bin, register, scan (+junk), find-junk + **apply junk к conf/туннелю**, apply awg-manager, проверка туннеля

### 0.10.16

- **п. 2 apply_strategy** — восстановление нестандартных `POLICY_NAME` / `POLICY_EXCLUDE` по умолчанию **Да** (`[Y/n]`)

### 0.10.15

- **п. 9** — возвращён **Discord: все пакеты в nfqws2** (`nfqws2_fullsession.sh`): пропал в 0.10.7 при выносе п.16 в отдельный installer
- README: описание п.9; убраны лишние варианты установки меню (Fastly / curl-jsDelivr / ghproxy)
- зависимости: `ca-certificates`, `opkg remove wget-nossl`

### 0.10.10 – 0.10.14

- **S → 3. Починить OPKG**: зеркала `sw.ext.io/entware` и `sw.ext.io/nfqws{,2,-web}`; probe доп. репо; github.io → sw при fail/hang; IPv4 wget; timeout `opkg update` 60 с; repair status/lock

### 0.10.19

- **SHA256SUMS cache** — скачивание во временный файл, `mv` только при успехе (PR #24)
- README: уточнения IPSet / язык / hosts п.7 / tg-ws-proxy-rs (PR #25)
- UI: подпись стандартного IPSet без опечатки «офиставка»

### 0.10.7 – 0.10.9

- **п. 16** — `installer_tgws_rs.sh`; **п. 17 firc** — `installer_firc.sh`
- *(в 0.10.7 при upload не попал п.9 Discord — восстановлен в 0.10.15)*

### 0.10.4

- **п. 17 firc** — снова только remote `installer_firc.sh` (без встраивания логики в меню)

### 0.10.3

- (отменено в 0.10.4) попытка inline-установки firc в меню

### 0.10.2

- **п. 17 firc** — установка через [repo.hoaxisr.ru](https://repo.hoaxisr.ru/): `src/gz hoaxisr` → `/opt/etc/opkg/awg_manager.conf`, `opkg update && opkg install firc`; Depends тянет opkg; conf общий с awg-manager не удаляется при remove

### 0.10.1

- Нумерация версии: переход на линейку **0.10.x** (MINOR после серии 0.9.x).

### 0.9.84

- **п. 17** — **firc** ([hoaxisr/firc](https://github.com/hoaxisr/firc), [repo.hoaxisr.ru](https://repo.hoaxisr.ru/)): opkg install из фида; статус в show_installed

### 0.9.x

- **Архитектура** — `opkg print-architecture` → `/opt/etc/opkg.conf` → `uname`; заголовок `Модель Title ARCH`; предупреждение без Netfilter-kmod
- **Язык RU/EN (77)** — локализация основного меню и общих промптов; `Language: RU|EN` всегда латиницей (Telnet)
- **Проверка обновлений** — TTL **10 мин**; `read -t` для авто-перерисовки с меткой ⭡; dpi-detector учитывает **pre-release**
- **Компоненты** — разбор `/opt/lib/opkg/status` (только `installed`), один awk-проход; меньше зависаний при занятом opkg
- **rkn.list** — сначала GitHub raw; очистка list через awk (в т.ч. CRLF)
- **Стратегии** — предупреждение о **ts-фулинге** (TCP timestamps на Windows)
- **Промпты** — единый формат `Your choice [0]:` / `Ваш выбор [0]:`; пункт **0** везде `Back` / `Назад`

### 0.7.0 – 0.8.0

- **Нумерация меню** — единый п. **1** (NFQWS / NFQWS2 / web / .ipk); стратегии/списки **2–8**; утилиты **10–17** (без TG WS Proxy Go)
- **п. 1 → 4** — установка `.ipk` напрямую (GitHub Releases / ghproxy / github.io) при блокировке opkg-репозитория
- **Проверка обновлений** — фоновый опрос (меню, tg-ws-proxy-rs, dpi-detector, awg-manager…); метка **⭡** в статусе и заголовке; TTL 10 мин (`NFQWS_MENU_UPDATE_TTL`)
- **TG WS Proxy Go** убран из меню (остаётся миграция секрета/порта при установке Rust)

### 0.6.69

- **TG WS Proxy Rust (п. 17)** — отдельный пункт: `tg-ws-proxy-rs` ставится релизом с GitHub, секрет и порт прежней Go-установки переносятся
- **Подбор параметров** — CF-домены и варианты лестницы проверяются штатной пробой бинаря (`--check-listener`, 2.4.5+), список с временем каждого выводится на выбор
- **Сквозная проверка** — ссылка выдаётся только после `resPQ` от DC Telegram

### 0.6.59 – 0.6.67

- **Ввод** — убраны `stty` / `tty_setup` и чтение меню с `/dev/tty` (ломали Backspace → печать `^?`); обычный `read`; `drain_stdin` сохранён
- **п. 1** — убран пункт «патч десинка TLS reasm» (с NFQWS2 **≥ 1.3.1** фикс в официальном пакете)

### 0.6.50 – 0.6.58

- **п. 16** — **telemt / telemt-panel** (augin/telemt_script): install / panel / systemD-emu / remove; статус в `show_installed`
- **S** — сервисные утилиты: UPX-сжатие bin/sbin, Dropbear fix, **U** — `opkg upgrade` всех пакетов
- **п. 10–12** — без лишнего `confirm` перед запуском установщиков dpi-detector / awg-manager / KeenKit
- *(патч TLS reasm bin — временно в 0.6.50–0.6.65, снят в 0.6.66)*

### 0.6.47 – 0.6.49

- **Загрузки** — зеркала CDN для raw/API GitHub: jsDelivr, Fastly jsDelivr, ghproxy; offline-кэш стратегий в `/opt/etc/nfqws-menu/strategies/`
- **Список стратегий** — SUMS → API → offline-кэш
- **DNS (п. 9)** — пресет **NullsProxy**; привязки доменов: cdninstagram, Supercell через NullsProxy (п. 9–10), свой домен → 11

### 0.6.46

- **п. 3 apply_strategy** — `POLICY_NAME` / `POLICY_EXCLUDE`: стандартные (`nfqws` / `0`) не трогаются; нестандартные — восстановление по запросу (y/N)

### 0.6.43 – 0.6.45

- **п. 3 → 99 backup** — список `.bak.*` от свежего к старому; самый свежий выделен жёлтым; рядом со стратегией из конфига (`general (ALT11)`)

### 0.6.42

- **download_file** — сообщения fallback («Основной канал недоступен…», «Скачано через…») уходят в **stderr**, чтобы не попадали в `list=$(list_strategies …)` и не ломали нумерацию меню
- **list_strategies** — дополнительно фильтрует только строки `*.conf`

### 0.6.41

- **п. 3 Выбор стратегии** — в конце списка добавлен **99) восстановление из backup**: вывод `nfqws.conf.bak.YYYYMMDDHHMMSS` (V1) / `nfqws2.conf.bak.…` (V2), выбор файла, запись без бэкапа текущего, `fix_isp_interface`, перезапуск сервиса

### 0.6.40

- **Таймауты загрузок** — увеличены для сильного DPI: connect 10 с, max 30 с, wget 25 с (раньше 5 / 15 / 12); для крупных файлов (rkn) — до 180 с
- **п. 5 rkn.list** — при недоступности GitHub raw: jsDelivr / Fastly / ghproxy / зеркало `mizulina.shit.vc`; URL основного источника упрощён (`…/master/…` без `refs/heads`)

### 0.6.36 – 0.6.39

- **LBL\_**\* — подписи пунктов совпадают с номерами меню (`LBL_5`…`LBL_9`; удалён `LBL_7F`)
- **DoT/DoH пресеты** — Google, AdGuard Default/Family, ControlD Free, DNS4EU, Alibaba DNS, DNSPod; убраны нерабочие Tiar Japan
- **proc_running** — `grep -qF --` (fix при именах сервисов с ведущим `-`)

### 0.6.26 – 0.6.35

- **SHA256 blobs** — проверка локальных `.bin` по `strategies/blobs/SHA256SUMS`; перекачка при несовпадении хеша
- **Список стратегий** — из корневого `SHA256SUMS` (без GitHub API), API как fallback
- **Список blobs** (п. 7) — приоритет SUMS → API → fallback
- **Загрузки** — при блокировке основного канала `curl --interface` через туннели (`awg0`, `t2s0`, `nwg0`, `opkgtun0`, …); короткие таймауты
- **CI** — workflow `.github/workflows/sha256sums.yml` обновляет `SHA256SUMS` и `strategies/blobs/SHA256SUMS` (push / daily / manual)
- **п. 3** — авто `IPV6_ENABLED` по наличию глобального IPv6 на ISP-интерфейсе; сохранение привязки **rkn.list** в `MODE_LIST` при смене стратегии
- **DNS (п. 9)** — парсер только секция System (`proxy-tls` / `proxy-https`); Policy\* и `*-filters` игнорируются

### 0.6.23 – 0.6.25

- **п. 5** — поддержка **v1 и v2** (выбор 1 / 2 / обе); размер существующего `rkn.list` в КБ вместо подсчёта строк
- **п. 5** — вставка в `MODE_LIST` через **awk** (CRLF, пустые кавычки, пробелы)
- **п. 10** — очистка дубликатов `dpi-detector` (`/tmp`, `/opt/root`) перед запуском / после установки

### 0.6.22

- **п. 8** — только IPv4; пропуск битых доменов (`..`, ведущая `.`); один IP на домен; предупреждение при &gt;64 записей (лимит Keenetic)
- **hosts** — исправлены `objects.githubusercontent.com`, `my.telegram.org`; убраны IPv6 и дубли discord

### 0.6.19 – 0.6.21

- **п. 3** — при применении стратегии: нормализация **CRLF → LF** в скачанном `.conf` (иначе `S51nfqws2` падает с `: not found` / битыми портами iptables)
- **ISP_INTERFACE** — при разборе значения из конфига удаляются `\r` и кавычки (исправлен «съехавший» вывод `[+]` → `"+]`)
- **п. 8** — **Обновление hosts**: секции из `hosts` в репозитории → `ndmc ip host` / удаление (`no ip host`) + save

### 0.6.18

- **п. 7** — ускорен разбор конфига: один проход `awk` вместо shell+grep на каждую строку

### 0.6.16 – 0.6.17

- **п. 5** — если `rkn.list` уже есть, спрашивает об обновлении (по умолчанию **Нет**)
- **п. 5** — перезапуск `S51nfqws2` только при изменениях (список и/или `MODE_LIST`)

### 0.6.15

- Базовая линейка 0.6.x (см. ниже)

### 0.6.x (основные изменения относительно 0.5.x)

- **п. 5** — загрузка **rkn.list** (125k+ доменов, zapret4rocket) + автодобавление в `MODE_LIST`
- **п. 7** — смена активных **fake:blob** (локальные + из репозитория)
- **п. 8** — **Обновление hosts** через `ndmc`
- **п. 15** — **MagiTrickle** (установка/обновление/удаление)
- **п. 15** — **telemt / telemt-panel**; **п. 16** — **TG WS Proxy Rust**
- **S / U** — UPX, Dropbear fix, opkg upgrade
- **п. 8** — Управление DoT/DoH: пресеты Xbox-DNS / NullsProxy / Supercell и др.
- **SHA256** blobs + список стратегий из SUMS; CDN/offline-кэш; fallback через VPN-туннели
- Нумерация (0.8.x): 1 = install, 2–8 = стратегии/списки, 10–16 = утилиты
- Статус: magitrickle / telemt / tg-ws-proxy-rs; метка **⭡** при новой версии
- Без принудительного `export LD_LIBRARY_PATH` (совместимость ndmc / Entware wget)
- Обычный `read` в меню (без `stty` / принудительного erase)

### 0.5.17

- **usque-keenetic** (п. 14) — установка/обновление; удаление в п. 88

### 0.5.16

- **DNS-счётчик** — только секция System; Policy0/1 и `proxy-*-filters` не учитываются

### 0.5.14 – 0.5.15

- Счётчик DoT/DoH по слотам (записи `server-tls` / `server-https`), а не по уникальным targets
- Ужесточён парсер `show dns-proxy`

### 0.5.13

- **LD_LIBRARY_PATH / ndmc_cli** — OPKG-путь по умолчанию; `ndmc` через системные библиотеки (как у spatiumstas)

### 0.5.11 – 0.5.12

- **TG WS Proxy Go** (п. 13) — установка/обновление через feedly
- Удаление `tg-ws-proxy` в п. 88 (+ опционально `feedly.conf`)

### 0.4.0 → 0.5.x

- **Управление DoT/DoH** через `ndmc`
- Утилиты: awg-manager, KeenKit; удаление — п. 88
- Быстрый запуск `menu`, статус только установленного, ⚡, кэш opkg/процессов
- Переключение языка (п. 77)

---
