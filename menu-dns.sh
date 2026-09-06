#!/bin/sh

# Цветовые ANSI-коды
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_MAGENTA="\033[35m"
C_RED="\033[31m"
C_DIM="\033[2m"

# Функция отображения текущего состояния
show_dns_servers() {
    ndmc -c show dns-proxy 2>/dev/null | awk -v c_reset="$C_RESET" \
                                             -v c_bold="$C_BOLD" \
                                             -v c_cyan="$C_CYAN" \
                                             -v c_green="$C_GREEN" \
                                             -v c_yellow="$C_YELLOW" \
                                             -v c_magenta="$C_MAGENTA" \
                                             -v c_dim="$C_DIM" '
        BEGIN { dot_gen_cnt = 0; doh_gen_cnt = 0; dom_cnt = 0 }

        /server-tls:/ {
            if (in_dot && addr != "") {
                target = (sni != "") ? addr " " sni : addr
                if (domain == "") {
                    dot_gen[dot_gen_cnt++] = "  " c_cyan "🔒" c_reset " " target
                } else {
                    dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " target " " c_magenta "[DoT]" c_reset
                }
                if (target != "") dot_tot[target] = 1
            }
            in_dot=1; in_doh=0; addr=""; sni=""; domain=""; next
        }
        in_dot && /address:/ { addr=$2 }
        in_dot && /port:/ { if ($2 != "853") addr=addr ":" $2 }
        in_dot && /sni:/ { sni=$2 }
        in_dot && /domain:/ { domain=$2 }

        /server-https:/ {
            if (in_doh && uri != "") {
                gsub(/[ \t\r\n]/, "", uri)
                if (domain == "") {
                    doh_gen[doh_gen_cnt++] = "  " c_green "⚡" c_reset " " uri
                } else {
                    dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " uri " " c_cyan "[DoH]" c_reset
                }
                if (uri != "") doh_tot[uri] = 1
            }
            in_doh=1; in_dot=0; uri=""; domain=""; next
        }
        in_doh && /uri:/ { reading_uri=1; uri=$2; next }
        in_doh && reading_uri && (/format:/ || /spki:/ || /interface:/ || /domain:/) { reading_uri=0 }
        in_doh && reading_uri { uri=uri $1 }
        in_doh && /domain:/ { domain=$2 }

        END {
            if (in_dot && addr != "") {
                target = (sni != "") ? addr " " sni : addr
                if (domain == "") {
                    dot_gen[dot_gen_cnt++] = "  " c_cyan "🔒" c_reset " " target
                } else {
                    dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " target " " c_magenta "[DoT]" c_reset
                }
                if (target != "") dot_tot[target] = 1
            }
            if (in_doh && uri != "") {
                gsub(/[ \t\r\n]/, "", uri)
                if (domain == "") {
                    doh_gen[doh_gen_cnt++] = "  " c_green "⚡" c_reset " " uri
                } else {
                    dom_list[dom_cnt++] = "  " c_yellow "🌐" c_reset " " sprintf("%-18s", domain) " " c_dim "➔" c_reset " " uri " " c_cyan "[DoH]" c_reset
                }
                if (uri != "") doh_tot[uri] = 1
            }

            for (k in dot_tot) dot_c++
            for (k in doh_tot) doh_c++

            print c_cyan "┌────────────────────────────────────────────────────────┐" c_reset
            print c_cyan "│" c_bold "          УПРАВЛЕНИЕ DNS СЕРВЕРАМИ KEENETIC            " c_cyan "│" c_reset
            print c_cyan "└────────────────────────────────────────────────────────┘" c_reset

            print "\n" c_bold c_magenta "  [ DoT Серверы ]" c_reset " " c_dim "[" dot_c+0 "/8]" c_reset
            delete printed
            if (dot_gen_cnt == 0) print "  " c_dim "— нет общих серверов —" c_reset
            for (i=0; i<dot_gen_cnt; i++) {
                if (!printed[dot_gen[i]]) { print dot_gen[i]; printed[dot_gen[i]] = 1 }
            }

            print "\n" c_bold c_cyan "  [ DoH Серверы ]" c_reset " " c_dim "[" doh_c+0 "/8]" c_reset
            delete printed
            if (doh_gen_cnt == 0) print "  " c_dim "— нет общих серверов —" c_reset
            for (i=0; i<doh_gen_cnt; i++) {
                if (!printed[doh_gen[i]]) { print doh_gen[i]; printed[doh_gen[i]] = 1 }
            }

            print "\n" c_bold c_yellow "  [ Персональные привязки к доменам ]" c_reset
            delete printed
            if (dom_cnt == 0) print "  " c_dim "— привязки отсутствуют —" c_reset
            for (i=0; i<dom_cnt; i++) {
                if (!printed[dom_list[i]]) { print dom_list[i]; printed[dom_list[i]] = 1 }
            }
            print "\n" c_dim "────────────────────────────────────────────────────────" c_reset
        }
    '
}

