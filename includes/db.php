<?php
/**
 * Database Connection (PDO)
 * LEP Application
 */

declare(strict_types=1);

if (!defined('LEP_APP')) {
    require_once dirname(__DIR__) . '/config/config.php';
}

function getPDO(): PDO
{
    static $pdo = null;

    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $dsn = 'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=' . DB_CHARSET;

    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
        PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci"
    ];

    try {
        $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
    } catch (PDOException $e) {
        // In production log the real error and show a generic message
        error_log('LEP DB Connection Error: ' . $e->getMessage());
        http_response_code(500);
        die('Database connection failed. Please contact the administrator.');
    }

    return $pdo;
}
