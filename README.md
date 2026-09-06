# NFQWS-MENU

Интерактивное меню установки и управления пакетами **nfqws-keenetic**, **nfqws2-keenetic** и **nfqws-keenetic-web** для роутеров **Keenetic / Netcraze** с **Entware**.

Репозиторий также служит хранилищем готовых **стратегий** обхода DPI, **blobs** и **lists**.

- Скрипт: [`nfqws-menu.sh`](nfqws-menu.sh)
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

Подготовлены пользователем **[@nare_51](https://github.com/nare_51)** с использованием искусственного интеллекта.

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
sh -c "$(wget -qO- https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh)"
```

---

## Что делает меню

При запуске скрипт:

1. Определяет архитектуру процессора (`aarch64` / `mipsel` / `mips` …).
2. Показывает установленные пакеты, версии и **реальный статус**:
   - `nfqws-keenetic` / `nfqws2-keenetic` — по init-скрипту и процессу;
   - `nfqws-keenetic-web` — по **порту 90** (`запущен (:90)` / `остановлен`).
3. Предлагает меню:

```
1.  Установка NFQWS, NFQWS2
2.  Установка веб-интерфейса
3.  Установка стратегии
4.  Обновление IPSet List
5.  Обход блокировки DoT/DoH
10. dpi-detector (rust/4Mb) (Pre-release)
11. Удаление пакетов
99. Обновить скрипт
00. Выход          ← по умолчанию (Enter)
```

### 1. Установка NFQWS / NFQWS2

- Выбор версии: **nfqws-keenetic** (v1) или **nfqws2-keenetic** (v2).
- Установка зависимостей (`ca-certificates`, `wget-ssl`, удаление `wget-nossl`).
- Добавление официального **универсального** opkg-репозитория (`/all`).
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
- Перезапускает `S51nfqws2`

### 10. dpi-detector (rust/4Mb) (Pre-release)

Устанавливает [dpi-detector](https://github.com/Runnin4ik/dpi-detector) (сборка rust, ~4Mb, pre-release v4.0.0-rust):

```bash
curl -fsSL https://github.com/Runnin4ik/dpi-detector/releases/download/v4.0.0-rust/install.sh | sh
```

### 11. Удаление пакетов

Показывает установленные компоненты и позволяет удалить выборочно:

```
Удаление:
  1) nfqws2-keenetic
  2) nfqws-keenetic-web
  3) dpi-detector
  a) Удалить все пакеты NFQWS
  b) Удалить резервные копии (.bak.* / *-opkg)
  0) Назад
```

- Пакеты NFQWS — через `opkg remove --autoremove`
- **dpi-detector** — удаление бинарника (`/opt/bin/dpi-detector` и др.)
- **a)** — все пакеты NFQWS + dpi-detector
- **b)** — резервные копии `*.bak.*`, `*.conf-opkg`, `*.list-opkg`  
  в `/opt/etc/nfqws/`, `/opt/etc/nfqws2/`, `/opt/etc/nfqws2/lists/`

### 99. Обновить скрипт

Скачивает свежую версию `nfqws-menu.sh` из репозитория:

```
https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh
```

- Перезаписывает текущий файл **без backup**
- Сразу перезапускает меню (`exec`)
- Если скрипт был запущен через pipe (`sh -c "$(wget …)"`) — сохраняет в `/opt/bin/nfqws-menu.sh`

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
подготовлены [@nare_51](https://github.com/nare_51) с использованием ИИ.

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

# Порт веб-интерфейса
netstat -lnt | grep ':90'

# Перезапуск
/opt/etc/init.d/S51nfqws restart
/opt/etc/init.d/S51nfqws2 restart

# Информация о пакете
opkg info nfqws-keenetic
opkg info nfqws2-keenetic
opkg info nfqws-keenetic-web

# Конфиги
vi /opt/etc/nfqws/nfqws.conf             # v1
vi /opt/etc/nfqws2/nfqws2.conf           # v2

# Интерфейс провайдера
ip route | grep ^default
# или
route | grep ^default
```

---

## Лицензия / отказ от ответственности

Материалы подготовлены в ознакомительных и научно-технических целях.  
Использование на свой страх и риск. Автор не несёт ответственности за последствия.

Стратегии адаптированы на основе [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube),  
подготовлены [@nare_51](https://github.com/nare_51) с использованием искусственного интеллекта.  
Официальные пакеты NFQWS: [nfqws](https://github.com/nfqws).
