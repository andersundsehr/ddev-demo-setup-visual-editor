# Demo Setup EXT:visual_editor

This repository provides a TYPO3 demo for `EXT:visual_editor`. The project is MySQL-only for both local DDEV development and the standalone Docker setup.

![Screenshot](./screenshot.png)

- Visual Editor project: [https://github.com/friendsoftypo3/visual_editor](https://github.com/FriendsOfTYPO3/visual_editor)
- Standalone image: `ghcr.io/andersundsehr/ddev-demo-setup-visual-editor`

## DDEV Setup

Use this workflow if you want to work on the project locally with DDEV.

### Prerequisites

- [ddev](https://ddev.com/)

### How to set up the demo

1. Clone the repository
2. Run `ddev start`
3. Run `ddev setup`
4. Run `ddev launch /typo3/module/web/edit`
5. If you want to update `EXT:visual_editor`, run `ddev composer u friendsoftypo3/visual-editor`
6. Refresh the committed demo seed artifacts with `ddev update-seed`

`ddev setup` installs Composer dependencies, restores `seed/demo.mysql.sql.gz` via `ddev import-db`, syncs `seed/fileadmin` into `public/fileadmin`, and runs the TYPO3 post-import tasks.

`ddev update-seed` updates:

- `seed/demo.mysql.sql.gz`
- `seed/fileadmin`

Its database export is produced via `ddev export-db`.

## Standalone Docker Setup

The standalone setup requires a MySQL service. Use the checked-in `docker-compose.yaml` to build locally:

```bash
docker compose -f docker-compose.yaml up --build -d
```

Or run the published image with your own Compose stack:

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
      RESET_DEMO_CRON_SCHEDULE: "0 0 * * *"

volumes:
  mysql-data:
```

Start it with:

```bash
docker compose up -d
```

Open the site at:

```text
http://localhost:8080
```

Follow the startup reset logs:

```bash
docker compose logs -f web
```

Stop the demo when you are done:

```bash
docker compose down
```

## Runtime Behavior

- `DATABASE_URL` is required for the standalone container and is parsed into TYPO3's `DB.Connections.Default` config at runtime.
- On container startup, `/usr/local/bin/reset-demo-state startup` rebuilds the MySQL schema, imports `seed/demo.mysql.sql.gz`, restores `seed/fileadmin`, and clears TYPO3 transient state under `var/cache`, `var/lock`, and `public/typo3temp`.
- The scheduled reset timing is controlled by `RESET_DEMO_CRON_SCHEDULE` and defaults to `0 0 * * *`.
- Set `RESET_DEMO_DB_WAIT_TIMEOUT` if your MySQL service needs longer than 60 seconds to become reachable.
- Set `TYPO3_TRUST_ANY_PROXY=1` if the demo runs behind a proxy whose forwarded host and HTTPS headers should be trusted by TYPO3.

## Reset Semantics

- The scheduled reset runs hourly by default.
- Override the timing by setting `RESET_DEMO_CRON_SCHEDULE` to any valid five-field cron expression.
- Set `RESET_DEMO_CRON_SCHEDULE=disabled` to turn off scheduled resets.
- MySQL reset drops all tables and views in the configured schema, runs `php vendor/bin/typo3 setup --force --no-interaction ...`, and imports `seed/demo.mysql.sql.gz`.
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

1. Confirm the services are running:

   ```bash
   docker compose ps
   ```

2. Confirm TYPO3 responds inside the container:

   ```bash
   docker compose exec web /bin/bash -lc 'curl -I -sS http://127.0.0.1'
   ```

3. Confirm the active database backend is seeded:

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
   docker compose exec web /bin/bash -lc "mysql --protocol=TCP -hmysql -P3306 -udemo -pdemo demo -e \"update pages set title = 'Manual Check Mutated' where uid = 1; select uid,title from pages where uid = 1;\""
   docker compose exec web /bin/bash -lc '/usr/local/bin/reset-demo-state manual-check'
   docker compose exec web /bin/bash -lc 'mysql --protocol=TCP -hmysql -P3306 -udemo -pdemo demo -e "select uid,title from pages where uid = 1;"'
   ```

## Validation Status

Expected behavior after these changes:

- `docker compose -f docker-compose.yaml up --build -d` builds the image from the local Dockerfile and starts the demo.
- Startup reset restores the MySQL-backed demo state and `fileadmin`.
- `DATABASE_URL=mysql://demo:demo@mysql:3306/demo` configures TYPO3 without editing PHP config files.
- The scheduled reset cadence remains configurable and defaults to hourly.

# with ♥️ from ![anders und sehr logo](https://www.andersundsehr.com/logo-claim/anders-und-sehr-logo_350px.svg)

> If something did not work 😮
> or you appreciate this Extension 🥰 let us know.

> We are always looking for great people to join our team!
> https://www.andersundsehr.com/karriere/
