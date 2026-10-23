<?php
// Args: host, user, password, database, type, optional encryption mode (0, 1 or 2).
// The entrypoint passes the mode only for an initial unattended installation.
$stderr = fopen('php://stderr', 'w');

function databaseError(string $message): never
{
	fwrite(STDERR, "\n" . $message . "\n");
	exit(1);
}

if ($argc < 6 || $argc > 7)
{
	databaseError('Expected database host, user, password, name, type and optional encryption mode.');
}

$host = $argv[1];
$port = null;

if (preg_match('/^\[([^\]]+)\](?::([0-9]+))?$/', $host, $matches))
{
	$host = $matches[1];
	$port = $matches[2] ?? null;
}
elseif (substr_count($host, ':') === 1)
{
	[$host, $port] = explode(':', $host, 2);
}

if ($host === '' || ($port !== null && (!ctype_digit($port) || (int) $port < 1 || (int) $port > 65535)))
{
	databaseError('Invalid database host or port.');
}

$user = $argv[2];
$password = $argv[3];
$db = $argv[4];
$dbType = strtolower($argv[5]);
$encryption = $argv[6] ?? '0';

if (!in_array($dbType, ['mysqli', 'pgsql'], true))
{
	databaseError("Invalid database type. Please provide 'pgsql' or 'mysqli'.");
}

if (!in_array($encryption, ['0', '1', '2'], true))
{
	databaseError('Database encryption mode must be 0, 1 or 2.');
}

if ($db === '' || str_contains($db, "\0"))
{
	databaseError('Database name must be nonempty and contain no NUL bytes.');
}

$tls = $encryption !== '0';
$verify = true;
$ca = $cert = $key = $cipher = null;

// Mode 0 deliberately does not read TLS environment variables. Browser setup
// keeps its existing connection behaviour even if TLS variables are present.
if ($tls)
{
	$verification = getenv('JOOMLA_DB_SSL_VERIFY_SERVER_CERT');
	$verification = $verification === false ? '1' : $verification;
	if (!in_array($verification, ['0', '1'], true))
	{
		databaseError('JOOMLA_DB_SSL_VERIFY_SERVER_CERT must be 0 or 1.');
	}
	$verify = $verification === '1';
	if (!$verify && getenv('JOOMLA_DB_SSL_CA_FILE') !== false)
	{
		databaseError('A database CA file requires JOOMLA_DB_SSL_VERIFY_SERVER_CERT=1.');
	}

	if ($host === 'localhost' || str_starts_with($host, '/'))
	{
		databaseError('Database TLS requires a TCP hostname matching the server certificate, not localhost or a socket path.');
	}

	$requiredFiles = $verify ? ['ca' => 'JOOMLA_DB_SSL_CA_FILE'] : [];
	if ($encryption === '2')
	{
		$requiredFiles += ['cert' => 'JOOMLA_DB_SSL_CERT_FILE', 'key' => 'JOOMLA_DB_SSL_KEY_FILE'];
	}
	foreach ($requiredFiles as $option => $variable)
	{
		$path = getenv($variable);
		if ($path === false || $path === '' || !is_file($path) || !is_readable($path))
		{
			databaseError($variable . ' must name a readable regular file.');
		}
		${$option} = $path;
	}

	if ($encryption === '2')
	{
		if (!function_exists('openssl_x509_check_private_key'))
		{
			databaseError('PHP OpenSSL support is required for database client certificates.');
		}
		$certificate = @openssl_x509_read('file://' . $cert);
		$privateKey = @openssl_pkey_get_private('file://' . $key);
		if ($certificate === false || $privateKey === false || !@openssl_x509_check_private_key($certificate, $privateKey))
		{
			databaseError('Database client certificate and private key must be valid, matching PEM files without a key passphrase.');
		}
		unset($certificate, $privateKey);
	}

	$cipher = getenv('JOOMLA_DB_SSL_CIPHER');
	$cipher = $cipher === false || $cipher === '' ? null : $cipher;
	if ($cipher !== null && ($dbType !== 'mysqli' || $encryption !== '2'))
	{
		databaseError('JOOMLA_DB_SSL_CIPHER is supported only for mysqli encryption mode 2.');
	}
}

fwrite($stderr, "\nEnsuring Joomla database is present\n");

