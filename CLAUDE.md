# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Webhook.site is a webhook testing/logging service. Users get unique URLs to capture HTTP requests in real-time. Built with Laravel 5.4 (PHP backend) and AngularJS 1.x (SPA frontend).

## Common Commands

### Development Setup
```bash
cp .env.example .env
composer install
php artisan key:generate
php artisan migrate
npm install
```

### Asset Compilation
```bash
npm run gulp-dev      # Development build
npm run gulp          # Production build
npm run gulp-watch    # Watch mode
```

### Running the App
```bash
php artisan serve                      # PHP dev server
php artisan queue:work --daemon        # Queue worker (required for IP blocking)
npm run echo                           # Laravel Echo WebSocket server
```

### Docker
```bash
docker-compose up                      # Start all services (app, redis, echo server)
```

### Tests
```bash
./vendor/bin/phpunit                   # Run all tests
./vendor/bin/phpunit --filter TestName # Run single test
```

## Architecture

### Storage Abstraction
The app uses an abstract storage layer in `app/Storage/` with interfaces (`RequestStore`, `TokenStore`) and Redis implementations (`app/Storage/Redis/`). Bindings are registered in `AppServiceProvider`. All data is stored in Redis — there is no SQL database in production.

### Core Entities
- **Token** (`app/Storage/Token.php`): Represents a webhook URL endpoint. Stores response configuration (status, content type, body, timeout, CORS toggle). Identified by UUID.
- **Request** (`app/Storage/Request.php`): Represents a captured HTTP request. Stores headers, body, query params, method, IP, user-agent. Identified by UUID, scoped to a Token.

### Request Flow
1. HTTP request hits `RequestController@store` → stored in Redis → `RequestCreated` event fired
2. `RequestCreated` broadcasts via Laravel Echo (Redis driver → `laravel-echo-server`) to WebSocket clients
3. AngularJS frontend receives broadcast and updates UI in real-time
4. Response returned to caller uses Token's configured status/content-type/body

### Real-time Updates
Laravel Echo broadcasts events via Redis. The `laravel-echo-server` container (port 6001) handles WebSocket connections. Nginx proxies `/socket.io` to the echo server (configured via `ECHO_HOST_MODE=path`).

### Queue Jobs
`BlockIp` and `UnblockIp` jobs in `app/Jobs/` manipulate UFW firewall rules for IP rate-limiting. Requires the queue worker to be running.

### Key Config Values
- `config/app.php`: `max_requests` (500 default), `expiry` (604800s = 7 days)
- Broadcasting driver: Redis (default) or Pusher
- Cache/Queue drivers: Redis

### Routes
All routes are in `app/Http/routes.php`:
- `GET /` → SPA (AngularJS)
- `GET|POST|... /{token}` → capture webhook request
- `GET /token/{token}` → get token config
- `POST /token` → create token
- REST API under `/api/` with token auth

### Frontend
Single-page app in `resources/assets/js/`. Gulp (via Laravel Elixir) compiles assets to `public/`. The AngularJS app communicates with the Laravel API and listens for Echo broadcasts.