# Сохранение конфигурации
save_config() {
    echo -n "Сохранение конфигурации..."
    ndmc -c system configuration save > /dev/null 2>&1
    echo " [ГОТОВО]"
    sleep 1
}

# Применение DoT
apply_dot() {
    ip="$1"
    sni="$2"
    domain="$3"
    port="$4"

    cmd="dns-proxy tls upstream $ip"
    [ -n "$port" ] && cmd="$cmd $port"
    [ -n "$sni" ] && cmd="$cmd sni $sni"
    [ -n "$domain" ] && cmd="$cmd domain $domain"

    echo -e "${C_CYAN}Применение DoT ($ip):${C_RESET} ndmc -c \"$cmd\""
    ndmc -c "$cmd" > /dev/null 2>&1
}

# Применение DoH
apply_doh() {
    uri="$1"
    domain="$2"

    cmd="dns-proxy https upstream $uri"
    [ -n "$domain" ] && cmd="$cmd domain $domain"

    echo -e "${C_CYAN}Применение DoH ($uri):${C_RESET} ndmc -c \"$cmd\""
    ndmc -c "$cmd" > /dev/null 2>&1
}

# Меню DoT Пресетов
add_dot_menu() {
    echo ""
    echo -e "${C_BOLD}Выбор DoT серверов (можно несколько через запятую, напр. 1,3,20):${C_RESET}"
    echo -e " ${C_YELLOW}--- Яндекс & Cloudflare ---${C_RESET}"
    echo " 1) Yandex Primary (77.88.8.8)"
    echo " 2) Yandex Secondary (77.88.8.1)"
    echo " 3) Cloudflare Standard Primary (1.1.1.1)"
    echo " 4) Cloudflare Standard Secondary (1.0.0.1)"
    echo " 5) Cloudflare Malware Primary (1.1.1.2)"
    echo " 6) Cloudflare Malware Secondary (1.0.0.2)"
    echo " 7) Cloudflare Malware+Adult Primary (1.1.1.3)"
    echo " 8) Cloudflare Malware+Adult Secondary (1.0.0.3)"
    echo -e " ${C_YELLOW}--- Безопасность & Приватность ---${C_RESET}"
    echo " 9) Quad9 Primary (9.9.9.9)"
    echo "10) Quad9 Secondary (149.112.112.112)"
    echo "11) CleanBrowsing Sec Filter 1 (185.228.168.9)"
    echo "12) CleanBrowsing Sec Filter 2 (185.228.169.9)"
    echo "13) OpenDNS Primary (208.67.222.222)"
    echo "14) OpenDNS Secondary (208.67.220.220)"
    echo "15) DNS.SB Primary (185.222.222.222)"
    echo "16) DNS.SB Secondary (45.11.45.11)"
    echo "17) dns0.eu (dns0.eu)"
    echo -e " ${C_YELLOW}--- OpenNameServer ---${C_RESET}"
    echo "18) OpenNameServer ns1 (217.160.70.42)"
    echo "19) OpenNameServer ns2 (213.202.211.221)"
    echo "20) OpenNameServer ns3 (81.169.136.222)"
    echo "21) OpenNameServer ns4 (185.181.61.24)"
    echo -e " ${C_YELLOW}--- Япония ---${C_RESET}"
    echo "22) IIJ Japan (public.dns.iij.jp)"
    echo "23) Tiar Japan (jp.tiar.app)"
    echo -e " ${C_GREEN}--- Proxy-DNS (Обход блокировок) ---${C_RESET}"
    echo "24) Xbox-DNS (xbox-dns.ru)"
    echo "25) Comss DNS (dns.comss.one)"
    echo "26) Malw Link (dns.malw.link)"
    echo "27) Cloudflare Gateway (5u35p8m9i7.cloudflare-gateway.com)"
    echo -e " ${C_YELLOW}--- Свой вариант ---${C_RESET}"
    echo "28) Ввести вручную (IP / Port / SNI)"
    echo " 0) Отмена"
    echo -e "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
    read -p "Выберите варианты: " raw_choices

    [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

    read -p "Привязать выбранные к домену? (пусто для всех): " domain
    clean_choices=$(echo "$raw_choices" | tr ',' ' ')

    added_any=0
    for choice in $clean_choices; do
        case $choice in
            1) apply_dot "77.88.8.8" "common.dot.dns.yandex.net" "$domain"; added_any=1 ;;
            2) apply_dot "77.88.8.1" "common.dot.dns.yandex.net" "$domain"; added_any=1 ;;
            3) apply_dot "1.1.1.1" "cloudflare-dns.com" "$domain"; added_any=1 ;;
            4) apply_dot "1.0.0.1" "cloudflare-dns.com" "$domain"; added_any=1 ;;
            5) apply_dot "1.1.1.2" "cloudflare-dns.com" "$domain"; added_any=1 ;;
            6) apply_dot "1.0.0.2" "cloudflare-dns.com" "$domain"; added_any=1 ;;
            7) apply_dot "1.1.1.3" "cloudflare-dns.com" "$domain"; added_any=1 ;;
            8) apply_dot "1.0.0.3" "cloudflare-dns.com" "$domain"; added_any=1 ;;
            9) apply_dot "9.9.9.9" "dns.quad9.net" "$domain"; added_any=1 ;;
            10) apply_dot "149.112.112.112" "dns.quad9.net" "$domain"; added_any=1 ;;
            11) apply_dot "185.228.168.9" "security-filter-dns.cleanbrowsing.org" "$domain" "853"; added_any=1 ;;
            12) apply_dot "185.228.169.9" "security-filter-dns2.cleanbrowsing.org" "$domain" "853"; added_any=1 ;;
            13) apply_dot "208.67.222.222" "dns.opendns.com" "$domain"; added_any=1 ;;
            14) apply_dot "208.67.220.220" "dns.opendns.com" "$domain"; added_any=1 ;;
            15) apply_dot "185.222.222.222" "dot.sb" "$domain"; added_any=1 ;;
            16) apply_dot "45.11.45.11" "dot.sb" "$domain"; added_any=1 ;;
            17) apply_dot "dns0.eu" "dns0.eu" "$domain"; added_any=1 ;;
            18) apply_dot "217.160.70.42" "ns1.opennameserver.org" "$domain"; added_any=1 ;;
            19) apply_dot "213.202.211.221" "ns2.opennameserver.org" "$domain"; added_any=1 ;;
            20) apply_dot "81.169.136.222" "ns3.opennameserver.org" "$domain"; added_any=1 ;;
            21) apply_dot "185.181.61.24" "ns4.opennameserver.org" "$domain"; added_any=1 ;;
            22) apply_dot "public.dns.iij.jp" "public.dns.iij.jp" "$domain"; added_any=1 ;;
            23) apply_dot "jp.tiar.app" "jp.tiar.app" "$domain"; added_any=1 ;;
            24) apply_dot "xbox-dns.ru" "xbox-dns.ru" "$domain"; added_any=1 ;;
            25) apply_dot "dns.comss.one" "dns.comss.one" "$domain"; added_any=1 ;;
            26) apply_dot "dns.malw.link" "dns.malw.link" "$domain"; added_any=1 ;;
            27) apply_dot "5u35p8m9i7.cloudflare-gateway.com" "5u35p8m9i7.cloudflare-gateway.com" "$domain"; added_any=1 ;;
            28) 
                read -p "Введите IP/Хост: " manual_ip
                read -p "Введите Порт (по умолчанию 853, отмена - Enter): " manual_port
                read -p "Введите SNI (отмена - Enter): " manual_sni
                if [ -n "$manual_ip" ]; then
                    apply_dot "$manual_ip" "$manual_sni" "$domain" "$manual_port"
                    added_any=1
                fi
                ;;
        esac
    done

    [ "$added_any" -eq 1 ] && save_config
}

