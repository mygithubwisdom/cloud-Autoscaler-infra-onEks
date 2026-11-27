package database

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadConfigValid(t *testing.T) {
	passwordFile := createPasswordFile(t, "test-password\n")
	setDatabaseEnv(t, passwordFile)

	config, err := LoadConfig()
	if err != nil {
		t.Fatalf("LoadConfig() failed: %v", err)
	}

	if config.Host != "db.example.com" {
		t.Errorf("unexpected host: %q", config.Host)
	}

	if config.Port != 5432 {
		t.Errorf("expected port 5432, got %d", config.Port)
	}

	if config.Name != "appdb" {
		t.Errorf("expected database appdb, got %q", config.Name)
	}

	if config.User != "app_user" {
		t.Errorf("unexpected database user: %q", config.User)
	}

	if config.Password != "test-password" {
		t.Error("password was not loaded correctly")
	}

	if config.SSLMode != "verify-full" {
		t.Errorf("unexpected SSL mode: %q", config.SSLMode)
	}
}

func TestLoadConfigMissingVariables(t *testing.T) {
	passwordFile := createPasswordFile(t, "test-password")
	setDatabaseEnv(t, passwordFile)

	t.Setenv("DB_HOST", "")

	_, err := LoadConfig()
	if err == nil {
		t.Fatal("expected error when DB_HOST is missing")
	}
}

func TestLoadConfigInvalidPort(t *testing.T) {
	passwordFile := createPasswordFile(t, "test-password")
	setDatabaseEnv(t, passwordFile)

	for _, port := range []string{"invalid", "0", "65536", "-1"} {
		t.Run(port, func(t *testing.T) {
			t.Setenv("DB_PORT", port)

			_, err := LoadConfig()
			if err == nil {
				t.Fatalf("expected error for invalid port %q", port)
			}
		})
	}
}

func TestLoadConfigRequiresVerifiedTLS(t *testing.T) {
	passwordFile := createPasswordFile(t, "test-password")
	setDatabaseEnv(t, passwordFile)

	for _, mode := range []string{"disable", "require", "verify-ca", ""} {
		t.Run("mode_"+mode, func(t *testing.T) {
			t.Setenv("DB_SSLMODE", mode)

			_, err := LoadConfig()
			if err == nil {
				t.Fatalf("expected error for SSL mode %q", mode)
			}
		})
	}
}

func TestLoadConfigMissingPasswordFile(t *testing.T) {
	setDatabaseEnv(t, "/nonexistent/db-password")

	_, err := LoadConfig()
	if err == nil {
		t.Fatal("expected error for missing password file")
	}
}

func TestLoadConfigEmptyPasswordFile(t *testing.T) {
	passwordFile := createPasswordFile(t, "")
	setDatabaseEnv(t, passwordFile)

	_, err := LoadConfig()
	if err == nil {
		t.Fatal("expected error for empty password file")
	}
}

func TestLoadConfigDefaultPort(t *testing.T) {
	passwordFile := createPasswordFile(t, "test-password")
	setDatabaseEnv(t, passwordFile)

	t.Setenv("DB_PORT", "")

	config, err := LoadConfig()
	if err != nil {
		t.Fatalf("LoadConfig() failed: %v", err)
	}

	if config.Port != 5432 {
		t.Errorf("expected default port 5432, got %d", config.Port)
	}
}

func createPasswordFile(t *testing.T, password string) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "db-password")

	if err := os.WriteFile(path, []byte(password), 0600); err != nil {
		t.Fatalf("failed to create password file: %v", err)
	}

	return path
}

func setDatabaseEnv(t *testing.T, passwordFile string) {
	t.Helper()

	vars := map[string]string{
		"DB_HOST":          "db.example.com",
		"DB_PORT":          "5432",
		"DB_NAME":          "appdb",
		"DB_USER":          "app_user",
		"DB_PASSWORD_FILE": passwordFile,
		"DB_SSLMODE":       "verify-full",
	}

	for key, value := range vars {
		t.Setenv(key, strings.TrimSpace(value))
	}
}
