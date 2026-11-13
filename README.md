# NFQWS-MENU

Интерактивное меню установки и управления пакетами **nfqws-keenetic**, **nfqws2-keenetic** и **nfqws-keenetic-web** для роутеров **Keenetic / Netcraze** с **Entware**.

Репозиторий также служит хранилищем готовых **стратегий** обхода DPI, **blobs** и **lists**.

- Скрипт: `nfqws-menu.sh` (текущая версия **0.11.03**)
- Стратегии: `strategies/`
- Hosts: `hosts`
- Контрольные суммы: `SHA256SUMS`, `strategies/blobs/SHA256SUMS`

### Официальные проекты

| Пакет | Репозиторий |
| --- | --- |
| nfqws-keenetic (v1) | https://github.com/nfqws/nfqws-keenetic |
| nfqws2-keenetic (v2) | https://github.com/nfqws/nfqws2-keenetic |
| Веб-интерфейс | https://github.com/nfqws/nfqws-keenetic-web |

### Источник стратегий

Стратегии в этом репозитории сделаны на базе проекта\
[**Flowseal/zapret-discord-youtube**](https://github.com/Flowseal/zapret-discord-youtube)\
и адаптированы под формат конфигов `nfqws-keenetic` / `nfqws2-keenetic`.

Подготовлены пользователем [**@Nare51**](https://github.com/Nare51) с использованием искусственного интеллекта.

---

## Быстрый старт

Подключитесь к Entware (SSH, порт 222 или 22, логин `root`).

> **Рекомендуется jsDelivr** — `raw.githubusercontent.com` у части провайдеров отвечает **404** (DPI), хотя файл в репозитории есть.

### 1. Установите необходимые зависимости

```bash
opkg update
opkg install curl wget-ssl ca-certificates
opkg remove wget-nossl 2>/dev/null || true
```

- **curl** / **wget-ssl** — загрузки по HTTPS (меню, зеркала, installers)
- **ca-certificates** — проверка TLS-сертификатов (без него HTTPS часто падает)
- **wget-nossl** — убрать, если стоит: конфликтует с `wget-ssl`, `opkg` может брать «глухой» wget без SSL

### 2. Установка меню

**Через jsDelivr (предпочтительно):**

```bash
wget -O /opt/nfqws-menu.sh https://cdn.jsdelivr.net/gh/rndnaame/nfqws-menu@main/nfqws-menu.sh && chmod +x /opt/nfqws-menu.sh && sh /opt/nfqws-menu.sh
```

**С GitHub raw (если не режется):**

```bash
wget -O /opt/nfqws-menu.sh https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh && chmod +x /opt/nfqws-menu.sh && sh /opt/nfqws-menu.sh
```

### 3. Быстрый запуск `menu`

После первого запуска создаётся symlink:

```bash
menu
```

(`/opt/bin/menu` → `/opt/nfqws-menu.sh`)

---

## Что делает меню

При запуске скрипт:

1. Определяет архитектуру: `opkg print-architecture` (основной) → при ошибке `/opt/etc/opkg.conf` → fallback `uname -m`. На части Keenetic `uname`/RCI отдают `mips` вместо `mipsel` — поэтому opkg приоритетнее.
2. Заголовок: **Модель / Title / ARCH** из RCI (`/rci/show/version`). ARCH зелёный (из opkg) или жёлтый (из conf/uname). Если в RCI нет `opkg-kmod-netfilter` — красное предупреждение установить «Модули ядра подсистемы Netfilter».
3. Показывает **только установленные** компоненты (версии и статус) одним проходом awk по **opkg status** + **ps** + кэш обновлений (без `opkg list-installed` на каждом кадре):
   - nfqws / nfqws2 / web / **nfqws2-ui**, usque-keenetic, **firc**, **antiscan** (⚡ по `/tmp/ascn.run`), magitrickle, **tg-ws-proxy-rs**;
   - dpi-detector, awg-manager (⚡ при sing-box / amneziawg), KeenKit, telemt / telemt-panel, opera-proxy, cron, dropbear и др. init.d;
   - **⚡** — сервис запущен; **⭡** — доступна более новая версия (фоновая проверка, **TTL 10 мин**, перерисовка меню без Enter).
4. Интерфейс **RU / EN** (пункт **77**): подписи меню и общие промпты (`Your choice [0]:` / `Ваш выбор [0]:`). Подпись `Language: RU|EN` всегда латиницей (удобно для Telnet).
5. Предлагает меню:

```
[::]  КОМПОНЕНТЫ
      1.  Установка NFQWS / NFQWS2

[::]  СТРАТЕГИИ / СПИСКИ
      2.  Выбор стратегии
      3.  Обновить IPSet List
      4.  Загрузить rkn.list (125k+ доменов)
      5.  Обход блокировки DoT/DoH
      6.  Смена активных fake:blob
      7.  Обновление hosts
      8.  Управление DoT/DoH
      9.  Discord: все пакеты в nfqws2

[::]  УТИЛИТЫ
      10. dpi-detector
      11. awg-manager
      12. KeenKit
      13. usque-keenetic
      14. MagiTrickle
      15. telemt / telemt-panel
      16. TG WS Proxy Rust
      17. firc
      18. warpscout
      19. Antiscan

[::]  СЕРВИС [S]  |  Language: RU|EN [77]
      88. Удаление пакетов
      99. Обновить скрипт
      00. Выход
```

Горячие клавиши: **S** — сервисные утилиты (UPX, Dropbear fix, починить OPKG); **U** — безопасное обновление Entware (см. ниже); **77** — смена языка RU↔EN.

Пример блока статуса:

```
Установленные компоненты:
  nfqws2-keenetic        1.3.x ⚡
  nfqws-keenetic-web     3.x ⚡
  tg-ws-proxy-rs         2.x ⚡
  dpi-detector           …
  ⭡ - доступна более новая версия
```

### 1. Установка NFQWS / NFQWS2

Подменю:

```
1) nfqws-keenetic
2) nfqws2-keenetic
3) nfqws-keenetic-web
4) nfqws-ui от zemidala
5) Установка / обновление .ipk (обход DPI)
0) Назад
```

- **1–2** — зависимости (`ca-certificates`, `wget-ssl`), официальный opkg-репозиторий под архитектуру, установка пакета; **взаимное исключение** v1 ↔ v2 (при конфликте — предложение удалить другой пакет, иначе отмена). После установки — предложение поставить веб.
- **3** — веб-интерфейс **nfqws-keenetic-web** (lighttpd + PHP, порт **90**): `http://<IP-роутера>:90`, логин/пароль Entware (`root` / `keenetic` по умолчанию).
- **4** — **nfqws-ui от zemidala** ([nfqws2-ui](https://github.com/zemidala/nfqws2-ui)): установщик с GitHub Releases; нужен **nfqws2-keenetic**; адрес по умолчанию `http://<IP>:8090`, управление — `nfqws-ui-setup`.
- **5** — прямая установка **.ipk** (обход DPI): версии с github.io, скачивание с GitHub Releases → ghproxy → github.io, затем `opkg install` локального файла (конфиги при необходимости извлекаются из .ipk).

> Фикс TLS reasm с **NFQWS2 ≥ 1.3.1** входит в официальный пакет.

### 2. Выбор стратегии

- Если ни одна версия NFQWS не установлена — предлагает установить.
- Показывает список `.conf` из:
  - `strategies/nfqws1/` — для v1
  - `strategies/nfqws2/` — для v2
- Список стратегий: `SHA256SUMS` → GitHub API → **локальный offline-кэш** (`/opt/etc/nfqws-menu/strategies/…`).
- Скачивание: основной raw GitHub → зеркала **jsDelivr / Fastly jsDelivr / ghproxy** → fallback через туннель-интерфейсы (`awg0`, `t2s0`, …); успешный файл сохраняется в offline-кэш.
- Делает **бэкап** текущего конфига и применяет стратегию.
- Перед записью **нормализует CRLF → LF** (иначе `source`/iptables: `: not found`, `invalid port/service`).
- **Пункт 99** — восстановление из backup: `.bak.*` от свежего к старому (самый свежий выделен), рядом имя стратегии из `general (…)` в файле; `fix_isp_interface`, перезапуск сервиса.
- После применения выполняет пост-настройку:

#### ISP_INTERFACE / IPV6_ENABLED

- Определяет интерфейс провайдера из default route (`ip route` / `route`), сравнивает с `ISP_INTERFACE` в конфиге и при необходимости предлагает установить правильное значение. При чтении значения снимаются `\r`, кавычки и пробелы (защита от CRLF в выводе меню).
- Проверяет наличие **глобального IPv6** (`scope global`: 2a00, 2a02, 2606, 2001, …) на выбранном `ISP_INTERFACE` (или default route) и выставляет `IPV6_ENABLED=0|1`. Несколько iface через пробел — достаточно одного с global.

#### Восстановление rkn.list и POLICY\_\*

- Если до смены стратегии в `MODE_LIST` уже был `--hostlist=…/rkn.list`, привязка **восстанавливается** автоматически.
- `POLICY_NAME` **/** `POLICY_EXCLUDE`: стандартные значения (`nfqws` / `0`) не трогаются; **нестандартные** предлагается восстановить (**по умолчанию: Да** — `[Y/n]`).

#### Проверка blobs (наличие + SHA256)

Парсит установленный конфиг и находит используемые `.bin` (`--blob=…`, `--dpi-desync-fake-tls=…`, `--dpi-desync-fake-quic=…` и абсолютные пути).

- Сверяет локальные файлы с эталоном `strategies/blobs/SHA256SUMS` (`sha256sum` или `openssl dgst -sha256`; кэш SUMS \~1 ч).
- Отсутствующие или **устаревшие/повреждённые** (хеш не совпал) предлагает скачать заново; после загрузки — повторная проверка SHA256 (при несовпадении файл удаляется).

#### Обновление lists

По запросу обновляет из `strategies/lists/`: `user.list`, `exclude.list`, `ipset.list`, `ipset_exclude.list`.\
`auto.list` **не трогается** — его заполняет демон.

После всех шагов соответствующий сервис перезапускается.

### 3. Обновление IPSet List

Предлагает выбрать IP/CIDR-список: большой список из\
[Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube)\
или стандартный список из репозитория соответствующего пакета (`nfqws-keenetic` / `nfqws2-keenetic`). Записывает его в `ipset.list`:

| Версия | Путь |
| --- | --- |
| nfqws-keenetic (v1) | `/opt/etc/nfqws/ipset.list` |
| nfqws2-keenetic (v2) | `/opt/etc/nfqws2/lists/ipset.list` |

Бэкап, очистка пустых строк/комментариев, перезапуск сервиса. При двух установленных версиях — можно обновить обе.

### 4. Загрузить rkn.list (125k+ доменов)

Доступно при установленном **nfqws-keenetic** (v1) и/или **nfqws2-keenetic** (v2). При обеих версиях — выбор: 1 / 2 / обе.

- Если `rkn.list` уже есть — показывает размер в **КБ** (без медленного подсчёта 125k строк) и спрашивает, обновлять ли список (**по умолчанию: Нет**). При отказе скачивание пропускается.
- Скачивает большой список доменов РКН из [IndeecFOX/zapret4rocket](https://github.com/IndeecFOX/zapret4rocket)\
  (`extra_strats/TCP/RKN/List.txt`). Сначала **GitHub raw**, затем jsDelivr / Fastly / ghproxy; при недоступности — зеркало `mizulina.shit.vc`.
- Записывает:
  - **v1** → `/opt/etc/nfqws/rkn.list`
  - **v2** → `/opt/etc/nfqws2/lists/rkn.list`
- Добавляет `--hostlist=…/rkn.list` в `MODE_LIST` соответствующего конфига (с бэкапом), если его ещё нет. Вставка через **awk** (устойчиво к CRLF, пробелам, пустым кавычкам).
- **Перезапуск** сервиса (`S51nfqws` / `S51nfqws2`) только при реальных изменениях (обновлён список и/или изменён `MODE_LIST`). Если hostlist уже был в конфиге и список не обновляли — перезапуск не выполняется.

### 5. Обход блокировки DoT/DoH

Доступно при установленном **nfqws-keenetic** и/или **nfqws2-keenetic** (при обеих версиях — выбор v1 / v2 / обе).

Добавляет в `NFQWS_ARGS_CUSTOM` стратегию обхода блокировок публичных DoT/DoH DNS:

- **nfqws1** — `strategies/dns_filter_nfqws1` (классический `--dpi-desync`)
- **nfqws2** — `strategies/dns_filter_nfqws2` (lua-desync)

Покрывает Cloudflare, Google, AdGuard, NextDNS, Quad9, DNS.SB, Alibaba, Xbox-DNS, Geohide и др.; при необходимости добавляет порт `853` в `TCP_PORTS` / `UDP_PORTS` и перезапускает соответствующий сервис (`S51nfqws` / `S51nfqws2`). Стратегия сначала скачивается с GitHub, при недоступности сети — встроенный fallback.

### 6. Смена активных fake:blob

Позволяет заменить используемые в конфиге `fake:blob=NAME` на другой `.bin`-файл (переназначает путь в `--blob=NAME:…`).

- Быстрый разбор конфига (v1/v2) одним проходом **awk**: секции `NFQWS_*ARGS*`, map `--blob=name:path`, уникальные `fake:blob=` (hex пропускаются).
- Показывает список найденных имён по секциям.
- Кандидаты `.bin`: локальные → имена из `strategies/blobs/SHA256SUMS` → GitHub API → встроенный fallback.
- При выборе файла из репозитория — скачивает его, обновляет `--blob=…`, бэкап конфига.
- Перезапуск сервиса — по подтверждению (по умолчанию Да).

### 7. Обновление hosts

Запись статических DNS-привязок на стороне **Keenetic** через `ndmc` (`ip host DOMAIN IP` / `no ip host DOMAIN` + сохранение конфигурации).

- Скачивает файл `hosts` из репозитория.
- Секции задаются комментариями `# Имя секции`; внутри — строки `IP DOMAIN`.
- Можно выбрать одну или несколько секций, **все**, либо **88** — удалить домены из hosts-файла.
- Только **IPv4**; битые домены (`..`, ведущая `.`) пропускаются; **один IP на домен**.
- Предупреждение, если уникальных записей **&gt; 64** (лимит Keenetic `ip host`).
- Нужен `ndmc` (только Keenetic / Netcraze OS).

### 8. Управление DoT/DoH

Управление DNS-over-TLS / DNS-over-HTTPS на стороне **Keenetic** через `ndmc`.

Подменю:

```
1) Добавить DoT сервер(ы)
2) Добавить DoH сервер(ы)
3) Привязать домен к DNS (Пресеты)
4) Удалить сервер(ы)
0) Назад
```

Возможности:

- Просмотр текущих DoT/DoH и персональных привязок к доменам
- Счётчик слотов **N/8** — только секция **System** (Policy0/1 и `*-filters` не учитываются)
- Пресеты DoT/DoH: Яндекс, Cloudflare, Google, Quad9, CleanBrowsing, OpenDNS, DNS.SB, OpenNameServer, AdGuard (Default/Family), ControlD Free, DNS4EU, Alibaba DNS, DNSPod, **NullsProxy**, Xbox-DNS, Comss, Malw Link, Geo Hide, Cloudflare Gateway, **AstraCat**, **Bezmezhau**, **DNS-AI**, **Mafioznik**, **Shecan Free** и др. или ручной ввод
- Быстрая привязка доменов (пресеты):

| № | Описание |
| --- | --- |
| 1 | Яндекс DoT (77.88.8.8) → .ru / .su / .рф |
| 2 | CleanBrowsing DoT → instagram.com |
| 3 | CleanBrowsing DoH → instagram.com |
| 4 | CleanBrowsing DoT → cdninstagram.com |
| 5 | CleanBrowsing DoH → cdninstagram.com |
| 6 | sw.ext.io DoT → rutor.is & rutor.info |
| 7 | Malw Link DoH → ntc.party |
| 8 | Xbox-DNS DoT → gql.twitch.tv & usher.ttvnw.net |
| 9 | Xbox-DNS DoH → gql.twitch.tv & usher.ttvnw.net |
| 10 | NullsProxy DoT → Supercell (supercell.com, supercellid.com, brawlstarsgame.com, clashofclans.com, clashroyaleapp.com) |
| 11 | NullsProxy DoH → те же домены Supercell |
| 12 | Ввести свой домен и выбрать сервер |

Можно выбрать несколько пресетов через запятую (например, `1,2,4`) — конфигурация сохраняется один раз.

**Пресет 1 — Яндекс DoT для российских зон.** Одним действием привязывает три доменные зоны к базовому Яндекс DNS (без семейной фильтрации) по DNS-over-TLS: `77.88.8.8`, порт `853`, SNI `common.dot.dns.yandex.net`.

```
dns-proxy tls upstream 77.88.8.8 853 sni common.dot.dns.yandex.net domain ru
dns-proxy tls upstream 77.88.8.8 853 sni common.dot.dns.yandex.net domain su
dns-proxy tls upstream 77.88.8.8 853 sni common.dot.dns.yandex.net domain xn--p1ai
```

- `.рф` передаётся в Punycode — `xn--p1ai`.
- DNS выбирается **по доменной зоне** имени, а не по расположению сервера: сайт в `.ru`, размещённый за рубежом, пойдёт через Яндекс, а российский сервис в `.com` (например, `vk.com`) — нет.
- Остальные домены по-прежнему разрешаются текущими DNS-серверами роутера; общий DNS, другие серверы и привязки не меняются и не удаляются.
- Если `ndmc` вернул ошибку для какой-либо зоны, меню называет эту зону и не сообщает об успехе; успешно привязанные зоны сохраняются.
- Повторный выбор отправляет те же три команды, без удаления существующих записей.

- Удаление upstream-ов с сохранением конфигурации

> Нужен `ndmc` (CLI Keenetic/Netcraze).\
> При активном **Интернет-фильтре** часть DoT может помечаться как *disregarded*.

### 9. Discord: все пакеты в nfqws2

Фикс для **Discord voice/UDP** на **nfqws2-keenetic**: по умолчанию nfqws2 обрабатывает только *первые* пакеты соединения; голос Discord часто «отваливается» после установления сессии. Пункт направляет **весь** UDP Discord в nfqws2 на протяжении звонка и исключает эти порты из аппаратного/программного ускорения (PPE).

Требуется установленный **nfqws2-keenetic**. Запускает [`nfqws2_fullsession.sh`](https://github.com/rndnaame/nfqws-menu/blob/main/nfqws2_fullsession.sh) (скачивание с репозитория; при офлайне — локальная копия `/opt/etc/nfqws2-fullsession/`).

Возможности скрипта (меню / CLI):

| Команда / действие | Описание |
| --- | --- |
| **меню** (без аргументов) | интерактив: статус, включить, выключить, порты, XKeen |
| `status` | диагностика: nfqws2, правила, порты, лог |
| `apply` | включить fullsession (порты по умолчанию `19294:19344,50000:50100`; можно `PORTS=…`) |
| `remove` | выключить и удалить правила/хуки |
| `rules` / `unrules` | поставить или снять только netfilter-правила |
| `xkeen` | исключить порты Discord из списка XKeen (`port_exclude.lst`) |

Что ставится при **apply**:

- конфиг `/opt/etc/nfqws2-fullsession/fullsession.conf` (`PORTS=…`);
- init `/opt/etc/init.d/S52nfqws2-fullsession`;
- хук netfilter `/opt/etc/ndm/netfilter.d/101-nfqws2-fullsession.sh` (цепочки mangle, mark `0x40000000`, `-j PPE` bypass);
- статус в блоке «Установленные компоненты» как **nfqws2-fullsession**.

### 10. dpi-detector

Инструмент для анализа цензуры трафика в России: обнаруживает и классифицирует блокировки сайтов, хостингов и CDN (TCP16–20 блокировки), а также подмену DNS-запросов провайдером.

Актуальная версия [dpi-detector](https://github.com/Runnin4ik/dpi-detector) (ветка `rust`):

```bash
curl -fsSL https://raw.githubusercontent.com/Runnin4ik/dpi-detector/rust/install.sh | sh
```

Если бинарник уже есть (`/opt/bin/dpi-detector`) — очищает дубликаты (`/tmp`, `/opt/root`) и сразу запускает его. После установки — та же очистка дубликатов.

### 11. awg-manager

Веб-интерфейс для управления AmneziaWG VPN-туннелями на роутерах Keenetic. В тестовом режиме добавлена поддержка Sing-box (vless tcp, hysteria, trojan и др.).

Установщик [awg-compressed](https://github.com/rndnaame/awg-compressed):

```bash
curl -sL https://raw.githubusercontent.com/rndnaame/awg-compressed/main/install-compressed.sh | sh
```

В статусе: `awg-manager` или `awg-manager [+SB]` при наличии sing-box.

### 12. KeenKit

Многофункциональный скрипт, упрощающий взаимодействие с роутером на базе KeeneticOS.

- Есть `/opt/keenkit.sh` — **сразу запускает**.
- Иначе — установщик [KeenKit](https://github.com/spatiumstas/KeenKit).

### 13. usque-keenetic

Адаптация неофициального клиента Cloudflare WARP с режимом MASQUE для роутеров Keenetic / Netcraze.

Через `installer_usque.sh` (пункт меню 13 или напрямую):

```bash
curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_usque.sh | sh
```

Подменю:

1. **Установка** — пакет [usque-keenetic](https://github.com/side-effect-tm/usque-keenetic) (opkg, репозиторий `…/usque-keenetic/$ARCH`, fallback `/all`)
2. **Обновление bin** — бинарник [Diniboy1123/usque](https://github.com/Diniboy1123/usque) с GitHub Releases → `/opt/usr/bin/usque` (aarch64→arm64, mipsel→mipsle, mips→mips, x86_64→amd64)
3. **Удаление** — `opkg remove --autoremove usque-keenetic` + conf репозитория; опционально `/opt/etc/usque`

- Init: `/opt/etc/init.d/S51usque` (start | stop | restart | status)
- Конфиг: `/opt/etc/usque/usque.conf`
- Бинарник: `/opt/usr/bin/usque`

```
# Интерфейс. Определяется автоматически при установке.
# Должен быть вида opkgtun*
IFACE="opkgtun0"
```

### 14. MagiTrickle

Утилита для точечной маршрутизации сетевого трафика по заданным доменным именам.

Установка / обновление [MagiTrickle](http://bin.magitrickle.dev/):

- **Не установлен** — добавление репозитория (`add_repo.sh`) + `opkg install magitrickle` + `S99magitrickle start`
- **Установлен** → `opkg update && opkg install magitrickle` + restart сервиса
- Init: `/opt/etc/init.d/S99magitrickle` (start | stop | restart | status)
- Удаление — в п. 88 (с опциональным удалением `/opt/etc/opkg/magitrickle.conf`)

### 15. telemt / telemt-panel

Telegram MTProto-прокси на Rust (полная реализация официального алгоритма + расширения). Скрипты: [augin/telemt_script](https://github.com/augin/telemt_script) (Entware / Keenetic, рекомендуется **aarch64**).

Подменю:

```
1. Установка telemt
2. Установка telemt-panel
3. Эмуляция systemD
4. Удаление
0. Назад
```

- Установщики запускаются с привязкой к `/dev/tty` (интерактивные скрипты).
- П. 3 — эмуляция systemctl для Entware ([anch665/keendev](https://github.com/anch665/keendev) и аналоги), если нужна совместимость с unit-скриптами.
- Статус telemt / telemt-panel отображается в блоке установленных компонентов; удаление — здесь или в п. 88.

### S. Сервисные утилиты

В главном меню: клавиша **S** (или раздел «СЕРВИС»).

| Пункт | Действие |
| --- | --- |
| 1 | **Сжать bin/sbin (UPX)** — `upx --lzma --best` для `/opt/bin`, `/opt/sbin`, `/opt/usr/bin`, `/opt/libexec` (при необходимости ставит `upx`) |
| 2 | **Dropbear fix** — правки conf/init Entware dropbear (с опцией сброса пароля root или без) |
| 3 | **Починить OPKG** — снятие залипших lock opkg, дедуп `src/gz` entware/keendev, починка битого `status` (NUL → segfault), выравнивание arch-path в `/opt/etc/opkg.conf` |
| U | **Обновить все пакеты** (клавиша **U** из главного меню / сервиса). Порядок: основной репо **bin.entware.net** → `opkg update` → `busybox`/`poorbox` → AdGuard (если есть) → **awg-manager UPX** авто через [awg-compressed](https://github.com/rndnaame/awg-compressed) (`INSTALL_AWG=1`, при наличии sing-box ещё `INSTALL_SB=1`) + `opkg flag hold` → mass `opkg upgrade` → dpi-detector при новой версии. Вывод opkg приглушён; этапы **1/6…6/6**. |

### 16. TG WS Proxy Rust (tg-ws-proxy-rs)

Через `installer_tgws_rs.sh` (пункт меню **16** или напрямую):

```sh
curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_tgws_rs.sh | sh
```

[tg-ws-proxy-rs](https://github.com/valnesfjord/tg-ws-proxy-rs) — MTProto-прокси на Rust. В opkg его нет: ставит штатный `install.sh` проекта, он же пишет конфиг и Entware-инициализацию. Установщик меню добавляет:

- **секрет и порт прежней Go-установки** (если осталась) — ссылки `tg://` не меняются, Go-сервис останавливается и снимается с автозапуска;
- **выбор сборки** — обычная или компактная (UPX), таблицей: размер на флеше и потребление памяти. По умолчанию обычная; компактная — когда флеш-памяти мало (образ распаковывается в ОЗУ и не вытесняется);
- **подбор параметров по замерам** — CF-домены и варианты лестницы проверяются штатной пробой бинаря, затем выводится список с временем каждого, и путь выбираете вы (Enter — быстрейший);
- **проверка связи до выдачи ссылки** — `resPQ` от DC Telegram, то есть вся цепочка, а не «порт открыт».

Конфиги: `/opt/etc/tg-ws-proxy-rs/config.conf` (`DC_IP`, `CF_DOMAIN`, `EXTRA_ARGS`), `secret.conf` рядом с ним. Init: `/opt/etc/init.d/S99tg-ws-proxy-rs` (start / stop / status / restart)

Проба есть с версии **2.4.5**; у более старого бинаря меню предложит обновиться.

Секрет меню пишет само, до установки: генератор секрета в `install.sh` проекта использует `od -An`, которого BusyBox не знает, и на боксе без готового секрета установка падает. Если секрет остался от Go-версии, переносится он — тогда ссылки клиентов не меняются.

### 17. firc

[firc](https://github.com/hoaxisr/firc) — утилита для **точечной маршрутизации трафика по доменам** (FakeIP) на Keenetic / Entware. Нужные домены заворачиваются в выбранный интерфейс (VPN / туннель), остальной трафик не затрагивается.

Через `installer_firc.sh` (пункт меню **17** или напрямую):

```sh
curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_firc.sh | sh
```

1. **Установка / обновление firc** — `src/gz hoaxisr` → `/opt/etc/opkg/awg_manager.conf` ([repo.hoaxisr.ru](https://repo.hoaxisr.ru/)), затем `opkg update && opkg install firc`
2. **Удаление firc** — `opkg remove` (`awg_manager.conf` не трогаем)
3. **Полное меню** — remote `installer_firc.sh` (диагностика и т.п.)

- Init: `/opt/etc/init.d/S99firc` (start | stop | restart | status)
- WebUI: обычно порт **666**
- Целевая платформа: **KeeneticOS 4+/5+** (ядро вроде `4.9-ndm-5`), aarch64 / mipsel / mips
- Статус в блоке установленных компонентов; удаление — здесь или в п. 88

### 18. warpscout

[warpscout](https://github.com/vernette/warpscout) — поиск рабочих эндпоинтов **Cloudflare WARP** (нода, регион выхода, ping/loss). Полезно, когда часть нод (например `DME`) режется DPI.

Через `installer_warpscout.sh` (пункт меню **18** или напрямую):

```sh
curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_warpscout.sh | sh
```

1. **Установка / обновление** — бинарник в `/opt/bin/warpscout`  
   - **aarch64**: релиз `warpscout_*_linux_arm64.tar.gz` (v0.16.1)  
   - **mipsel**: готовый бинарник из `warpscout/warpscout-0.16.1-mipsle` в этом репозитории
2. **Создать аккаунт** — `warpscout register` → `/opt/root/warpscout-account.json`
3. **Сканирование (AWG)** — `warpscout scan -p awg -P -o /opt/root/warpscout-awg.list -conf /opt/root/warpscout-awg.conf` (отчёт + готовый conf; подхват junk из п.4)
4. **Автоматический поиск / apply junk (find-junk)** — `warpscout find-junk -gen-i1 …` → `/opt/root/warpscout-junk.env`; применение к conf и/или **replace** в туннель (Jc/Jmin/Jmax/I1)
5. **Применить conf в awg-manager** — выбор endpoint (*Best endpoint per node*) → `Endpoint`/свободный `Address` → **replace** или import; имя `WARP-ARN` / `WARP-DME`; после — `start`
6. **Проверка туннеля** — интерфейс `nwg*`/`awg*` → HTTP-пробы + Cloudflare `cdn-cgi/trace`
7. **Удаление** — бинарник; по подтверждению аккаунт, list, conf, junk

### 19. Antiscan

[Antiscan](https://github.com/dimon27254/antiscan) (автор — dimon27254) блокирует IP, которые сканируют порты роутера или подбирают пароли: много соединений с одного адреса, единичные соединения с многих адресов одной подсети /24, плюс опционально пользовательские списки, геоблокировка, honeypot и списки NDMS `ip lockout-policy`.

> **Только IPv4 и только TCP.** IPv6 и UDP (например WireGuard) Antiscan не защищает.

Через `installer_antiscan.sh` (пункт меню **19** или напрямую):

```sh
curl -fsSL https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/installer_antiscan.sh | sh
```

**Требования:** Entware, компонент «Модули ядра подсистемы Netfilter» (`opkg-kmod-netfilter`; до KeeneticOS 4.3 — вместе с «Протокол IPv6»). На KeeneticOS 5.2+ Antiscan при первом запуске попросит **токен доступа RCI** (создаётся в веб-интерфейсе или CLI роутера; позже — `antiscan token set`). Зависимости пакета: `ipset`, `iptables`, `curl`, `jq`, `cron`.

Меню:

1. **Установить** — проверка компонента Netfilter (RCI `show version`, иначе по модулям `xt_recent`/`xt_multiport`), репозиторий `src/gz antiscan https://dimon27254.github.io/antiscan/all` → `/opt/etc/opkg/antiscan.conf`, `opkg update` (индекс Antiscan должен загрузиться заново — устаревший кэш opkg не принимается), `opkg install antiscan`. Если установка не удалась, добавленная запись репозитория откатывается (в чужом `antiscan.conf` убирается только дописанная строка). Уже настроенный репозиторий (в т.ч. зеркало) не перезаписывается; при недоступности можно явно выбрать зеркало `https://bin.antiscan.ru/packages/all`. Установленный пакет не переустанавливается, `--force-reinstall` и `curl | sh` не используются. Если нет `wget-ssl` / `ca-bundle` — предлагается их установить (как в официальном `install.sh`).
2. **Статус и версия** — opkg, репозиторий, служба, hook, текущие интерфейсы/порты, `antiscan status`.
3. **Запуск / остановка / перезапуск** — `antiscan start | stop | restart` с проверкой результата.
4. **WAN-интерфейсы и TCP-порты** — меняет только `ISP_INTERFACES`, `PORTS`, `PORTS_FORWARDED` (бэкап `ascn.conf.bak.*`, остальные строки не трогаются), затем `antiscan reload`. Результат проверяется по iptables (только чтение `-L`/`-C`/`-S`): переходы из `INPUT`/`FORWARD` и содержимое цепочек по включённым режимам (DROP и наполнение `ascn_ips` для IPS, правила honeypot и пользовательских списков). `reload` удаляет старые правила до применения новых и может вернуть 0 без них, а `add_rules` заполняет цепочку только при её создании. Если защита неполная — по шагам с подтверждением: снять зависший `/tmp/ascn.lock` (только если процесса `reload` нет), `antiscan update_rules` (добавляет недостающие переходы, блокировки сохраняются; для пустой цепочки не предлагается), `antiscan restart` с текущим `ascn.conf` (если цепочка есть, но без правил), затем прежний `ascn.conf` + `antiscan restart`; каждый шаг проверяется. Firewall целиком не очищается.
5. **Открыть конфигурацию** — `antiscan edit config` (nano / vim / vi; Antiscan сам проверяет файл и применяет его).
6. **Заблокированные IP и подсети** — `antiscan list ips | subnets` (+ `honeypot` / `ndm_lockout`, если включены).
7. **Обновить** — `opkg upgrade antiscan` только при наличии новой версии; настройки сохраняются (conffiles), перед обновлением бэкап.
8. **Удалить** — подтверждение, `antiscan stop`, `opkg remove antiscan` (prerm/postrm убирают службу, symlink и задачи cron). Настройки по выбору копируются в `/opt/etc/antiscan-backup-*` (каталог `700`, файлы `600`: пара `.tkn` + `.k` позволяет восстановить токен RCI) или удаляются (только известные файлы Antiscan). Зависимости и другие пакеты не удаляются, `--autoremove` не используется.

**Первая настройка.** Пакет запускает Antiscan сразу после установки со значениями по умолчанию (`ISP_INTERFACES="eth3"`, порты `22,80,443`). Поэтому установщик сразу предлагает настройку; если `eth3` не похож на WAN этого роутера — предлагает остановить Antiscan до настройки. Существующий `ascn.conf` (не по умолчанию) никогда не меняется автоматически.

- **ISP_INTERFACES** — unix-имена интернет-подключений (`eth3`, `ppp0`, `eth2.2`, …; до 10). Подсказка строится из маршрутов `default` и интерфейсов RCI с `global: true` (`show interface <имя> system-name`), но сохраняется только то, что подтвердил пользователь. Если ничего не найдено — ручной ввод.
- **PORTS** — TCP-порты служб **самого роутера**, доступных из интернета.
- **PORTS_FORWARDED** — порты **назначения на устройстве LAN** (поле «Направлять на порт»), а не внешний порт правила. Antiscan проверяет их в `FORWARD`, уже после DNAT.

Ввод проверяется по тем же правилам, что и в Antiscan (имена `[a-zA-Z][a-zA-Z0-9_.:-]{1,14}`, порты `1–65535`, до 15, диапазоны `N:M`); значения не исполняются и не передаются в `eval`. Honeypot, геоблокировка и прочие режимы установщиком не включаются.

**Совместимость с nfqws / nfqws2.** Antiscan добавляет правила только в таблицу `filter` (цепочки `ANTISCAN` / `ANTISCAN_HONEYPOT`, переходы из `INPUT`/`FORWARD` по `-i <WAN> -p tcp --dports …`) и восстанавливает их hook-ом `/opt/etc/ndm/netfilter.d/099-ascn.sh` только для `table=filter`. nfqws-keenetic и nfqws2-keenetic работают в таблицах `mangle`/`nat` и их hook обрабатывает только `mangle`/`nat`, поэтому правила не пересекаются и перезапуск nfqws не нужен. Установщик сам iptables/ipset не изменяет (при удалении только читает, осталась ли цепочка `ANTISCAN`).

**Ограничения и риски:**

- Лимиты (по умолчанию 20 одновременных / 15 новых соединений за 30 с) действуют на все адреса, включая ваши: удалённое администрирование, VPN-клиенты поверх TCP, сервисы за пробросом с множеством соединений (веб-сервер, NAS, торрент-порт) могут попасть в блокировку на 10 суток. Доверенные адреса добавляйте в `ascn_custom_exclude.txt` (`antiscan edit custom_exclude`, `USE_CUSTOM_EXCLUDE_LIST="1"`). Установщик предупреждает, если вы подключены по SSH извне.
- Если в `ISP_INTERFACES` указан VPN/туннель, лимиты действуют и на входящие соединения через него.
- Диапазоны портов, пересекающиеся с 32768–60999, захватывают ответы на исходящие соединения — установщик предупреждает об этом.
- `antiscan stop` / `restart` снимают накопленные блокировки, если не включено `SAVE_IPSETS`.
- `postinst` пакета при отсутствии каталога crontabs настраивает и запускает cron (меняет `/opt/etc/init.d/S10cron`) — это поведение самого пакета.

### 77. Change language

Мгновенное переключение интерфейса **ru ↔ en** (файл `/opt/etc/nfqws-menu/nfqws-menu.lang`). При первом запуске файл по старому пути `/opt/etc/nfqws-menu.lang` переносится в новый каталог.

### 88. Удаление пакетов

Показывает установленные компоненты и позволяет удалить выборочно:

```
Удаление:
  [N] nfqws2-keenetic / nfqws-keenetic-web / dpi-detector /
      awg-manager / tg-ws-proxy-rs / usque-keenetic / firc /
      magitrickle / opera-proxy / KeenKit / telemt
  [a] Удалить все пакеты NFQWS
  [b] Удалить резервные копии (.bak.* / *-opkg)
  [0] Назад
```

- Пакеты NFQWS — `opkg remove --autoremove`
- **dpi-detector** — бинарник (`/opt/bin/dpi-detector` и др.)
- **awg-manager** — `opkg remove` + `rm -rf /opt/etc/awg-manager`
- **tg-ws-proxy-rs** — бинарь и init; конфиг и секрет удаляются по подтверждению
- **usque-keenetic** — `opkg remove --autoremove` + `/opt/etc/opkg/usque-keenetic.conf`
- **firc** — `opkg remove --autoremove` (+ stop `S99firc`; `awg_manager.conf` не удаляем)
- **magitrickle** — `opkg remove` + запрос на удаление `/opt/etc/opkg/magitrickle.conf`
- **KeenKit** — удаление `/opt/keenkit.sh`
- **a)** — все пакеты NFQWS + dpi-detector
- **b)** — `*.bak.*`, `*.conf-opkg`, `*.list-opkg` в `/opt/etc/nfqws/`, `/opt/etc/nfqws2/`, `/opt/etc/nfqws2/lists/`

### 99. Обновить скрипт

Скачивает свежую версию из репозитория, перезаписывает `/opt/nfqws-menu.sh`, обновляет symlink `/opt/bin/menu`, сразу перезапускает меню (`exec`).

---

## Changelog

Полная история: **[CHANGELOG.md](CHANGELOG.md)**.

<details>
<summary><strong>Недавние версии (0.11.x / 0.10.x)</strong> — нажмите, чтобы развернуть</summary>

### 0.11.03
- **U / awg UPX auto** — при наличии `sing-box` рядом с awg-manager: `INSTALL_AWG=1 INSTALL_SB=1` (оба пакета через awg-compressed)

### 0.11.02
- линейка **0.11.x** (см. [CHANGELOG.md](CHANGELOG.md) для полного списка)

### 0.10.35 – 0.10.36
- **U** — тихий opkg (без простыни Downloading); AWG/dpi только если remote новее; авто-UPX без tty-промптов; успех по смене версии

### 0.10.33 – 0.10.34
- **U** — этапы 1/6…6/6; awg UPX до mass upgrade + `opkg flag hold`

### 0.10.30 – 0.10.32
- **U** — порядок Entware (bin.entware.net, busybox/poorbox, AdGuard, upgrade)

### 0.10.26
- **show_installed** — `emit_opkg`, без `opkg list-installed` на каждом кадре

### 0.10.21
- **п. 18 warpscout**

### 0.10.1
- линейка **0.10.x**

</details>

## Структура репозитория

```
nfqws-menu/
├── nfqws-menu.sh          # Главный скрипт меню
├── hosts                  # Секции IP DOMAIN для п. 7 (ndmc ip host)
├── SHA256SUMS             # Хеши файлов репозитория (список стратегий без API)
├── README.md
├── .github/workflows/
│   └── sha256sums.yml     # Автообновление SHA256SUMS
└── strategies/
    ├── blobs/
    │   ├── *.bin          # Бинарные шаблоны
    │   └── SHA256SUMS     # Эталоны для проверки blobs на роутере
    ├── lists/             # Готовые списки доменов / IP
    │   ├── user.list
    │   ├── exclude.list
    │   ├── ipset.list
    │   └── ipset_exclude.list
    ├── nfqws1/            # Стратегии для nfqws-keenetic (v1)
    └── nfqws2/            # Стратегии для nfqws2-keenetic (v2)
```

### Как добавить свою стратегию

1. Файл `имя.conf` в `strategies/nfqws1/` или `strategies/nfqws2/`.
2. Полный конфиг (`ISP_INTERFACE=`, `NFQWS_ARGS=` / `NFQWS_BASE_ARGS=` и т.д.).
3. При необходимости — `.bin` в `strategies/blobs/`, списки в `strategies/lists/`.
4. После push workflow обновит `SHA256SUMS` / `strategies/blobs/SHA256SUMS`; скрипт подхватит стратегию из SUMS (или через GitHub API).

---

## Требования (Keenetic / Netcraze)

1. Установлен **Entware** (внутренняя память или USB).
2. В веб-интерфейсе — **модули ядра Netfilter** (`OPKG → Kernel modules for Netfilter`).\
   На старых прошивках компонент появляется после включения IPv6.
3. Рекомендуется отключить DNS провайдера и настроить DoT/DoH.
4. Команды выполняются **в среде Entware**, не в CLI Keenetic.

---

## Полезные команды вручную

```bash
# Статус сервисов
/opt/etc/init.d/S51nfqws status          # v1
/opt/etc/init.d/S51nfqws2 status         # v2
/opt/etc/init.d/S99tg-ws-proxy-rs status # TG WS Proxy Rust
/opt/etc/init.d/S51usque status          # usque
/opt/etc/init.d/S99magitrickle status    # MagiTrickle

# Порт веб-интерфейса
netstat -lnt | grep ':90'

# Перезапуск
/opt/etc/init.d/S51nfqws restart
/opt/etc/init.d/S51nfqws2 restart
/opt/etc/init.d/S99tg-ws-proxy-rs restart
/opt/etc/init.d/S51usque restart
/opt/etc/init.d/S99magitrickle restart

# Информация о пакете
opkg info nfqws-keenetic
opkg info nfqws2-keenetic
opkg info nfqws-keenetic-web
opkg info usque-keenetic
opkg info magitrickle

# Конфиги
vi /opt/etc/nfqws/nfqws.conf
vi /opt/etc/nfqws2/nfqws2.conf
vi /opt/etc/tg-ws-proxy-rs/config.conf
vi /opt/etc/tg-ws-proxy-rs/secret.conf
vi /opt/etc/usque/usque.conf

# Интерфейс провайдера
ip route | grep ^default
# или
route | grep ^default

# DNS-proxy (DoT/DoH)
ndmc -c show dns-proxy

# Быстрый запуск меню
menu
```

---

## Лицензия / отказ от ответственности

Материалы подготовлены в ознакомительных и научно-технических целях.\
Использование на свой страх и риск. Автор не несёт ответственности за последствия.

Стратегии адаптированы на основе [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube),\
подготовлены [@Nare51](https://github.com/Nare51) с использованием искусственного интеллекта.\
Официальные пакеты NFQWS: [nfqws](https://github.com/nfqws).