package database

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Test 1: Reject incomplete database configuration.
func TestOpenPoolRejectsIncompleteConfig(t *testing.T) {
	_, err := OpenPool(context.Background(), Config{}, "")

	if err == nil {
		t.Fatal("expected incomplete configuration to be rejected")
	}
}

// Test 2: Reject TLS modes that do not verify the server hostname.
func TestOpenPoolRejectsUnverifiedTLS(t *testing.T) {
	cfg := validPoolConfig()
	cfg.SSLMode = "require"

	_, err := OpenPool(context.Background(), cfg, "")

	if err == nil || !strings.Contains(err.Error(), "verify-full") {
		t.Fatalf("expected TLS verification error, got %v", err)
	}
}

// Test 3: Require a CA certificate file.
func TestOpenPoolRequiresCACertificate(t *testing.T) {
	cfg := validPoolConfig()

	_, err := OpenPool(context.Background(), cfg, "")

	if err == nil || !strings.Contains(err.Error(), "DB_SSLROOTCERT") {
		t.Fatalf("expected missing CA certificate error, got %v", err)
	}
}

// Test 4: Reject an invalid CA certificate.
func TestOpenPoolRejectsInvalidCACertificate(t *testing.T) {
	cfg := validPoolConfig()
	caFile := createPasswordFile(t, "not a valid certificate")

	_, err := OpenPool(context.Background(), cfg, caFile)

	if err == nil || !strings.Contains(err.Error(), "invalid database CA") {
		t.Fatalf("expected invalid CA certificate error, got %v", err)
	}
}

// Test 5: Readiness must fail when the database pool is unavailable.
func TestCheckReadyRejectsNilPool(t *testing.T) {
	err := CheckReady(nil)

	if err == nil {
		t.Fatal("expected readiness failure for nil database pool")
	}
}

// Test 6: Verify connection settings cannot be overridden by
// the selected PostgreSQL environment variables.
func TestPoolConfigIgnoresPostgresEnvironment(t *testing.T) {
	t.Setenv("PGHOST", "unexpected.example.com")
	t.Setenv("PGPORT", "9999")
	t.Setenv("PGUSER", "unexpected_user")
	t.Setenv("PGDATABASE", "unexpected_db")
	t.Setenv("PGSSLMODE", "disable")

	cfg := validPoolConfig()
	caFile := createTestCA(t)

	poolConfig, err := buildPoolConfig(cfg, caFile)
	if err != nil {
		t.Fatalf("buildPoolConfig() failed: %v", err)
	}

	conn := poolConfig.ConnConfig

	if conn.Host != cfg.Host {
		t.Errorf("unexpected host: %q", conn.Host)
	}

	if conn.Port != cfg.Port {
		t.Errorf("unexpected port: %d", conn.Port)
	}

	if conn.User != cfg.User {
		t.Errorf("unexpected user: %q", conn.User)
	}

	if conn.Database != cfg.Name {
		t.Errorf("unexpected database: %q", conn.Database)
	}

	if poolConfig.MaxConns != 10 {
		t.Errorf("expected 10 max connections, got %d", poolConfig.MaxConns)
	}

	if poolConfig.MinConns != 0 {
		t.Errorf("expected 0 min connections, got %d", poolConfig.MinConns)
	}

	if conn.ConnectTimeout != 5*time.Second {
		t.Errorf("expected 5-second connection timeout, got %v", conn.ConnectTimeout)
	}

	if conn.TLSConfig == nil {
		t.Fatal("expected TLS configuration")
	}

	if conn.TLSConfig.InsecureSkipVerify {
		t.Fatal("TLS certificate verification must not be disabled")
	}

	if conn.TLSConfig.ServerName != cfg.Host {
		t.Errorf(
			"expected TLS hostname %q, got %q",
			cfg.Host,
			conn.TLSConfig.ServerName,
		)
	}

	if conn.TLSConfig.MinVersion < tls.VersionTLS12 {
		t.Error("TLS minimum version must be TLS 1.2")
	}

	if conn.TLSConfig.RootCAs == nil {
		t.Error("expected trusted CA certificates")
	}

	if len(conn.Fallbacks) != 0 {
		t.Error("unexpected fallback connection targets")
	}
}

// Helper: Return a valid test database configuration.
func validPoolConfig() Config {
	return Config{
		Host:     "db.example.com",
		Port:     5432,
		Name:     "appdb",
		User:     "app_user",
		Password: "test-password",
		SSLMode:  "verify-full",
	}
}

// Helper: Generate a temporary self-signed CA certificate.
// This certificate is used only for local unit tests.
func createTestCA(t *testing.T) string {
	t.Helper()

	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate test key: %v", err)
	}

	template := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign,
	}

	der, err := x509.CreateCertificate(
		rand.Reader,
		template,
		template,
		&privateKey.PublicKey,
		privateKey,
	)
	if err != nil {
		t.Fatalf("create test certificate: %v", err)
	}

	certificate := pem.EncodeToMemory(
		&pem.Block{
			Type:  "CERTIFICATE",
			Bytes: der,
		},
	)

	path := filepath.Join(t.TempDir(), "test-ca.pem")

	if err := os.WriteFile(path, certificate, 0600); err != nil {
		t.Fatalf("write test certificate: %v", err)
	}

	return path
}
