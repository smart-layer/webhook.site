# ─── Assets ───────────────────────────────────────────────────────────────────
FROM node:18-alpine AS npm
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY resources ./resources
COPY gulpfile.js ./
RUN npm run gulp

# ─── Dependencies ─────────────────────────────────────────────────────────────
FROM composer:2 AS composer
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-interaction --no-autoloader --no-dev --prefer-dist --no-scripts --ignore-platform-reqs

# ─── Production ───────────────────────────────────────────────────────────────
FROM bkuhl/fpm-nginx:7.3 AS production
WORKDIR /var/www/html

COPY nginx.conf /etc/nginx/conf.d/

COPY --from=composer /usr/bin/composer /usr/bin/composer
COPY --from=composer --chown=www-data:www-data /app/vendor ./vendor

COPY --chown=www-data:www-data app ./app
COPY --chown=www-data:www-data bootstrap ./bootstrap
COPY --chown=www-data:www-data config ./config
COPY --chown=www-data:www-data database ./database
COPY --chown=www-data:www-data public ./public
COPY --chown=www-data:www-data resources ./resources
COPY --chown=www-data:www-data storage ./storage
COPY --chown=www-data:www-data artisan composer.json composer.lock ./

COPY --from=npm --chown=www-data:www-data /app/public/css ./public/css
COPY --from=npm --chown=www-data:www-data /app/public/js ./public/js

USER www-data
RUN composer dump-autoload --optimize --no-dev \
    && touch database/database.sqlite \
    && php artisan optimize \
    && php artisan migrate
USER root
