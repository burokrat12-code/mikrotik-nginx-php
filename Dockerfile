# Фиксируем версию Debian для стабильности
FROM debian:bookworm-20241223-slim

# Устанавливаем зависимости
RUN apt-get update && apt-get install -y \
    curl \
    gnupg2 \
    ca-certificates \
    lsb-release \
    debian-archive-keyring \
    supervisor \
    php8.2-fpm \
    php8.2-cli \
    php8.2-common \
    php8.2-opcache \
    openssl \
    && apt-get clean

# Устанавливаем Nginx из официального репозитория (фиксируем версию)
RUN curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/debian bookworm nginx" \
    | tee /etc/apt/sources.list.d/nginx.list

# Устанавливаем конкретную версию Nginx
RUN apt-get update && apt-get install -y nginx=1.26.2-1~bookworm && apt-get clean

# Проверяем наличие stream_ssl_preread_module
RUN nginx -V 2>&1 | grep -q with-stream_ssl_preread_module || exit 1

# Создаём структуру папок
RUN mkdir -p /var/www/html /etc/ssl/certs /etc/ssl/private && \
    chown -R www-data:www-data /var/www/html

# Генерируем самоподписанный сертификат по умолчанию (чтобы nginx не падал при старте)
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=Default/CN=localhost"

# Копируем конфиги
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/php-fpm.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY config/default-site.conf /etc/nginx/conf.d/default.conf

EXPOSE 80 443 8443

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
