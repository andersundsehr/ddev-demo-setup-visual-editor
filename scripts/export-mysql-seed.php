#!/usr/bin/env php
<?php

declare(strict_types=1);

use Doctrine\DBAL\DriverManager;
use Doctrine\DBAL\Schema\Column;
use Doctrine\DBAL\Types\BinaryType;
use Doctrine\DBAL\Types\BlobType;

require dirname(__DIR__) . '/vendor/autoload.php';

if ($argc !== 3) {
    fwrite(STDERR, "Usage: export-mysql-seed.php <sqlite-source> <mysql-seed-target>\n");
    exit(1);
}

$source = $argv[1];
$target = $argv[2];

if (!is_file($source)) {
    fwrite(STDERR, sprintf("Source database not found: %s\n", $source));
    exit(1);
}

$targetDirectory = dirname($target);
if (!is_dir($targetDirectory) && !mkdir($targetDirectory, 0775, true) && !is_dir($targetDirectory)) {
    fwrite(STDERR, sprintf("Failed to create target directory: %s\n", $targetDirectory));
    exit(1);
}

$connection = DriverManager::getConnection([
    'driver' => 'sqlite3',
    'path' => $source,
]);

$schemaManager = $connection->createSchemaManager();
$tableNames = $schemaManager->listTableNames();
sort($tableNames, SORT_STRING);

$sql = "-- MySQL baseline data generated from seed/demo.sqlite\n";
$sql .= "SET NAMES utf8mb4;\n";
$sql .= "SET FOREIGN_KEY_CHECKS = 0;\n";
$sql .= "SET UNIQUE_CHECKS = 0;\n\n";

foreach ($tableNames as $tableName) {
    $quotedTableName = quoteMySqlIdentifier($tableName);
    /** @var array<string, Column> $columns */
    $columns = $schemaManager->listTableColumns($tableName);
    $columnNames = array_keys($columns);
    $quotedColumns = implode(', ', array_map('quoteMySqlIdentifier', $columnNames));

    $sql .= sprintf("DELETE FROM %s;\n", $quotedTableName);

    $result = $connection->executeQuery(sprintf('SELECT * FROM %s', $quotedTableName));
    $batch = [];

    foreach ($result->iterateAssociative() as $row) {
        $values = [];
        foreach ($columnNames as $columnName) {
            $values[] = toSqlLiteral($row[$columnName] ?? null, $columns[$columnName]);
        }
        $batch[] = '(' . implode(', ', $values) . ')';

        if (count($batch) === 100) {
            $sql .= sprintf(
                "INSERT INTO %s (%s) VALUES\n  %s;\n",
                $quotedTableName,
                $quotedColumns,
                implode(",\n  ", $batch)
            );
            $batch = [];
        }
    }

    if ($batch !== []) {
        $sql .= sprintf(
            "INSERT INTO %s (%s) VALUES\n  %s;\n",
            $quotedTableName,
            $quotedColumns,
            implode(",\n  ", $batch)
        );
    }

    $sql .= "\n";
}

$sql .= "SET UNIQUE_CHECKS = 1;\n";
$sql .= "SET FOREIGN_KEY_CHECKS = 1;\n";

writeDeterministicGzip($target, $sql);

function toSqlLiteral(mixed $value, Column $column): string
{
    if ($value === null) {
        return 'NULL';
    }

    $type = $column->getType();
    if ($type instanceof BinaryType || $type instanceof BlobType) {
        return "X'" . strtoupper(bin2hex((string)$value)) . "'";
    }

    if (is_int($value) || is_float($value)) {
        return (string)$value;
    }

    if (is_bool($value)) {
        return $value ? '1' : '0';
    }

    $escaped = str_replace(
        ["\\", "\0", "\n", "\r", "\x1a", "'"],
        ["\\\\", "\\0", "\\n", "\\r", "\\Z", "\\'"],
        (string)$value
    );

    return "'" . $escaped . "'";
}

function quoteMySqlIdentifier(string $identifier): string
{
    return '`' . str_replace('`', '``', $identifier) . '`';
}

function writeDeterministicGzip(string $target, string $contents): void
{
    $header = "\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03";
    $compressed = gzdeflate($contents, 9);

    if ($compressed === false) {
        fwrite(STDERR, sprintf("Failed to gzip output: %s\n", $target));
        exit(1);
    }

    $trailer = pack('V', crc32($contents)) . pack('V', strlen($contents) & 0xffffffff);
    $bytesWritten = file_put_contents($target, $header . $compressed . $trailer);

    if ($bytesWritten === false) {
        fwrite(STDERR, sprintf("Failed to write target file: %s\n", $target));
        exit(1);
    }
}
