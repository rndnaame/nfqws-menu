# NFQWS-MENU

Интерактивное меню установки и управления пакетами **nfqws-keenetic**, **nfqws2-keenetic** и **nfqws-keenetic-web** для роутеров **Keenetic / Netcraze** с **Entware**.

Репозиторий также служит хранилищем готовых **стратегий** обхода DPI, **blobs** и **lists**.

- Скрипт: [`nfqws-menu.sh`](nfqws-menu.sh) (текущая версия **0.5.12**)
- Стратегии: [`strategies/`](strategies/)

### Официальные проекты

| Пакет | Репозиторий |
|-------|-------------|
| nfqws-keenetic (v1) | https://github.com/nfqws/nfqws-keenetic |
| nfqws2-keenetic (v2) | https://github.com/nfqws/nfqws2-keenetic |
| Веб-интерфейс | https://github.com/nfqws/nfqws-keenetic-web |

### Источник стратегий

Стратегии в этом репозитории сделаны на базе проекта  
**[Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube)**  
и адаптированы под формат конфигов `nfqws-keenetic` / `nfqws2-keenetic`.

Подготовлены пользователем **[@Nare51](https://github.com/Nare51)** с использованием искусственного интеллекта.

---

## Быстрый старт

Подключитесь к Entware (SSH, порт 222 или 22, логин `root`):

```bash
# Скачать и запустить
wget -O /opt/nfqws-menu.sh https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh
chmod +x /opt/nfqws-menu.sh
sh /opt/nfqws-menu.sh
```

или одной строкой:

```bash
wget -O /opt/nfqws-menu.sh https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh && chmod +x /opt/nfqws-menu.sh && sh /opt/nfqws-menu.sh
```

После первого запуска создаётся symlink для быстрого старта:

```bash
menu
```

(` /opt/bin/menu` → `/opt/nfqws-menu.sh` )

---

## Что делает меню

При запуске скрипт:

1. Определяет архитектуру процессора (`aarch64` / `mipsel` / `mips` …) — с кэшированием.
2. Показывает **только установленные** компоненты (версии и статус):
   - пакеты NFQWS / web;
   - dpi-detector, awg-manager (`[+SB]` при наличии sing-box), KeenKit;
   - другие сервисы из `/opt/etc/init.d/`;
   - **⚡** — сервис запущен.
3. Предлагает меню:

```
[::]  КОМПОНЕНТЫ
      1.  Установить NFQWS/NFQWS2
      2.  Установить веб-интерфейс

[::]  СТРАТЕГИИ/СПИСКИ
      3.  Выбор стратегии
      4.  Обновить IPSet List
      5.  Обход блокировки DoT/DoH
      6.  Управление DoT/DoH

[::]  УТИЛИТЫ
      10. dpi-detector
      11. awg-manager
      12. KeenKit
      13. TG WS Proxy Go

[::]  СЕРВИС
      77. Change language
      88. Удаление пакетов

      99. Обновить скрипт
      00. Выход
```

Пример блока статуса:

```
Установленные компоненты:
  nfqws2-keenetic        1.2.6 ⚡
  nfqws-keenetic-web     3.0.23 ⚡
  dpi-detector           5.0.0-alpha.6
  awg-manager [+SB]      2.18.0
  KeenKit                2.8.7
```

### 1. Установка NFQWS / NFQWS2

- Выбор версии: **nfqws-keenetic** (v1) или **nfqws2-keenetic** (v2).
- Установка зависимостей (`ca-certificates`, `wget-ssl`, удаление `wget-nossl`).
- Добавление официального **универсального** opkg-репозитория.
- Установка пакета.
- Предложение установить веб-интерфейс.

> При установке v2, если уже стоит v1, скрипт предложит удалить старый пакет (рекомендуется).

### 2. Установка веб-интерфейса

Устанавливает `nfqws-keenetic-web` (lighttpd + PHP на порту **90**).

- Адрес: `http://<IP-роутера>:90`
- Логин/пароль — учётные данные Entware (по умолчанию `root` / `keenetic`).

### 3. Установка стратегии

- Если ни одна версия NFQWS не установлена — предлагает установить.
- Показывает список `.conf` из:
  - `strategies/nfqws1/` — для v1
  - `strategies/nfqws2/` — для v2
- Скачивает выбранный файл, делает **бэкап** текущего конфига и применяет стратегию.
- После применения выполняет пост-настройку:

#### ISP_INTERFACE

Определяет интерфейс провайдера из default route:

```bash
ip route | grep ^default
# или
route | grep ^default
```

Сравнивает с `ISP_INTERFACE` в конфиге и при необходимости предлагает установить правильное значение (например `ppp0`, `eth3`).

#### Проверка blobs

Парсит **установленный** конфиг и находит все используемые `.bin`:

- `--blob=name:@/path/file.bin`
- `--dpi-desync-fake-tls=/path/file.bin`
- `--dpi-desync-fake-quic=/path/file.bin`
- любые абсолютные пути `*.bin`

Для каждого файла показывает `OK` или `нет`.  
Отсутствующие предлагает скачать из `strategies/blobs/` (по имени файла).

#### Обновление lists

Спрашивает, нужно ли обновить списки из `strategies/lists/`:

- `user.list`
- `exclude.list`
- `ipset.list`
- `ipset_exclude.list`

`auto.list` **не трогается** — его заполняет сам демон.

После всех шагов соответствующий сервис перезапускается.

### 4. Обновление IPSet List

Скачивает актуальный IP/CIDR-список из проекта  
[Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube):

```
https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt
```

и записывает его в `ipset.list` установленной версии:

| Версия | Путь |
|--------|------|
| nfqws-keenetic (v1) | `/opt/etc/nfqws/ipset.list` |
| nfqws2-keenetic (v2) | `/opt/etc/nfqws2/lists/ipset.list` |

- Делает бэкап существующего файла
- Убирает пустые строки и комментарии
- Перезапускает соответствующий сервис  
- Если установлены обе версии — можно обновить обе сразу

### 5. Обход блокировки DoT/DoH

Доступно при установленном **nfqws2-keenetic**.

Добавляет в `NFQWS_ARGS_CUSTOM` стратегию обхода блокировки **DoT/DoH** публичных DNS-серверов (Cloudflare, Google, AdGuard, NextDNS, Quad9 и др.):

- TLS (TCP 443/853) и QUIC (UDP 853)
- Список доменов DNS-сервисов в `--hostlist-domains`
- Делает бэкап конфига, дописывает стратегию (или создаёт `NFQWS_ARGS_CUSTOM`, если пустой)
- Добавляет порт `853` в `TCP_PORTS` / `UDP_PORTS` при необходимости
- Перезапускает `S51nfqws2`

### 6. Управление DoT/DoH

Управление DNS-over-TLS / DNS-over-HTTPS на стороне **Keenetic** через `ndmc` (dns-proxy).

Подменю:

```
1) Добавить DoT сервер(ы)
2) Добавить DoH сервер(ы)
3) Привязать домен к DNS (Пресеты)
4) Удалить сервер(ы)
0) Назад
```

Возможности:

- Просмотр текущих DoT/DoH-серверов и персональных привязок к доменам
- Добавление DoT/DoH из пресетов (Яндекс, Cloudflare, Quad9, CleanBrowsing, OpenDNS, DNS.SB, dns0.eu, OpenNameServer, японские DNS, Proxy-DNS и др.) или вручную
- Быстрая привязка доменов (instagram.com, rutor, ntc.party и свой вариант)
- Удаление выбранных upstream-ов с сохранением конфигурации

> Требуется наличие `ndmc` (штатный CLI Keenetic/Netcraze).  
> При активном **Интернет-фильтре** часть DoT-серверов может добавляться в конфиг, но помечаться как *disregarded*.

### 10. dpi-detector

Устанавливает актуальную версию [dpi-detector](https://github.com/Runnin4ik/dpi-detector) (ветка `rust`):

```bash
curl -fsSL https://raw.githubusercontent.com/Runnin4ik/dpi-detector/rust/install.sh | sh
```

Если бинарник уже есть (`/opt/bin/dpi-detector`) — сразу запускает его.  
Версия в статусе меню берётся из `dpi-detector --version`.

### 11. awg-manager

Запускает установщик [awg-compressed](https://github.com/rndnaame/awg-compressed) (AmneziaWG manager):

```bash
curl -sL https://raw.githubusercontent.com/rndnaame/awg-compressed/main/install-compressed.sh | sh
```

В статусе: `awg-manager` или `awg-manager [+SB]`, если есть  
`/opt/etc/awg-manager/singbox/sing-box`.

### 12. KeenKit

- Если есть `/opt/keenkit.sh` — **сразу запускает** его (без установки).
- Иначе запускает установщик [KeenKit](https://github.com/spatiumstas/KeenKit):

```bash
curl -L -s "https://raw.githubusercontent.com/spatiumstas/KeenKit/main/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```

Версия в статусе — из `SCRIPT_VERSION` в `/opt/keenkit.sh`.

### 13. TG WS Proxy Go

Установка / обновление [tg-ws-proxy](https://github.com/spatiumstas/tg-ws-proxy-go) (Telegram WebSocket Proxy).

- Если пакет **уже установлен** → `opkg update && opkg upgrade tg-ws-proxy`
- Если **не установлен** → добавление репозитория feedly + `opkg install tg-ws-proxy`:

```bash
curl -fsSL https://raw.githubusercontent.com/spatiumstas/feedly/main/add-repo.sh | sh
opkg install tg-ws-proxy
```

После установки/обновления выводится справочная информация:

```
# Entware (KeeneticOS):
#   /opt/etc/tg-ws-proxy/config.conf
#   /opt/etc/tg-ws-proxy/secret.conf
https://github.com/spatiumstas/tg-ws-proxy-go

SECRET должен быть строкой из 32 hex-символов. Если оставить пустым, он будет автоматически сгенерирован при запуске.
DC_IP_DEFAULT и DC_IP_DEFAULT_POOL — глобальные значения по умолчанию для DC (2,4).
EXTRA_ARGS используется для переопределений по DC и дополнительных флагов, см. CFProxy.
Полный список доступных команд: --help.
FAKE_TLS_DOMAIN включает режим Fake TLS (ee secret link). Оставьте пустым для стандартного режима dd.
CFPROXY_DOMAINS — локальный список fallback-доменов.
CFPROXY_DOMAINS_URL — значение по умолчанию/зеркало

# Entware (KeeneticOS)
/opt/etc/init.d/S99tg-ws-proxy (start / stop / status / restart)
```

### 77. Change language

Мгновенное переключение интерфейса **ru ↔ en** (сохраняется в `/opt/etc/nfqws-menu.lang`).

### 88. Удаление пакетов

Показывает установленные компоненты и позволяет удалить выборочно:

```
Удаление:
  1) nfqws2-keenetic
  2) nfqws-keenetic-web
  3) dpi-detector
  4) awg-manager
  5) tg-ws-proxy
  a) Удалить все пакеты NFQWS
  b) Удалить резервные копии (.bak.* / *-opkg)
  0) Назад
```

- Пакеты NFQWS — через `opkg remove --autoremove`
- **dpi-detector** — бинарник (`/opt/bin/dpi-detector` и др.)
- **awg-manager** — `opkg remove awg-manager` и `rm -rf /opt/etc/awg-manager`
- **tg-ws-proxy** — `opkg remove tg-ws-proxy` + запрос на удаление репозитория `/opt/etc/opkg/feedly.conf`
- **a)** — все пакеты NFQWS + dpi-detector
- **b)** — резервные копии `*.bak.*`, `*.conf-opkg`, `*.list-opkg`  
  в `/opt/etc/nfqws/`, `/opt/etc/nfqws2/`, `/opt/etc/nfqws2/lists/`

### 99. Обновить скрипт

Скачивает свежую версию `nfqws-menu.sh` из репозитория:

```
https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh
```

- Перезаписывает текущий файл **без backup**
- Обновляет symlink `/opt/bin/menu`
- Сразу перезапускает меню (`exec`)
- Рекомендуемый путь: `/opt/nfqws-menu.sh`

---

## Changelog

### 0.5.12

- **Удаление tg-ws-proxy** (п. 88) — `opkg remove tg-ws-proxy` + запрос на удаление `/opt/etc/opkg/feedly.conf`

### 0.5.11

- **TG WS Proxy Go** (п. 13) — установка/обновление `tg-ws-proxy` через репозиторий feedly; вывод справки по конфигам и init-скрипту

### 0.4.0 → 0.5.x

- **Управление DoT/DoH** (п. 6) — просмотр, добавление, привязка доменов и удаление через `ndmc`
- Исправления DNS-меню: удаление DoT, корректный разбор списка серверов
- Быстрый запуск: `menu` → `/opt/bin/menu`
- Утилиты: **awg-manager** (11), **KeenKit** (12); удаление — п. **88** (в т.ч. awg-manager)
- Блок статуса: только установленное; dpi-detector, awg-manager `[+SB]`, KeenKit, сервисы `init.d`
- Компактный вид: версия без префикса, **⚡** для запущенных
- Ускорение отрисовки (кэш opkg / процессов / архитектуры)
- Переключение языка интерфейса (п. 77)

---

## Структура репозитория

```
nfqws-menu/
├── nfqws-menu.sh          # Главный скрипт меню
├── README.md
└── strategies/
    ├── blobs/             # Бинарные шаблоны (*.bin), используемые стратегиями
    ├── lists/             # Готовые списки доменов / IP
    │   ├── user.list
    │   ├── exclude.list
    │   ├── ipset.list
    │   └── ipset_exclude.list
    ├── nfqws1/            # Стратегии для nfqws-keenetic (v1) — *.conf
    └── nfqws2/            # Стратегии для nfqws2-keenetic (v2) — *.conf
```

### Как добавить свою стратегию

1. Положите файл `имя.conf` в `strategies/nfqws1/` или `strategies/nfqws2/`.
2. Файл должен быть **полным конфигом** (содержать `ISP_INTERFACE=`, `NFQWS_ARGS=` / `NFQWS_BASE_ARGS=` и т.д.).
3. При необходимости добавьте нужные `.bin` в `strategies/blobs/` и списки в `strategies/lists/`.
4. Закоммитьте и запушьте — скрипт подхватит новый файл через GitHub API.

Стратегии в репозитории основаны на [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube),  
подготовлены [@Nare51](https://github.com/Nare51) с использованием ИИ.

---

## Требования (Keenetic / Netcraze)

Перед использованием убедитесь:

1. Установлен **Entware** (на внутреннюю память или USB).
2. В веб-интерфейсе роутера установлены **модули ядра Netfilter**  
   (`OPKG → Kernel modules for Netfilter`).  
   На старых прошивках компонент появляется после включения IPv6.
3. Рекомендуется отключить DNS провайдера и настроить DoT/DoH.
4. Все команды выполняются **в среде Entware**, а не в CLI Keenetic.

---

## Полезные команды вручную

```bash
# Статус сервисов
/opt/etc/init.d/S51nfqws status          # v1
/opt/etc/init.d/S51nfqws2 status         # v2
/opt/etc/init.d/S99tg-ws-proxy status    # TG WS Proxy

# Порт веб-интерфейса
netstat -lnt | grep ':90'

# Перезапуск
/opt/etc/init.d/S51nfqws restart
/opt/etc/init.d/S51nfqws2 restart
/opt/etc/init.d/S99tg-ws-proxy restart

# Информация о пакете
opkg info nfqws-keenetic
opkg info nfqws2-keenetic
opkg info nfqws-keenetic-web
opkg info tg-ws-proxy

# Конфиги
vi /opt/etc/nfqws/nfqws.conf             # v1
vi /opt/etc/nfqws2/nfqws2.conf           # v2
vi /opt/etc/tg-ws-proxy/config.conf
vi /opt/etc/tg-ws-proxy/secret.conf

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

Материалы подготовлены в ознакомительных и научно-технических целях.  
Использование на свой страх и риск. Автор не несёт ответственности за последствия.

Стратегии адаптированы на основе [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube),  
подготовлены [@Nare51](https://github.com/Nare51) с использованием искусственного интеллекта.  
Официальные пакеты NFQWS: [nfqws](https://github.com/nfqws).
