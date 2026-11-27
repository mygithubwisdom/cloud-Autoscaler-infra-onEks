package database

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	maxConnections   = 10
	connectTimeout   = 5 * time.Second
	readinessTimeout = 2 * time.Second
)

// buildPoolConfig prepares the database connection configuration.
// It does not connect to PostgreSQL.
func buildPoolConfig(cfg Config, caFile string) (*pgxpool.Config, error) {
	if strings.TrimSpace(cfg.Host) == "" ||
		strings.TrimSpace(cfg.Name) == "" ||
		strings.TrimSpace(cfg.User) == "" ||
		cfg.Password == "" ||
		cfg.Port == 0 {
		return nil, errors.New("incomplete database configuration")
	}

	if cfg.SSLMode != "verify-full" {
		return nil, errors.New("database TLS mode must be verify-full")
	}

	if strings.TrimSpace(caFile) == "" {
		return nil, errors.New("DB_SSLROOTCERT is required")
	}

	caPEM, err := os.ReadFile(caFile)
	if err != nil {
		return nil, fmt.Errorf("read database CA certificate: %w", err)
	}

	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(caPEM) {
		return nil, errors.New("invalid database CA certificate")
	}

	connString := "host=" + quoteConnValue(cfg.Host) +
		" port=" + strconv.Itoa(int(cfg.Port)) +
		" dbname=" + quoteConnValue(cfg.Name) +
		" user=" + quoteConnValue(cfg.User) +
		" sslmode=verify-full" +
		" connect_timeout=5"

	poolConfig, err := pgxpool.ParseConfig(connString)
	if err != nil {
		return nil, errors.New("invalid PostgreSQL pool configuration")
	}

	poolConfig.ConnConfig.Host = cfg.Host
	poolConfig.ConnConfig.Port = cfg.Port
	poolConfig.ConnConfig.Database = cfg.Name
	poolConfig.ConnConfig.User = cfg.User
	poolConfig.ConnConfig.Password = cfg.Password
	poolConfig.ConnConfig.ConnectTimeout = connectTimeout

	poolConfig.ConnConfig.TLSConfig = &tls.Config{
		MinVersion: tls.VersionTLS12,
		ServerName: cfg.Host,
		RootCAs:    roots,
	}

	poolConfig.ConnConfig.Fallbacks = nil

	poolConfig.MaxConns = maxConnections
	poolConfig.MinConns = 0

	return poolConfig, nil
}

// OpenPool creates a bounded PostgreSQL connection pool.
func OpenPool(ctx context.Context, cfg Config, caFile string) (*pgxpool.Pool, error) {
	poolConfig, err := buildPoolConfig(cfg, caFile)
	if err != nil {
		return nil, err
	}

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, errors.New("failed to create PostgreSQL pool")
	}

	return pool, nil
}

// CheckReady verifies PostgreSQL availability.
func CheckReady(pool *pgxpool.Pool) error {
	if pool == nil {
		return errors.New("database pool is unavailable")
	}

	ctx, cancel := context.WithTimeout(context.Background(), readinessTimeout)
	defer cancel()

	if err := pool.Ping(ctx); err != nil {
		return errors.New("database readiness check failed")
	}

	return nil
}

// quoteConnValue escapes a PostgreSQL connection-string value.
func quoteConnValue(value string) string {
	value = strings.ReplaceAll(value, "\\", "\\\\")
	value = strings.ReplaceAll(value, "'", "\\'")
	return "'" + value + "'"
}
