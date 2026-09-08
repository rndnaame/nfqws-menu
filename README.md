# NFQWS-MENU

Интерактивное меню установки и управления пакетами **nfqws-keenetic**, **nfqws2-keenetic** и **nfqws-keenetic-web** для роутеров **Keenetic / Netcraze** с **Entware**.

Репозиторий также служит хранилищем готовых **стратегий** обхода DPI, **blobs** и **lists**.

- Скрипт: [`nfqws-menu.sh`](nfqws-menu.sh) (текущая версия **0.5.17**)
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

(`/opt/bin/menu` → `/opt/nfqws-menu.sh`)

---

## Что делает меню

При запуске скрипт:

1. Выставляет `LD_LIBRARY_PATH` для Entware; вызовы `ndmc` идут через `ndmc_cli` (системные библиотеки).
2. Определяет архитектуру процессора (`aarch64` / `mipsel` / `mips` …) — с кэшированием.
3. Показывает **только установленные** компоненты (версии и статус):
   - пакеты NFQWS / web;
   - dpi-detector, awg-manager (`[+SB]` при наличии sing-box), KeenKit;
   - другие сервисы из `/opt/etc/init.d/`;
   - **⚡** — сервис запущен.
4. Предлагает меню:

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
      14. usque-keenetic

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
- Добавление официального opkg-репозитория под архитектуру.
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

Определяет интерфейс провайдера из default route (`ip route` / `route`), сравнивает с `ISP_INTERFACE` в конфиге и при необходимости предлагает установить правильное значение.

#### Проверка blobs

Парсит установленный конфиг и находит используемые `.bin` (`--blob=…`, `--dpi-desync-fake-tls=…`, `--dpi-desync-fake-quic=…` и абсолютные пути). Отсутствующие предлагает скачать из `strategies/blobs/`.

#### Обновление lists

По запросу обновляет из `strategies/lists/`: `user.list`, `exclude.list`, `ipset.list`, `ipset_exclude.list`.  
`auto.list` **не трогается** — его заполняет демон.

После всех шагов соответствующий сервис перезапускается.

### 4. Обновление IPSet List

Скачивает актуальный IP/CIDR-список из  
[Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube)  
и записывает в `ipset.list`:

| Версия | Путь |
|--------|------|
| nfqws-keenetic (v1) | `/opt/etc/nfqws/ipset.list` |
| nfqws2-keenetic (v2) | `/opt/etc/nfqws2/lists/ipset.list` |

Бэкап, очистка пустых строк/комментариев, перезапуск сервиса. При двух установленных версиях — можно обновить обе.

### 5. Обход блокировки DoT/DoH

Только при установленном **nfqws2-keenetic**.

Добавляет в `NFQWS_ARGS_CUSTOM` стратегию обхода блокировок публичных DoT/DoH DNS (Cloudflare, Google, AdGuard, NextDNS, Quad9 и др.), при необходимости добавляет порт `853` в `TCP_PORTS` / `UDP_PORTS`, перезапускает `S51nfqws2`.

### 6. Управление DoT/DoH

Управление DNS-over-TLS / DNS-over-HTTPS на стороне **Keenetic** через `ndmc` (`ndmc_cli` — с системным `LD_LIBRARY_PATH`).

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
- Пресеты (Яндекс, Cloudflare, Quad9, CleanBrowsing, OpenDNS, DNS.SB, dns0.eu, OpenNameServer, японские DNS, Proxy-DNS и др.) или ручной ввод
- Быстрая привязка доменов (instagram.com, rutor, ntc.party и свой вариант)
- Удаление upstream-ов с сохранением конфигурации

> Нужен `ndmc` (CLI Keenetic/Netcraze).  
> При активном **Интернет-фильтре** часть DoT может помечаться как *disregarded*.

### 10. dpi-detector

