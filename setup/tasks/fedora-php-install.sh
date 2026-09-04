#!/usr/bin/env bash
set -euo pipefail

printf 'Installing PHP...\n'

sudo dnf install -y \
  php-cli \
  php-fpm \
  php-bcmath \
  php-gd \
  php-intl \
  php-mbstring \
  php-mysqlnd \
  php-pdo \
  php-process \
  php-sodium \
  php-pecl-apcu \
  php-pecl-igbinary \
  php-pecl-imagick \
  php-pecl-memcache \
  php-pecl-memcached \
  php-pecl-msgpack \
  php-pecl-redis6 \
  php-pecl-xmlrpc \
  php-pecl-zip

printf '\nPHP setup complete.\n'
