# NFQWS-MENU

Интерактивное меню установки и управления пакетами **nfqws-keenetic**, **nfqws2-keenetic** и **nfqws-keenetic-web** для роутеров **Keenetic / Netcraze** с **Entware**.

Репозиторий также служит хранилищем готовых **стратегий** обхода DPI.

- Скрипт: [`nfqws-menu.sh`](nfqws-menu.sh)
- Стратегии: [`strategies/`](strategies/)

Официальные проекты:

| Пакет | Репозиторий |
|-------|-------------|
| nfqws-keenetic (v1) | https://github.com/nfqws/nfqws-keenetic |
| nfqws2-keenetic (v2) | https://github.com/nfqws/nfqws2-keenetic |
| Веб-интерфейс | https://github.com/nfqws/nfqws-keenetic-web |

---

## Быстрый старт

Подключитесь к Entware (SSH, порт 222 или 22, пользовательн `root`):

```bash
# Скачать и запустить
wget -O /tmp/nfqws-menu.sh https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh
chmod +x /tmp/nfqws-menu.sh
sh /tmp/nfqws-menu.sh
```

или одной строкой:

```bash
sh -c "$(wget -qO- https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh)"
```

---

## Что делает меню

При запуске скрипт:

1. Определяет архитектуру процессора (`aarch64` / `mipsel` / `mips` …).
2. Показывает установленные пакеты, их версии и статус (запущен / остановлен).
3. Предлагает меню:

```
1. Установка NFQWS, NFQWS2
2. Установка веб-интерфейса
3. Установка стратегии
4. Удаление NFQWS, NFQWS2
00. Выход          ← по умолчанию (Enter)
```

### 1. Установка NFQWS / NFQWS2

- Выбор версии: **nfqws-keenetic** (v1) или **nfqws2-keenetic** (v2).
- Установка зависимостей (`ca-certificates`, `wget-ssl`, удаление `wget-nossl`).
- Добавление официального **универсального** opkg-репозитория.
- Установка пакета.
- Предложение установить веб-интерфейс.

> При установке v2, если уже стоит v1, скрипт предложит удалить старый пакет (рекомендуется).

### 2. Установка веб-интерфейса

Устанавливает `nfqws-keenetic-web`.

- Адрес: `http://<IP-роутера>:90`
- Логин/пароль — учётные данные Entware (по умолчанию `root` / `keenetic`).

### 3. Установка стратегии

- Если ни одна версия NFQWS не установлена — предлагает установить.
- Показывает список `.conf`-файлов из каталогов:
  - `strategies/nfqws1/` — для первой версии
  - `strategies/nfqws2/` — для второй версии
- Скачивает выбранный файл, делает бэкап текущего конфига и применяет стратегию.
- Перезапускает соответствующий сервис.

### 4. Удаление

Показывает установленные компоненты и позволяет удалить выборочно или всё сразу (`opkg remove --autoremove`).

---

## Структура репозитория

```
nfqws-menu/
├── nfqws-menu.sh          # Главный скрипт меню
├── README.md
└── strategies/
    ├── blobs/             # Бинарные шаблоны (tls_clienthello, quic_initial и т.п.)
    ├── lists/             # Готовые списки доменов / IP
    ├── nfqws1/            # Стратегии для nfqws-keenetic (v1) — файлы *.conf
    └── nfqws2/            # Стратегии для nfqws2-keenetic (v2) — файлы *.conf
```

### Как добавить свою стратегию

1. Положите файл `имя.conf` в `strategies/nfqws1/` или `strategies/nfqws2/`.
2. Файл может быть:
   - **полным конфигом** (содержит `ISP_INTERFACE=`, `NFQWS_ARGS=` и т.д.) — тогда он полностью заменит текущий;
   - или только блоком параметров стратегии.
3. Закоммитьте и запушьте — скрипт подхватит новый файл через GitHub API.

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
# Статус
/opt/etc/init.d/S51nfqws status          # v1
/opt/etc/init.d/S51nfqws2 status         # v2

# Перезапуск
/opt/etc/init.d/S51nfqws restart
/opt/etc/init.d/S51nfqws2 restart

# Информация о пакете
opkg info nfqws-keenetic
opkg info nfqws2-keenetic

# Конфиги
vi /opt/etc/nfqws/nfqws.conf             # v1
vi /opt/etc/nfqws2/nfqws2.conf           # v2
```

---

## Лицензия / отказ от ответственности

Материалы подготовлены в ознакомительных и научно-технических целях.  
Использование на свой страх и риск. Автор не несёт ответственности за последствия.
