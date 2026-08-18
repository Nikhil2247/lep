# Production image for Coolify (Dockerfile build pack). Single container:
# nginx + php-fpm under supervisord, since this repo has no separate
# frontend build step (no package.json/@vite - pure Blade views).
FROM php:8.2-fpm

RUN apt-get update && apt-get install -y --no-install-recommends \
        libzip-dev unzip git \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
        libonig-dev \
        nginx supervisor \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install pdo_mysql mbstring bcmath zip gd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# php.ini overrides - the legacy server's defaults (upload_max_filesize=2M,
# post_max_size=8M) are too small for LEP_MAX_EVIDENCE_FILES=5 x 5MB each;
# see .env.example for those limits.
COPY docker/php.ini /usr/local/etc/php/conf.d/99-lep.ini

WORKDIR /var/www/html
COPY . .

RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && mkdir -p bootstrap/cache storage/framework/cache storage/framework/sessions \
       storage/framework/views storage/logs storage/app/public \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

COPY docker/nginx.conf /etc/nginx/sites-enabled/default
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
