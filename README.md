# Demo Setup EXT:visual_editor

This repository provides a TYPO3 demo for `EXT:visual_editor`. It can be used either as a local DDEV setup for development work or as a published standalone Docker image backed by SQLite by default.

![Screenshot](./screenshot.png)

- Visual Editor project: https://github.com/andersundsehr/visual_editor
- Standalone image: `ghcr.io/andersundsehr/ddev-demo-setup-visual-editor`

## Standalone Container

The demo is also available as a standalone container, so you can run it directly without setting up DDEV or a separate database service.

```bash
docker run --rm -p 8080:80 ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest
```

## DDEV Setup

Use this workflow if you want to work on the project locally with DDEV.

### Prerequisites

- [ddev](https://ddev.com/)

### How to set up the demo

1. Clone the repository
2. Run `ddev start`
3. Run `ddev setup`
4. Run `ddev launch /typo3/module/web/edit`
5. If you want to update the `EXT:visual_editor` run this: `ddev composer u friendsoftypo3/visual-editor`
6. Refresh the committed demo seed artifacts with `ddev update-seed`

`ddev update-seed` updates:

- `seed/demo.sqlite`
- `seed/demo.mysql.sql.gz`
- `seed/fileadmin`

The MySQL seed dump is generated from the current SQLite demo state in DDEV.

## Standalone Docker Setup

Use this workflow if you want to run the published image directly or build the standalone container locally.

### Prerequisites

- Docker
- Docker Compose

### Option 1: Run the published container with one command

```bash
docker run --rm -p 8080:80 ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest
```

Override the scheduled reset timing with `RESET_DEMO_CRON_SCHEDULE`:

```bash
docker run --rm -p 8080:80 \
  -e RESET_DEMO_CRON_SCHEDULE="*/15 * * * *" \
  ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest
```

Allow TYPO3 to trust forwarded host and HTTPS headers from any proxy:

```bash
docker run --rm -p 8080:80 \
  -e TYPO3_TRUST_ANY_PROXY=1 \
  ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest
```

Disable scheduled resets entirely:

```bash
docker run --rm -p 8080:80 \
  -e RESET_DEMO_CRON_SCHEDULE=disabled \
  ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest
```

### Option 2: Build and run locally with Docker Compose

```bash
docker compose up --build -d
```

### Option 3: Run the published image with your own `docker-compose.yaml`

```yaml
services:
  web:
    image: ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest
    ports:
      - "8080:80"
    environment:
      TYPO3_TRUST_ANY_PROXY: "0"
      RESET_DEMO_CRON_SCHEDULE: "0 * * * *"
```

Start it with:

```bash
docker compose up -d
```

Open the site at:

```text
http://localhost:8080
```

Follow the container logs while the startup reset runs:

```bash
docker compose logs -f web
```

Stop the demo when you are done:

```bash
docker compose down
```

If you started the container with `docker run`, stop it with `Ctrl+C` or by removing the container from another shell.

### Option 4: Run the standalone image with a MySQL container

Set `DATABASE_URL` to switch TYPO3 from the default SQLite database to another Doctrine DBAL-supported backend. For MySQL, use a URL in this format:

```text
mysql://demo:demo@mysql:3306/demo
```

Example `docker-compose.yaml`:

```yaml
services:
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_DATABASE: demo
      MYSQL_USER: demo
      MYSQL_PASSWORD: demo
      MYSQL_ROOT_PASSWORD: root
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -uroot -proot --silent"]
      interval: 5s
      timeout: 3s
      retries: 20
    volumes:
      - mysql-data:/var/lib/mysql

  web:
    image: ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest
    depends_on:
      mysql:
        condition: service_healthy
    ports:
      - "8080:80"
    environment:
      DATABASE_URL: mysql://demo:demo@mysql:3306/demo
      TYPO3_TRUST_ANY_PROXY: "0"
      RESET_DEMO_CRON_SCHEDULE: disabled

volumes:
  mysql-data:
```

Start it with:

```bash
docker compose up -d
```

Important notes for the MySQL flow:

- The published image still defaults to SQLite when `DATABASE_URL` is unset.
- `DATABASE_URL` is parsed into TYPO3's `DB.Connections.Default` config at runtime.
- The image ships a baseline data dump at `seed/demo.mysql.sql.gz` for MySQL-backed startup and reset.
- On MySQL, startup and reset rebuild the schema via `php vendor/bin/typo3 setup --force --no-interaction ...` and then import the baseline dump.
- Set `RESET_DEMO_DB_WAIT_TIMEOUT` if your MySQL service needs longer than 60 seconds to become reachable.

## Runtime Behavior

- TYPO3 uses SQLite at `var/sqlite/demo.sqlite` inside the container runtime unless `DATABASE_URL` is set.
- On container startup, `/usr/local/bin/reset-demo-state startup` restores:
  - the seeded SQLite database from `seed/demo.sqlite`, or
  - the seeded MySQL baseline from `seed/demo.mysql.sql.gz` after rebuilding the schema
  - the public assets baseline from `seed/fileadmin`
  - TYPO3 transient state under `var/cache`, `var/lock`, and `public/typo3temp`
- Reset logs are written to the container log stream and can be inspected with:

  ```bash
  docker compose logs web
  ```

- The scheduled reset timing is controlled by `RESET_DEMO_CRON_SCHEDULE` and defaults to `0 * * * *`.
- Set `TYPO3_TRUST_ANY_PROXY=1` if the demo runs behind a proxy whose forwarded host and HTTPS headers should be trusted by TYPO3.
- Set `DATABASE_URL` to override the default SQLite connection, for example `mysql://demo:demo@mysql:3306/demo`.

## Reset Semantics

- The scheduled reset runs hourly by default.
- Override the timing by setting `RESET_DEMO_CRON_SCHEDULE` to any valid five-field cron expression.
- Set `RESET_DEMO_CRON_SCHEDULE=disabled` to turn off scheduled resets.
- `RESET_DEMO_DB_WAIT_TIMEOUT` controls how long MySQL startup/reset waits for the database and defaults to `60`.
- SQLite reset restores `seed/demo.sqlite` into `var/sqlite/demo.sqlite`.
- MySQL reset drops all tables and views in the configured schema, runs `php vendor/bin/typo3 setup --force --no-interaction ...`, and imports `seed/demo.mysql.sql.gz`.
- Default cron entry:

  ```cron
  0 * * * * root /usr/local/bin/reset-demo-state scheduled >/proc/1/fd/1 2>/proc/1/fd/2
  ```

- Manual execution uses the same restore script:

  ```bash
  docker compose exec web /usr/local/bin/reset-demo-state manual-check
  ```

## Container Publishing

GitHub Actions builds the image for pull requests and publishes a multi-architecture image to GHCR on pushes to `main`.

Published tags:

- `ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest`
- `ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:sha-<shortsha>`

Each published tag resolves to:

- `linux/amd64`
- `linux/arm64`

## Manual Verification

Use these checks if you want to confirm the demo state yourself.

1. Confirm the service is running:

   ```bash
   docker compose ps
   ```

2. Confirm TYPO3 responds inside the container:

   ```bash
   docker compose exec web /bin/bash -lc 'curl -I -sS http://127.0.0.1'
   ```

3. Confirm the active database backend is seeded:

   ```bash
   docker compose exec web /bin/bash -lc 'php -m | grep -E "pdo_sqlite|sqlite3"'
   docker compose exec web /bin/bash -lc 'sqlite3 /app/var/sqlite/demo.sqlite "select uid,title from pages order by uid limit 5;"'
   ```

   For MySQL-based runs, inspect the configured connection instead:

   ```bash
   docker compose exec web /bin/bash -lc 'php -m | grep -E "pdo_mysql"'
   docker compose exec web env | grep '^DATABASE_URL='
   docker compose exec web /bin/bash -lc 'mysql --protocol=TCP -hmysql -P3306 -udemo -pdemo demo -e "select uid,title from pages order by uid limit 5;"'
   ```

4. Confirm seeded files exist:

   ```bash
   docker compose exec web /bin/bash -lc 'find /app/public/fileadmin -maxdepth 2 -type f | sort | head -n 10'
   ```

5. Validate file reset behavior:

   ```bash
   docker compose exec web /bin/bash -lc 'printf "temp\n" > /app/public/fileadmin/user_upload/phase6-temp.txt'
   docker compose exec web /bin/bash -lc '/usr/local/bin/reset-demo-state manual-check'
   docker compose exec web /bin/bash -lc 'test ! -e /app/public/fileadmin/user_upload/phase6-temp.txt && echo restored'
   ```

6. Validate database reset behavior:

   ```bash
   docker compose exec web /bin/bash -lc "sqlite3 /app/var/sqlite/demo.sqlite \"update pages set title = 'Manual Check Mutated' where uid = 1;\""
   docker compose exec web /bin/bash -lc 'sqlite3 /app/var/sqlite/demo.sqlite "select uid,title from pages where uid = 1;"'
   docker compose exec web /bin/bash -lc '/usr/local/bin/reset-demo-state manual-check'
   docker compose exec web /bin/bash -lc 'sqlite3 /app/var/sqlite/demo.sqlite "select uid,title from pages where uid = 1;"'
   ```

   For MySQL-based runs:

   ```bash
   docker compose exec web /bin/bash -lc "mysql --protocol=TCP -hmysql -P3306 -udemo -pdemo demo -e \"update pages set title = 'Manual Check Mutated' where uid = 1; select uid,title from pages where uid = 1;\""
   docker compose exec web /bin/bash -lc '/usr/local/bin/reset-demo-state manual-check'
   docker compose exec web /bin/bash -lc 'mysql --protocol=TCP -hmysql -P3306 -udemo -pdemo demo -e "select uid,title from pages where uid = 1;"'
   ```

## Validation Status

Expected behavior after these changes:

- `docker compose up --build -d` builds the image from the local Dockerfile and starts the demo.
- `docker run --rm -p 8080:80 ghcr.io/andersundsehr/ddev-demo-setup-visual-editor:latest` starts the published demo image directly on both `amd64` and `arm64` hosts.
- Startup reset restores the baseline SQLite or MySQL-backed demo state and `fileadmin`.
- `DATABASE_URL=mysql://demo:demo@mysql:3306/demo` switches TYPO3 to MySQL without editing PHP config files.
- The scheduled reset cadence remains configurable and defaults to hourly.

# with ♥️ from ![anders und sehr logo](https://www.andersundsehr.com/logo-claim/anders-und-sehr-logo_350px.svg)

> If something did not work 😮
> or you appreciate this Extension 🥰 let us know.

> We are always looking for great people to join our team!
> https://www.andersundsehr.com/karriere/
