# Flowseal 1.10.4 → nfqws2 (Keenetic / Netcraze / Entware)

Стандартные стратегии из Windows-бандла [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) **1.10.4**, портированные под формат `nfqws2.conf` пакета [nfqws2-keenetic](https://github.com/nfqws/nfqws2-keenetic).

Подготовлены [@Nare51](https://github.com/Nare51) с использованием ИИ.

В каталоге **22** стандартных `.conf` (+ отдельные кастомные конфиги сообщества: `MartinBacker`, `Uvvi2`, `alt4_mod`, `eduncey`, `hardcorp74`, `krushaaa` — они не входят в комплект Flowseal).

Формат соответствует службе nfqws2: `NFQWS_BASE_ARGS`, `NFQWS_ARGS`, `NFQWS_ARGS_QUIC`, `NFQWS_ARGS_UDP`, `MODE_LIST` / `MODE_ALL` / `MODE_AUTO`, `NFQWS_EXTRA_ARGS`, `NFQWS_ARGS_IPSET`, `NFQWS_ARGS_CUSTOM` и служебные настройки. Отдельный run.sh не нужен.

## Что заложено в стандартные конфиги

- `ISP_INTERFACE="eth3"`, `IPV6_ENABLED=0`, `POLICY_NAME="nfqws"`, `POLICY_EXCLUDE=0` (поправьте интерфейс под свой роутер).
- `NFQUEUE_NUM=300`, `USER=nobody`, `CONFIG_VERSION=1`.
- По умолчанию `NFQWS_EXTRA_ARGS="$MODE_ALL"`.
- TCP/UDP-порты из образца, включая **853** (DNS).
- Три DNS-профиля в `NFQWS_ARGS_CUSTOM` (домены / IP / методы).
- Lua: `zapret-lib.lua`, `zapret-antidpi.lua`, `zapret-auto.lua` из `strategies/lua/` (официальные библиотеки bol-van/zapret2 v1.0.7, Lua API 6). Для `altorder=1` нужен также `flowseal-compat.lua`.
- Blobs: в т.ч. `ACTIVE_*`, `legacy_*`, TLS/QUIC из `strategies/blobs/`. Имя `tls_clienthello` явно привязано к `tls_clienthello_www_google_com.bin`.
- **`NFQWS_ARGS_IPSET` пустой** — общая HTTP(S)/QUIC-стратегия не копируется службой автоматически. Исходные IP-профили с собственными списками и методами вынесены в `NFQWS_ARGS_CUSTOM` (в т.ч. 8443, особенности ALT7/EXP).
- Game Filter **выключен**. Полные игровые фрагменты — в `game-profiles/*.args` (не самостоятельные конфиги; при включении не ставить диапазон 1024–65535 в начало CUSTOM).

Все 22 стратегии и цепочки ~195 профилей сохранены без смягчения repeats / split-pos / seqovl / cutoff / fooling / порядка fake и выбора blobs. Для Discord/game используются blobs из BAT 1.10.4, не произвольные alias.

Особенности отдельных стратегий:

- **ALT5** — без отдельного Google TCP и Discord-media TCP; общий IPv4 `syndata` + `multidisorder`.
- **ALT7** — отличающийся IP TCP-профиль `syndata`.
- **EXP** — свой QUIC-профиль без ограничения порта, приоритет перед Discord UDP.
- Для `multidisorder` в nfqws2 используется `multidisorder_legacy`.

## Таблица стратегий

| оригинал | конфиг | техника |
|---|---|---|
| general.bat | `general.conf` | базовая (см. файл) |
| general (ALT).bat | `alt.conf` | fake + fakedsplit, ts |
| general (ALT2).bat | `alt2.conf` | multisplit seqovl=652 pos=2 |
| general (ALT3).bat | `alt3.conf` | fake + hostfakesplit, ts |
| general (ALT4).bat | `alt4.conf` | fake + multisplit, badseq +1000 |
| general (ALT5).bat | `alt5.conf` | syndata + multidisorder |
| general (ALT6).bat | `alt6.conf` | multisplit seqovl=681 pos=1 |
| general (ALT7).bat | `alt7.conf` | multisplit pos=2,sniext+1 seqovl=679 |
| general (ALT8).bat | `alt8.conf` | fake встроенный, badseq +2 |
| general (ALT9).bat | `alt9.conf` | hostfakesplit, ts+md5sig |
| general (ALT10).bat | `alt10.conf` | fake 4pda, ts |
| general (ALT11).bat | `alt11.conf` | fake + multisplit seqovl=664 |
| general (ALT12).bat | `alt12.conf` | ALT11 + hostfakesplit для google |
| general (ALT13).bat | `alt13.conf` | fake + hostfakesplit (mail.ru), ts; Google hostfakesplit |
| general (EXP).bat | `exp.conf` | fake + multisplit seqovl=480 (stun2) |
| general (FAKE TLS AUTO).bat | `fake_tls_auto.conf` | fake + multidisorder 1,midsld |
| general (FAKE TLS AUTO ALT).bat | `fake_tls_auto_alt.conf` | fake + fakedsplit pos=1 |
| general (FAKE TLS AUTO ALT2).bat | `fake_tls_auto_alt2.conf` | fake + multisplit, badseq 10000000 |
| general (FAKE TLS AUTO ALT3).bat | `fake_tls_auto_alt3.conf` | то же, но ts |
| general (SIMPLE FAKE).bat | `simple_fake.conf` | fake + Google hostfakesplit, ts |
| general (SIMPLE FAKE ALT).bat | `simple_fake_alt.conf` | только fake, badseq +2 |
| general (SIMPLE FAKE ALT2).bat | `simple_fake_alt2.conf` | только fake (max.ru), ts |

## Как ставить (через меню или вручную)

1. Бэкап текущего `/opt/etc/nfqws2/nfqws2.conf` и своих списков.
2. Blobs из `strategies/blobs/` → `/opt/etc/nfqws2/blobs/` (меню при применении стратегии обычно предлагает недостающие).
3. Lua из `strategies/lua/` → `/opt/etc/nfqws2/lua/` (версия библиотек должна соответствовать установленному nfqws2 / zapret2; не подменяйте «чужой» major вслепую).
4. Списки: не затирайте свои `rkn.list`, `auto.list`, `user.list` и exclude пустыми шаблонами. При необходимости объедините домены из комплектных `user.list` / `google.list` со своими.
5. Один выбранный `.conf` → `/opt/etc/nfqws2/nfqws2.conf` (через пункт меню «Выбор стратегии» или вручную). Поправьте `ISP_INTERFACE`.
6. `/opt/etc/init.d/S51nfqws2 restart`

Не запускайте несколько стратегий одновременно.

### Проверка на устройстве (опционально)

Файлы в `strategies/verification/`:

```sh
sh strategies/verification/check-on-device.sh /opt/etc/nfqws2/nfqws2.conf --dry-run
sh strategies/verification/check-on-device.sh /opt/etc/nfqws2/nfqws2.conf --intercept=0
```

При необходимости: `NFQWS2_BIN=/opt/sbin/nfqws2`. Порядок аргументов в проверке: BASE, CUSTOM, UDP, QUIC + EXTRA, HTTP(S) + EXTRA.

## Таблица соответствий winws1 → nfqws2

| winws1 | nfqws2 |
|---|---|
| `--dpi-desync=fake,multisplit` | два инстанса `--lua-desync=fake:…` + `--lua-desync=multisplit:…` |
| `--dpi-desync-fake-tls=X.bin` | `--blob=name:@файл` + `fake:blob=name` |
| `--dpi-desync-fake-tls=!` | `fake:blob=fake_default_tls` (встроенный) / legacy blobs |
| `--dpi-desync-fake-tls-mod=rnd,dupsid,sni=X` | `tls_mod=rnd,dupsid,sni=X` |
| `--dpi-desync-fooling=ts` | `tcp_ts=-600000:tcp_ts_up` |
| `--dpi-desync-fooling=md5sig` | `tcp_md5` |
| `--dpi-desync-fooling=badseq` | `tcp_seq=…` (+ ack по схеме порта) |
| `--dpi-desync-split-pos=…` | `pos=…` |
| `--dpi-desync-split-seqovl=N` | `seqovl=N` (или `seqovl=#blobname`) |
| `--dpi-desync-split-seqovl-pattern=X.bin` | `seqovl_pattern=blobname` |
| `--dpi-desync-fakedsplit-pattern=X` | `pattern=X` |
| `--dpi-desync-hostfakesplit-mod=host=X` | `host=X` |
| `--dpi-desync-hostfakesplit-mod=altorder=1` | через `flowseal-compat.lua` |
| `--dpi-desync-repeats=N` | `repeats=N` (на `fake`) |
| `--dpi-desync-cutoff=nN` | `--out-range=<nN` |
| `--dpi-desync-any-protocol=1` | явные payload-профили / `known,unknown` |
| `--filter-l7=discord,stun` | то же + payload `discord_ip_discovery`, `stun` |
| `--wf-tcp=` / `--wf-udp=` | `TCP_PORTS` / `UDP_PORTS` |
| `--hostlist=` / `--ipset=` | `MODE_*` / профили в `NFQWS_ARGS_CUSTOM` (здесь `NFQWS_ARGS_IPSET` пустой) |

Типичные размеры блобов для `seqovl`: `tls_clienthello_www_google_com.bin` ≈ 681, `tls_clienthello_www_sferum_ru.bin` ≈ 664, `stun2.bin` = 120 (в EXP seqovl=480 — длиннее блоба, добивается повторами).

## Что важно знать

1. **`ts`-фулинг за роутером.** Правит TSval; timestamps генерирует клиентская ОС. На Windows по умолчанию выключены — на клиенте: `netsh interface tcp set global timestamps=enabled`. Стратегии с `ts`: `alt`, `alt3`, `alt9`–`alt12`, `exp`, `fake_tls_auto_alt3`, `simple_fake`, `simple_fake_alt2`.

2. **Порядок профилей.** Служба nfqws2-keenetic собирает командную строку с приоритетом CUSTOM. Поэтому Google, Discord-media, DNS и IP-профили вынесены в `NFQWS_ARGS_CUSTOM`. Из‑за `MODE_ALL` область общего профиля шире, чем у исходных BAT с hostlist; IPv6 в комплекте выключен.

3. **Game Filter** выключен. Фрагменты — `game-profiles/*.args`. Диапазон 1024–65535 при включении нужно ставить **после** основных профилей и расширить `TCP_PORTS`/`UDP_PORTS`, иначе CUSTOM «съест» чужой трафик.

4. **`altorder`.** Нативный параметр winws1 частично закрывается `flowseal-compat.lua` из `strategies/lua/`. Без него поведение ближе к `altorder=0`.

5. **`syndata` + hostlist** (`alt5`, `alt7`): payload в SYN, имя хоста ещё неизвестно. С `--hostlist` нужна поддержка hostname-cache; в оригинале эти профили без hostlist.

6. **`multidisorder` / `multidisorder_legacy`** слабо помогает против Windows-серверов (`fake_tls_auto`, `alt5`): ОС не перезаписывает буфер перекрывающимся сегментом.

7. **Расхождения с Windows.** Сегментация, MSS, IP ID, TLS без SNI и случайные TLS-поля между winws1 и NFQWS2 могут отличаться. Сохранение методов и чисел ≠ побайтово та же область применения, что в бандле на ПК.

## Проверки комплекта

- 22 стандартных `.conf` проходили `sh -n` и разбор аргументов по структуре службы.
- Ссылки на lists/blobs в конфигах согласованы с файлами репозитория; исходные blobs побайтово из бандла.
- Четыре Lua-файла собирались под LuaJIT 2.1; нативный `--dry-run` на конкретном Netcraze/сети автором комплекта не гарантировался.
- Результаты: `strategies/verification/results.json`, карта профилей: `profile-map.json`.

Источники: Flowseal 1.10.4; [bol-van/zapret2 v1.0.7](https://github.com/bol-van/zapret2/releases/tag/v1.0.7); структура переменных службы — [nfqws-keenetic common init](https://github.com/nfqws/nfqws-keenetic/blob/master/etc/init.d/common).