# Меню DoH Пресетов
add_doh_menu() {
    echo ""
    echo -e "${C_BOLD}Выбор DoH серверов (можно несколько через запятую, напр. 1,3,13):${C_RESET}"
    echo -e " ${C_YELLOW}--- Яндекс & Cloudflare ---${C_RESET}"
    echo " 1) Yandex Primary (https://77.88.8.8/dns-query)"
    echo " 2) Yandex Secondary (https://77.88.8.1/dns-query)"
    echo " 3) Cloudflare (https://cloudflare-dns.com/dns-query)"
    echo -e " ${C_YELLOW}--- Безопасность & Приватность ---${C_RESET}"
    echo " 4) Quad9 (https://dns.quad9.net/dns-query)"
    echo " 5) CleanBrowsing (https://doh.cleanbrowsing.org/doh/security-filter/)"
    echo " 6) OpenDNS (https://doh.opendns.com/dns-query)"
    echo " 7) DNS.SB (https://doh.dns.sb/dns-query)"
    echo " 8) dns0.eu (https://dns0.eu/)"
    echo -e " ${C_YELLOW}--- OpenNameServer ---${C_RESET}"
    echo " 9) OpenNameServer ns1 (https://ns1.opennameserver.org/dns-query)"
    echo "10) OpenNameServer ns2 (https://ns2.opennameserver.org/dns-query)"
    echo "11) OpenNameServer ns3 (https://ns3.opennameserver.org/dns-query)"
    echo "12) OpenNameServer ns4 (https://ns4.opennameserver.org/dns-query)"
    echo -e " ${C_YELLOW}--- Япония ---${C_RESET}"
    echo "13) IIJ Japan (https://public.dns.iij.jp/dns-query)"
    echo "14) Tiar Japan app (https://jp.tiar.app/dns-query)"
    echo "15) Tiar Japan org (https://jp.tiarap.org/dns-query)"
    echo -e " ${C_GREEN}--- Proxy-DNS (Обход блокировок) ---${C_RESET}"
    echo "16) Xbox-DNS (https://xbox-dns.ru/dns-query)"
    echo "17) Comss DNS Keenetic/MikroTik (https://dns.comss.one/dns-query)"
    echo "18) Malw Link (https://dns.malw.link/dns-query)"
    echo "19) Cloudflare Gateway (https://5u35p8m9i7.cloudflare-gateway.com/dns-query)"
    echo -e " ${C_YELLOW}--- Свой вариант ---${C_RESET}"
    echo "20) Ввести вручную (произвольный URI)"
    echo " 0) Отмена"
    echo -e "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
    read -p "Выберите варианты: " raw_choices

    [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

    read -p "Привязать выбранные к домену? (пусто для всех): " domain
    clean_choices=$(echo "$raw_choices" | tr ',' ' ')

    added_any=0
    for choice in $clean_choices; do
        case $choice in
            1) apply_doh "https://77.88.8.8/dns-query" "$domain"; added_any=1 ;;
            2) apply_doh "https://77.88.8.1/dns-query" "$domain"; added_any=1 ;;
            3) apply_doh "https://cloudflare-dns.com/dns-query" "$domain"; added_any=1 ;;
            4) apply_doh "https://dns.quad9.net/dns-query" "$domain"; added_any=1 ;;
            5) apply_doh "https://doh.cleanbrowsing.org/doh/security-filter/" "$domain"; added_any=1 ;;
            6) apply_doh "https://doh.opendns.com/dns-query" "$domain"; added_any=1 ;;
            7) apply_doh "https://doh.dns.sb/dns-query" "$domain"; added_any=1 ;;
            8) apply_doh "https://dns0.eu/" "$domain"; added_any=1 ;;
            9) apply_doh "https://ns1.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
            10) apply_doh "https://ns2.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
            11) apply_doh "https://ns3.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
            12) apply_doh "https://ns4.opennameserver.org/dns-query" "$domain"; added_any=1 ;;
            13) apply_doh "https://public.dns.iij.jp/dns-query" "$domain"; added_any=1 ;;
            14) apply_doh "https://jp.tiar.app/dns-query" "$domain"; added_any=1 ;;
            15) apply_doh "https://jp.tiarap.org/dns-query" "$domain"; added_any=1 ;;
            16) apply_doh "https://xbox-dns.ru/dns-query" "$domain"; added_any=1 ;;
            17) apply_doh "https://dns.comss.one/dns-query" "$domain"; added_any=1 ;;
            18) apply_doh "https://dns.malw.link/dns-query" "$domain"; added_any=1 ;;
            19) apply_doh "https://5u35p8m9i7.cloudflare-gateway.com/dns-query" "$domain"; added_any=1 ;;
            20) 
                read -p "Введите URI DoH сервера: " manual_uri
                if [ -n "$manual_uri" ]; then
                    apply_doh "$manual_uri" "$domain"
                    added_any=1
                fi
                ;;
        esac
    done

    [ "$added_any" -eq 1 ] && save_config
}

