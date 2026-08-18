#!/bin/sh
set -e

# Coolify injects env vars into the container directly - it does not write a
# .env file - so config:cache must happen here at boot (after those vars
# exist), never at Docker build time, or it would bake in empty values.
php artisan config:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache

exec "$@"