if ($dbType === 'mysqli')
{
	$port = $port !== null ? (int) $port : 3306;
	$maxTries = 10;

	// Keep explicit connection retries with PHP 8.1+ instead of exceptions.
	mysqli_report(MYSQLI_REPORT_OFF);

	do {
		$mysql = mysqli_init();
		if ($mysql === false)
		{
			databaseError('Cannot initialize the MySQL connection.');
		}
		$flags = 0;
		if ($tls)
		{
			// mysqlnd can return false for this legacy option. Like Joomla,
			// use the SSL flags below to select verified or unverified TLS.
			$mysql->options(MYSQLI_OPT_SSL_VERIFY_SERVER_CERT, $verify);
			if (!$mysql->ssl_set($key, $cert, $ca, null, $cipher))
			{
				databaseError('Cannot configure MySQL TLS.');
			}
			$flags = MYSQLI_CLIENT_SSL;
			if (!$verify && defined('MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT'))
			{
				$flags |= MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT;
			}
		}

		$connected = @$mysql->real_connect($host, $user, $password, '', $port, null, $flags);
		if (!$connected)
		{
			fwrite($stderr, "\nMySQL connection failed (error {$mysql->connect_errno}).\n");
			unset($mysql);
			if (--$maxTries <= 0)
			{
				databaseError($tls ? 'Cannot establish the requested MySQL TLS connection; no unencrypted fallback was attempted.' : 'Cannot connect to MySQL.');
			}
			sleep(3);
		}
	} while (!$connected);

	if ($tls)
	{
		$result = $mysql->query("SHOW SESSION STATUS LIKE 'Ssl_cipher'");
		$row = $result ? $result->fetch_row() : null;
		if ($result)
		{
			$result->free();
		}
		if (empty($row[1]))
		{
			$mysql->close();
			databaseError('MySQL did not negotiate TLS; refusing database creation.');
		}
	}

	// Database names are identifiers, not SQL string literals.
	if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . str_replace('`', '``', $db) . '`'))
	{
		$mysql->close();
		databaseError("MySQL 'CREATE DATABASE' failed.");
	}
	fwrite($stderr, "\nMySQL Database Created\n");
	$mysql->close();
}
else
{
	$port = $port !== null ? (int) $port : 5432;
	$maxTries = 10;
	$parameters = ['host' => $host, 'port' => (string) $port, 'user' => $user, 'password' => $password, 'dbname' => 'postgres'];
	if ($tls)
	{
		$parameters['sslmode'] = $verify ? 'verify-full' : 'require';
		$parameters['gssencmode'] = 'disable';
		foreach (['sslrootcert' => $ca, 'sslcert' => $cert, 'sslkey' => $key] as $name => $value)
		{
			if ($value !== null)
			{
				$parameters[$name] = $value;
			}
		}
	}
	$connection = '';
	foreach ($parameters as $name => $value)
	{
		$connection .= $name . "='" . str_replace(['\\', "'"], ['\\\\', "\\'"], $value) . "' ";
	}

	do {
		$dbconn = @pg_connect($connection);
		if (!$dbconn)
		{
			fwrite($stderr, "\nPostgreSQL connection failed.\n");
			if (--$maxTries <= 0)
			{
				databaseError($tls ? 'Cannot establish the requested PostgreSQL TLS connection; no unencrypted fallback was attempted.' : 'Cannot connect to PostgreSQL.');
			}
			sleep(3);
		}
	} while (!$dbconn);

	if ($tls)
	{
		$result = @pg_query($dbconn, 'SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()');
		$encrypted = $result && pg_num_rows($result) === 1 && pg_fetch_result($result, 0, 0) === 't';
		if ($result)
		{
			pg_free_result($result);
		}
		if (!$encrypted)
		{
			pg_close($dbconn);
			databaseError('PostgreSQL did not negotiate TLS; refusing database creation.');
		}
	}

	$result = @pg_query_params($dbconn, 'SELECT 1 FROM pg_database WHERE datname = $1', [$db]);
	if (!$result)
	{
		pg_close($dbconn);
		databaseError('Cannot check whether the PostgreSQL database exists.');
	}
	$exists = pg_num_rows($result) !== 0;
	pg_free_result($result);
	if (!$exists && !@pg_query($dbconn, 'CREATE DATABASE ' . pg_escape_identifier($dbconn, $db)))
	{
		pg_close($dbconn);
		databaseError("PostgreSQL 'CREATE DATABASE' failed.");
	}
	fwrite($stderr, "\nPostgreSQL Database Created\n");
	pg_close($dbconn);
}