# Меню персональной привязки доменов
add_domain_menu() {
    echo ""
    echo -e "${C_BOLD}Быстрая привязка DNS к целевым доменам (можно несколько через запятую, напр. 1,3,4):${C_RESET}"
    echo " 1) CleanBrowsing DoT (185.228.168.9 + SNI) ➔ instagram.com"
    echo " 2) CleanBrowsing DoH (doh.cleanbrowsing.org) ➔ instagram.com"
    echo " 3) sw.ext.io DoT ➔ rutor.is & rutor.info"
    echo " 4) Malw Link DoH (dns.malw.link) ➔ ntc.party"
    echo " 5) Ввести свой домен и выбрать сервер"
    echo " 0) Отмена"
    echo -e "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
    read -p "Выберите варианты: " raw_choices

    [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && return

    clean_choices=$(echo "$raw_choices" | tr ',' ' ')
    added_any=0

    for choice in $clean_choices; do
        case $choice in
            1)
                apply_dot "185.228.168.9" "security-filter-dns.cleanbrowsing.org" "instagram.com" "853"
                added_any=1
                ;;
            2)
                apply_doh "https://doh.cleanbrowsing.org/doh/security-filter/" "instagram.com"
                added_any=1
                ;;
            3)
                apply_dot "sw.ext.io" "" "rutor.is"
                apply_dot "sw.ext.io" "" "rutor.info"
                added_any=1
                ;;
            4)
                apply_doh "https://dns.malw.link/dns-query" "ntc.party"
                added_any=1
                ;;
            5)
                read -p "Введите домен (например: example.com): " dom
                if [ -n "$dom" ]; then
                    echo "Тип протокола: 1) DoT  2) DoH"
                    read -p "Выберите [1-2]: " ptype
                    if [ "$ptype" = "1" ]; then
                        read -p "Введите IP/Хост DoT: " dot_ip
                        read -p "Введите SNI (необязательно): " dot_sni
                        read -p "Введите порт (по умолчанию 853, Enter - пропустить): " dot_port
                        if [ -n "$dot_ip" ]; then
                            apply_dot "$dot_ip" "$dot_sni" "$dom" "$dot_port"
                            added_any=1
                        fi
                    elif [ "$ptype" = "2" ]; then
                        read -p "Введите URI DoH: " doh_uri
                        if [ -n "$doh_uri" ]; then
                            apply_doh "$doh_uri" "$dom"
                            added_any=1
                        fi
                    fi
                fi
                ;;
        esac
    done

    [ "$added_any" -eq 1 ] && save_config
}

