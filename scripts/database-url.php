<?php

return static function (?string $databaseUrl): ?array {
    if ($databaseUrl === null || trim($databaseUrl) === '') {
        return null;
    }

    $databaseUrl = trim($databaseUrl);
    $databaseUrl = preg_replace('#^mysql\+pdo://#', 'mysql://', $databaseUrl) ?? $databaseUrl;
    $databaseUrl = preg_replace('#^pdo[-_]?mysql://#', 'mysql://', $databaseUrl) ?? $databaseUrl;

    $parsedUrl = parse_url($databaseUrl);
    if ($parsedUrl === false || !isset($parsedUrl['scheme'])) {
        throw new \InvalidArgumentException('DATABASE_URL must be a valid database URL.');
    }

    return match ($parsedUrl['scheme']) {
        'mysql' => (static function (array $parsedUrl): array {
            $host = $parsedUrl['host'] ?? '';
            $databaseName = isset($parsedUrl['path']) ? ltrim($parsedUrl['path'], '/') : '';

            if ($host === '' || $databaseName === '') {
                throw new \InvalidArgumentException(
                    'DATABASE_URL for MySQL must contain both host and database name.'
                );
            }

            $databaseName = urldecode($databaseName);
            $user = isset($parsedUrl['user']) ? urldecode($parsedUrl['user']) : '';
            $password = isset($parsedUrl['pass']) ? urldecode($parsedUrl['pass']) : '';
            $port = isset($parsedUrl['port']) ? (int)$parsedUrl['port'] : 3306;

            return [
                'scheme' => 'mysql',
                'host' => $host,
                'port' => $port,
                'dbname' => $databaseName,
                'user' => $user,
                'password' => $password,
                'typo3Connection' => [
                    'driver' => 'pdo_mysql',
                    'host' => $host,
                    'port' => $port,
                    'dbname' => $databaseName,
                    'user' => $user,
                    'password' => $password,
                ],
            ];
        })($parsedUrl),
        default => throw new \InvalidArgumentException(
            sprintf('DATABASE_URL scheme "%s" is not supported.', $parsedUrl['scheme'])
        ),
    };
};
