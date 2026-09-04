> Обновление 1.10.2: добавлен ALT13, синхронизированы blobs и списки из бандла 1.10.2.

# zapret-discord-youtube 1.10.2 → nfqws2

21 стратегия из бандла, портированные под формат `nfqws2.conf`
(пакет [nfqws2-keenetic](https://github.com/nfqws/nfqws2-keenetic), Entware/Keenetic/OpenWrt).

| оригинал | конфиг | техника |
|---|---|---|
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

## Что обновлено относительно предыдущего набора конфигов

Этот набор сохраняет ту же структуру и стиль NFQWS2-конфигов, но синхронизирован со стратегиями Windows-бандла 1.10.1.

- Новые `--dpi-desync-fake-unknown` в игровых TCP-профилях учтены через NFQWS2 payload-селекцию `unknown`. В старом порте Game Filter уже использовал `--payload=known,unknown` + `payload=~empty`, поэтому там, где это уже давало эквивалентное покрытие, fake-инстансы намеренно не продублированы.
- `ALT11`, `SIMPLE FAKE ALT` и `SIMPLE FAKE ALT2` используют `stun2.bin` там, где 1.10.1 заменил `stun.bin`.
- В `SIMPLE FAKE` профиль Google/443 переведён с обычного `fake` на нативный NFQWS2 `hostfakesplit:host=www.google.com`, как в 1.10.1.
- В `SIMPLE FAKE` обычный TLS-профиль больше не шлёт `stun.bin`; игровой unknown использует `stun2`.
- В `EXP` расширение `--dpi-desync-any-protocol=1` для Discord/STUN/unknown уже выражено явными NFQWS2 payload-профилями.
- Новые blobs `quic_initial_5ka_ru.bin`, `quic_initial_rutube_ru.bin`, `tls_clienthello_5ka_ru.bin` присутствуют в 1.10.1-бандле, но текущие 20 стратегий их не используют, поэтому дополнительные `--blob=` здесь не добавлены.

## Как ставить

1. Скопировать `bin\*.bin` из бандла в `/opt/etc/nfqws2/blobs/`.
2. `lists\list-google.txt` → `/opt/etc/nfqws2/lists/google.list`,
   `list-general*.txt` → `user.list`, `list-exclude*.txt` → `exclude.list`,
   `ipset-all.txt` → `ipset.list`, `ipset-exclude*.txt` → `ipset_exclude.list`.
3. Выбранный `.conf` → `/opt/etc/nfqws2/nfqws2.conf`, поправить `ISP_INTERFACE`.
4. `/opt/etc/init.d/S51nfqws2 restart`

## Таблица соответствий winws1 → nfqws2

| winws1 | nfqws2 |
|---|---|
| `--dpi-desync=fake,multisplit` | два инстанса `--lua-desync=fake:…` + `--lua-desync=multisplit:…` |
| `--dpi-desync-fake-tls=X.bin` | `--blob=name:@файл` + `fake:blob=name` |
| `--dpi-desync-fake-tls=!` | `fake:blob=fake_default_tls` (встроенный фейк) |
| `--dpi-desync-fake-tls-mod=rnd,dupsid,sni=X` | `tls_mod=rnd,dupsid,sni=X` |
| `--dpi-desync-fake-tls-mod=none` | просто отсутствие `tls_mod` |
| `--dpi-desync-fooling=ts` | `tcp_ts=-600000:tcp_ts_up` |
| `--dpi-desync-fooling=md5sig` | `tcp_md5` |
| `--dpi-desync-fooling=badseq` | `tcp_seq=-10000:tcp_ack=-66000` |
| `--dpi-desync-badseq-increment=N` | `tcp_seq=N` (ack остаётся −66000) |
| `--dpi-desync-split-pos=…` | `pos=…` |
| `--dpi-desync-split-seqovl=N` | `seqovl=N` (или `seqovl=#blobname`) |
| `--dpi-desync-split-seqovl-pattern=X.bin` | `seqovl_pattern=blobname` |
| `--dpi-desync-fakedsplit-pattern=X` | `pattern=X` |
| `--dpi-desync-hostfakesplit-mod=host=X` | `host=X` |
| `--dpi-desync-repeats=N` | `repeats=N` (только на `fake`) |
| `--ip-id=zero` | `ip_id=zero` на каждом инстансе |
| `--dpi-desync-cutoff=nN` | `--out-range=<nN` |
| `--dpi-desync-any-protocol=1` | `--payload=known,unknown` + `payload=~empty` |
| `--filter-l7=discord,stun` | то же + `--payload=discord_ip_discovery,stun` |
| `--wf-tcp=` / `--wf-udp=` | `TCP_PORTS` / `UDP_PORTS` (правила iptables) |
| `--hostlist=` / `--ipset=` | `MODE_LIST` / `NFQWS_ARGS_IPSET` |

Числа `seqovl` — это ровно размеры блобов: `tls_clienthello_www_google_com.bin` = 681 б,
`tls_clienthello_max_ru.bin` = 664 б, `stun2.bin` = 120 б (в EXP берётся 480 — приставка
длиннее блоба, добивается повторами/нулями).

## Что важно знать

**1. `ts`-фулинг может не работать за роутером.** Он правит TSval в TCP timestamps,
а таймштампы генерирует клиентская ОС. В Windows они выключены по умолчанию.
Когда winws крутился на самом ПК, бандл это решал локально; на роутере нужно включать
на каждом клиенте: `netsh interface tcp set global timestamps=enabled`.
Если стратегия с `ts` не заводится — это первый подозреваемый. Затронуты:
`alt`, `alt3`, `alt9`, `alt10`, `alt11`, `alt12`, `exp`, `fake_tls_auto_alt3`,
`simple_fake`, `simple_fake_alt2`.

**2. Порядок профилей другой.** В `.bat` он такой, как написан. Пакет nfqws2-keenetic
собирает командную строку жёстко: `CUSTOM → UDP → QUIC(ipset) → QUIC(list) →
HTTPS(ipset) → HTTPS(list)`. Поэтому специфичные профили (`discord.media`, google-лист)
вынесены в `NFQWS_ARGS_CUSTOM` — иначе их перехватил бы общий профиль. Побочный эффект:
ipset-профили теперь идут перед хостлистовыми, а не после.

**3. Игровой фильтр** во всех конфигах закомментирован (в бандле он тоже выключен
по умолчанию). Диапазон `1024-65535` разбит на подинтервалы с вырезанными портами
2053/2083/2087/2096/8443 и 19294-19344/50000-50100 — потому что в винде игровой профиль
шёл последним, а в `NFQWS_ARGS_CUSTOM` он окажется первым и иначе съел бы чужой трафик.
Если включаете — не забудьте расширить `TCP_PORTS`/`UDP_PORTS`.

**4. `altorder` не портируется.** `--dpi-desync-hostfakesplit-mod=altorder=1` (`alt3`)
и `--dpi-desync-fakedsplit-mod=altorder=N` в nfqws2 отсутствуют: порядок отправки
сегментов зашит и соответствует `altorder=0`. Есть только `nofake1`/`nofake2` для
отключения отдельных фейков.

**5. `syndata` + хостлисты.** `alt5` и `alt7` используют стратегию нулевой фазы:
пейлоад кладётся в SYN, когда имя хоста ещё неизвестно. С `--hostlist` она сработает
только при `--ipcache-hostname`. В оригинале эти профили вообще без хостлиста.
Подробности — в примечаниях внутри самих файлов.

**6. `multidisorder` бесполезен против Windows-серверов** (`fake_tls_auto`, `alt5`):
Windows не перезаписывает буфер сокета перекрывающимся сегментом.

**7. Расхождения list/ipset.** В `alt7` и `alt9` оригинал использует разные стратегии
для хостлистового и ipset-профиля. Пакет генерирует ipset-профиль автоматически
из того же `NFQWS_ARGS`, поэтому задать разные нельзя — выбран один вариант,
это отмечено в примечаниях к файлам.

## Проверка

Все 20 `.conf` проверены как shell-конфиги (`dash -n`) после обновления. Параметры NFQWS2 сверены с актуальной схемой `NFQWS_ARGS*` и нативным Lua-desync форматом. Перед заменой рабочего конфига рекомендуется сохранить текущий `nfqws2.conf` и первый запуск сделать с `LOG_LEVEL=1`.
