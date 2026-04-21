#!/bin/sh

OUTPUT_FILE="/etc/nginx/cloudflare_real_ips.conf"
TMP_FILE="${OUTPUT_FILE}.tmp"

{
    echo "# Cloudflare IP ranges - generated on $(date)"
    echo "# Source: https://www.cloudflare.com/ips-v4 and ips-v6"
    echo ""
    
    curl -s https://www.cloudflare.com/ips-v4 | while read ip; do
        [ -n "$ip" ] && echo "set_real_ip_from ${ip};"
    done
    
    echo ""
    
    curl -s https://www.cloudflare.com/ips-v6 | while read ip; do
        [ -n "$ip" ] && echo "set_real_ip_from ${ip};"
    done
    
    echo ""
    echo "real_ip_header CF-Connecting-IP;"
} > ${TMP_FILE}

if [ -f ${OUTPUT_FILE} ] && cmp -s ${TMP_FILE} ${OUTPUT_FILE}; then
    rm -f ${TMP_FILE}
    exit 0
fi

mv ${TMP_FILE} ${OUTPUT_FILE}
nginx -t >/dev/null 2>&1 && nginx -s reload
