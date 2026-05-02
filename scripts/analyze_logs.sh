#!/bin/bash
# scripts/analyze_logs.sh
# Скрипт анализа логов Nginx для блокировки IP со статусом 444

# ============================================
# Конфигурация
# ============================================
LOG_DIR="/var/log/nginx"
RSC_OUTPUT="/var/log/nginx/ban_ips.rsc"
TEMP_FILE="/tmp/suspicious_ips.txt"
CF_LIST_FILE="/tmp/cloudflare_ips.txt"
CF_LAST_UPDATE="/tmp/cloudflare_last_update"
LAST_RUN_FILE="/tmp/nginx_ban_last_run"
ADDRESS_LIST="BAN_black_list"

# ============================================
# Функции
# ============================================
echo_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
echo_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
echo_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Обновление списков Cloudflare (раз в неделю)
update_cloudflare_ips() {
    local current_time=$(date +%s)
    local last_update=0
    
    if [ -f "$CF_LAST_UPDATE" ]; then
        last_update=$(cat "$CF_LAST_UPDATE")
        local days_since=$(( (current_time - last_update) / 86400 ))
        [ $days_since -lt 7 ] && [ -s "$CF_LIST_FILE" ] && return
    fi
    
    echo_info "Обновление Cloudflare IP..."
    curl -s --connect-timeout 10 "https://www.cloudflare.com/ips-v4" > "$CF_LIST_FILE.tmp" 2>/dev/null
    if [ -s "$CF_LIST_FILE.tmp" ]; then
        mv "$CF_LIST_FILE.tmp" "$CF_LIST_FILE"
        echo "$current_time" > "$CF_LAST_UPDATE"
        echo_info "Cloudflare IP обновлены: $(wc -l < $CF_LIST_FILE) подсетей"
    else
        rm -f "$CF_LIST_FILE.tmp"
    fi
}

# Инкрементальный анализ логов
analyze_logs() {
    local last_run=0
    [ -f "$LAST_RUN_FILE" ] && last_run=$(cat "$LAST_RUN_FILE")
    
    > "$TEMP_FILE"
    
    if [ "$last_run" -eq 0 ]; then
        echo_info "Первый запуск - анализ всех логов"
        local log_files=$(find "$LOG_DIR" -name "access.log*" -type f 2>/dev/null)
    else
        echo_info "Инкрементальный анализ после: $(date -d "@$last_run" '+%Y-%m-%d %H:%M:%S')"
        local log_files=$(find "$LOG_DIR" -name "access.log*" -type f -newer "$LAST_RUN_FILE" 2>/dev/null)
    fi
    
    if [ -z "$log_files" ]; then
        echo_warn "Нет новых логов"
        echo "$(date +%s)" > "$LAST_RUN_FILE"
        return 1
    fi
    
    # Поиск IP со статусом 444
    for log in $log_files; do
        grep -h "444" "$log" 2>/dev/null | awk '{print $1}' >> "$TEMP_FILE"
    done
    
    echo "$(date +%s)" > "$LAST_RUN_FILE"
    
    # Фильтрация
    sort -u "$TEMP_FILE" > "${TEMP_FILE}_uniq"
    
    # Исключаем локальные и Cloudflare IP
    if [ -f "$CF_LIST_FILE" ] && [ -s "$CF_LIST_FILE" ]; then
        grep -vE '^(127\.|192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)' "${TEMP_FILE}_uniq" | \
        grep -vFf "$CF_LIST_FILE" > "${TEMP_FILE}_clean"
    else
        grep -vE '^(127\.|192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)' "${TEMP_FILE}_uniq" > "${TEMP_FILE}_clean"
    fi
    
    local count=$(wc -l < "${TEMP_FILE}_clean")
    echo_info "Найдено новых IP со статусом 444: $count"
    return 0
}

# Генерация RSC файла для MikroTik
generate_rsc() {
    local count=$(wc -l < "${TEMP_FILE}_clean" 2>/dev/null || echo "0")
    
    if [ "$count" -eq 0 ]; then
        echo_warn "Нет новых IP для добавления"
        cat > "$RSC_OUTPUT" << EOF
# No new IPs with status 444 - $(date)
EOF
        return
    fi
    
    echo_info "Генерация RSC файла ($count IP)..."
    
    cat > "$RSC_OUTPUT" << EOF
# Auto-generated banned IP list for MikroTik
# Target: $ADDRESS_LIST
# Generated: $(date)
# Total IPs: $count

EOF

    local added=0
    local current_date=$(date +%Y-%m-%d)
    
    while read -r ip; do
        [ -z "$ip" ] && continue
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo ":do { /ip firewall address-list add list=\"$ADDRESS_LIST\" address=$ip timeout=7d comment=\"444: $current_date\" } on-error={ }" >> "$RSC_OUTPUT"
            added=$((added + 1))
        fi
    done < "${TEMP_FILE}_clean"
    
    echo_info "Готово! Добавлено $added IP, файл: $RSC_OUTPUT"
}

# Очистка
cleanup() {
    rm -f "$TEMP_FILE" "${TEMP_FILE}_uniq" "${TEMP_FILE}_clean" 2>/dev/null
}

# Основная функция
main() {
    echo_info "=== Запуск анализа логов Nginx (статус 444) ==="
    update_cloudflare_ips
    analyze_logs
    generate_rsc
    cleanup
    echo_info "=== Готово ==="
}

main "$@"
