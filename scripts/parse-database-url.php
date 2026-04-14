<?php

declare(strict_types=1);

$parseDatabaseUrl = require __DIR__ . '/database-url.php';
$databaseConfiguration = $parseDatabaseUrl($argv[1] ?? null);

if ($databaseConfiguration === null) {
    throw new RuntimeException('DATABASE_URL must be set for the MySQL-only demo image.');
}

$variables = [
    'RESET_DATABASE_HOST' => $databaseConfiguration['host'],
    'RESET_DATABASE_PORT' => (string)$databaseConfiguration['port'],
    'RESET_DATABASE_NAME' => $databaseConfiguration['dbname'],
    'RESET_DATABASE_USER' => $databaseConfiguration['user'],
    'RESET_DATABASE_PASSWORD' => $databaseConfiguration['password'],
];

foreach ($variables as $key => $value) {
    $escapedValue = str_replace("'", "'\"'\"'", (string)$value);
    echo $key . "='" . $escapedValue . "'" . PHP_EOL;
}