# Меню удаления серверов
remove_dns_menu() {
    tmp_list="/tmp/dns_rem_list.txt"
    rm -f "$tmp_list"

    # Сбор данных с фильтрацией дублирующихся доменов
    ndmc -c show dns-proxy 2>/dev/null | awk '
        /server-tls:/ {
            if (in_dot && addr != "") {
                p = (port != "") ? port : "853"
                key = addr "|" p
                if (!(key in dot_order)) { dot_addrs[dot_cnt++] = key; dot_order[key] = 1 }
                if (domain != "") {
                    dom_key = key "|" domain
                    if (!(dom_key in dot_dom_seen)) {
                        dot_dom_seen[dom_key] = 1
                        dot_doms[key] = (dot_doms[key] != "") ? dot_doms[key] ", " domain : domain
                    }
                }
            }
            in_dot=1; in_doh=0; addr=""; port=""; domain=""; next
        }
        in_dot && /address:/ { addr=$2 }
        in_dot && /port:/ { port=$2 }
        in_dot && /domain:/ { domain=$2 }

        /server-https:/ {
            if (in_doh && uri != "") {
                gsub(/[ \t\r\n]/, "", uri)
                if (!(uri in doh_order)) { doh_addrs[doh_cnt++] = uri; doh_order[uri] = 1 }
                if (domain != "") {
                    dom_key = uri "|" domain
                    if (!(dom_key in doh_dom_seen)) {
                        doh_dom_seen[dom_key] = 1
                        doh_doms[uri] = (doh_doms[uri] != "") ? doh_doms[uri] ", " domain : domain
                    }
                }
            }
            in_doh=1; in_dot=0; uri=""; domain=""; next
        }
        in_doh && /uri:/ { reading_uri=1; uri=$2; next }
        in_doh && reading_uri && (/format:/ || /spki:/ || /interface:/ || /domain:/) { reading_uri=0 }
        in_doh && reading_uri { uri=uri $1 }
        in_doh && /domain:/ { domain=$2 }

        END {
            if (in_dot && addr != "") {
                p = (port != "") ? port : "853"
                key = addr "|" p
                if (!(key in dot_order)) { dot_addrs[dot_cnt++] = key; dot_order[key] = 1 }
                if (domain != "") {
                    dom_key = key "|" domain
                    if (!(dom_key in dot_dom_seen)) {
                        dot_dom_seen[dom_key] = 1
                        dot_doms[key] = (dot_doms[key] != "") ? dot_doms[key] ", " domain : domain
                    }
                }
            }
            if (in_doh && uri != "") {
                gsub(/[ \t\r\n]/, "", uri)
                if (!(uri in doh_order)) { doh_addrs[doh_cnt++] = uri; doh_order[uri] = 1 }
                if (domain != "") {
                    dom_key = uri "|" domain
                    if (!(dom_key in doh_dom_seen)) {
                        doh_dom_seen[dom_key] = 1
                        doh_doms[uri] = (doh_doms[uri] != "") ? doh_doms[uri] ", " domain : domain
                    }
                }
            }

            idx = 1
            for (i = 0; i < dot_cnt; i++) {
                split(dot_addrs[i], parts, "|")
                a = parts[1]
                pt = parts[2]
                print idx " | dot | " a " | " pt " | " dot_doms[dot_addrs[i]]
                idx++
            }
            for (i = 0; i < doh_cnt; i++) {
                u = doh_addrs[i]
                print idx " | doh | " u " | | " doh_doms[u]
                idx++
            }
        }
    ' > "$tmp_list"

    if [ ! -s "$tmp_list" ]; then
        echo -e "\n${C_YELLOW}Нет настроенных DNS серверов для удаления.${C_RESET}"
        sleep 1.5
        return
    fi

    echo ""
    echo -e "${C_BOLD}${C_RED}Список настроенных серверов для удаления:${C_RESET}"
    while IFS='|' read -r num type target port doms; do
        num=$(echo "$num" | xargs)
        type=$(echo "$type" | xargs)
        target=$(echo "$target" | xargs)
        port=$(echo "$port" | xargs)
        doms=$(echo "$doms" | xargs)

        label_type=""
        [ "$type" = "dot" ] && label_type="${C_MAGENTA}[DoT]${C_RESET}"
        [ "$type" = "doh" ] && label_type="${C_CYAN}[DoH]${C_RESET}"

        dom_info=""
        [ -n "$doms" ] && dom_info=" ${C_YELLOW}(domains: $doms)${C_RESET}"

        echo -e " ${C_BOLD}$num)${C_RESET} $label_type $target$dom_info"
    done < "$tmp_list"

    echo -e " ${C_BOLD}0)${C_RESET} Отмена"
    echo -e "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
    read -p "Выберите номера для удаления (можно несколько через запятую): " raw_choices

    [ -z "$raw_choices" ] || [ "$raw_choices" = "0" ] && { rm -f "$tmp_list"; return; }

    clean_choices=$(echo "$raw_choices" | tr ',' ' ')
    removed_any=0

    for choice in $clean_choices; do
        line=$(grep -E "^$choice \|" "$tmp_list")
        if [ -n "$line" ]; then
            type=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
            target=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
            port=$(echo "$line" | awk -F'|' '{print $4}' | xargs)

            cmd=""
            if [ "$type" = "dot" ]; then
                [ -z "$port" ] && port="853"
                cmd="no dns-proxy tls upstream $target $port"
            elif [ "$type" = "doh" ]; then
                cmd="no dns-proxy https upstream $target"
            fi

            echo -e "${C_RED}Удаление:${C_RESET} ndmc -c \"$cmd\""
            ndmc -c "$cmd" > /dev/null 2>&1
            removed_any=1
        fi
    done

    rm -f "$tmp_list"
    [ "$removed_any" -eq 1 ] && save_config
}

# Главный цикл программы
while true; do
    clear
    show_dns_servers
    echo -e " ${C_BOLD}1)${C_RESET} Добавить DoT сервер(ы)"
    echo -e " ${C_BOLD}2)${C_RESET} Добавить DoH сервер(ы)"
    echo -e " ${C_BOLD}3)${C_RESET} ${C_YELLOW}Привязать домен к DNS (Пресеты)${C_RESET}"
    echo -e " ${C_BOLD}4)${C_RESET} ${C_RED}Удалить сервер(ы)${C_RESET}"
    echo -e " ${C_BOLD}0)${C_RESET} Выход"
    echo -e "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
    read -p "Выберите действие [0-4]: " choice

    case $choice in
        1) add_dot_menu ;;
        2) add_doh_menu ;;
        3) add_domain_menu ;;
        4) remove_dns_menu ;;
        0) clear; exit 0 ;;
        *) echo "Неверный ввод, попробуйте снова."; sleep 1 ;;
    esac
done