Актуальная версия [dpi-detector](https://github.com/Runnin4ik/dpi-detector) (ветка `rust`):

```bash
curl -fsSL https://raw.githubusercontent.com/Runnin4ik/dpi-detector/rust/install.sh | sh
```

Если бинарник уже есть (`/opt/bin/dpi-detector`) — сразу запускает его.

### 11. awg-manager

Установщик [awg-compressed](https://github.com/rndnaame/awg-compressed) (AmneziaWG manager):

```bash
curl -sL https://raw.githubusercontent.com/rndnaame/awg-compressed/main/install-compressed.sh | sh
```

В статусе: `awg-manager` или `awg-manager [+SB]` при наличии sing-box.

### 12. KeenKit

- Есть `/opt/keenkit.sh` — **сразу запускает**.
- Иначе — установщик [KeenKit](https://github.com/spatiumstas/KeenKit).

### 13. TG WS Proxy Go

Установка / обновление [tg-ws-proxy](https://github.com/spatiumstas/tg-ws-proxy-go).

- Уже установлен → `opkg update && opkg upgrade tg-ws-proxy`
- Не установлен → репозиторий feedly + `opkg install tg-ws-proxy`

```bash
curl -fsSL https://raw.githubusercontent.com/spatiumstas/feedly/main/add-repo.sh | sh
opkg install tg-ws-proxy
```

Конфиги: `/opt/etc/tg-ws-proxy/config.conf`, `secret.conf`  
Init: `/opt/etc/init.d/S99tg-ws-proxy` (start / stop / status / restart)

### 14. usque-keenetic

Установка / обновление [usque-keenetic](https://side-effect-tm.github.io/usque-keenetic/).

- **Не установлен** — репозиторий под архитектуру + установка:

```bash
mkdir -p /opt/etc/opkg
echo "src/gz usque-keenetic https://side-effect-tm.github.io/usque-keenetic/$ARCH" > /opt/etc/opkg/usque-keenetic.conf
opkg update
opkg install usque-keenetic
```

- **Установлен** → `opkg update && opkg upgrade usque-keenetic`
- Init: `/opt/etc/init.d/S51usque` (start | stop | restart)
- Конфиг: `/opt/etc/usque/usque.conf`

```
# Интерфейс. Определяется автоматически при установке.
# Должен быть вида opkgtun*
IFACE="opkgtun0"
```

### 77. Change language

Мгновенное переключение интерфейса **ru ↔ en** (файл `/opt/etc/nfqws-menu.lang`).

### 88. Удаление пакетов

Показывает установленные компоненты и позволяет удалить выборочно:

```
Удаление:
  1) nfqws2-keenetic
  2) nfqws-keenetic-web
  3) dpi-detector
  4) awg-manager
  5) tg-ws-proxy
  6) usque-keenetic
  a) Удалить все пакеты NFQWS
  b) Удалить резервные копии (.bak.* / *-opkg)
  0) Назад
```

- Пакеты NFQWS — `opkg remove --autoremove`
- **dpi-detector** — бинарник (`/opt/bin/dpi-detector` и др.)
- **awg-manager** — `opkg remove` + `rm -rf /opt/etc/awg-manager`
- **tg-ws-proxy** — `opkg remove` + запрос на удаление `/opt/etc/opkg/feedly.conf`
- **usque-keenetic** — `opkg remove --autoremove` + `/opt/etc/opkg/usque-keenetic.conf`
- **a)** — все пакеты NFQWS + dpi-detector
- **b)** — `*.bak.*`, `*.conf-opkg`, `*.list-opkg` в `/opt/etc/nfqws/`, `/opt/etc/nfqws2/`, `/opt/etc/nfqws2/lists/`

### 99. Обновить скрипт

Скачивает свежую версию из репозитория, перезаписывает `/opt/nfqws-menu.sh`, обновляет symlink `/opt/bin/menu`, сразу перезапускает меню (`exec`).

---

## Changelog

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

- **Управление DoT/DoH** (п. 6) через `ndmc`
- Утилиты: awg-manager (11), KeenKit (12); удаление — п. 88
- Быстрый запуск `menu`, статус только установленного, ⚡, кэш opkg/процессов
- Переключение языка (п. 77)

---

## Структура репозитория

```
nfqws-menu/
├── nfqws-menu.sh          # Главный скрипт меню
├── README.md
└── strategies/
    ├── blobs/             # Бинарные шаблоны (*.bin)
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
4. После push скрипт подхватит файл через GitHub API.

---

## Требования (Keenetic / Netcraze)

1. Установлен **Entware** (внутренняя память или USB).
2. В веб-интерфейсе — **модули ядра Netfilter** (`OPKG → Kernel modules for Netfilter`).  
   На старых прошивках компонент появляется после включения IPv6.
3. Рекомендуется отключить DNS провайдера и настроить DoT/DoH.
4. Команды выполняются **в среде Entware**, не в CLI Keenetic.

---

## Полезные команды вручную

```bash
# Статус сервисов
/opt/etc/init.d/S51nfqws status          # v1
/opt/etc/init.d/S51nfqws2 status         # v2
/opt/etc/init.d/S99tg-ws-proxy status    # TG WS Proxy
/opt/etc/init.d/S51usque status          # usque

# Порт веб-интерфейса
netstat -lnt | grep ':90'

# Перезапуск
/opt/etc/init.d/S51nfqws restart
/opt/etc/init.d/S51nfqws2 restart
/opt/etc/init.d/S99tg-ws-proxy restart
/opt/etc/init.d/S51usque restart

# Информация о пакете
opkg info nfqws-keenetic
opkg info nfqws2-keenetic
opkg info nfqws-keenetic-web
opkg info tg-ws-proxy
opkg info usque-keenetic

# Конфиги
vi /opt/etc/nfqws/nfqws.conf
vi /opt/etc/nfqws2/nfqws2.conf
vi /opt/etc/tg-ws-proxy/config.conf
vi /opt/etc/tg-ws-proxy/secret.conf
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

Материалы подготовлены в ознакомительных и научно-технических целях.  
Использование на свой страх и риск. Автор не несёт ответственности за последствия.

Стратегии адаптированы на основе [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube),  
подготовлены [@Nare51](https://github.com/Nare51) с использованием искусственного интеллекта.  
Официальные пакеты NFQWS: [nfqws](https://github.com/nfqws).
