package database

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Host     string
	Port     uint16
	Name     string
	User     string
	Password string
	SSLMode  string
}

func LoadConfig() (Config, error) {
	host := strings.TrimSpace(os.Getenv("DB_HOST"))
	name := strings.TrimSpace(os.Getenv("DB_NAME"))
	user := strings.TrimSpace(os.Getenv("DB_USER"))
	passwordFile := strings.TrimSpace(os.Getenv("DB_PASSWORD_FILE"))
	sslMode := strings.TrimSpace(os.Getenv("DB_SSLMODE"))

	if host == "" || name == "" || user == "" || passwordFile == "" {
		return Config{}, errors.New(
			"DB_HOST, DB_NAME, DB_USER and DB_PASSWORD_FILE are required",
		)
	}

	if sslMode != "verify-full" {
		return Config{}, errors.New("DB_SSLMODE must be verify-full")
	}

	portValue := strings.TrimSpace(os.Getenv("DB_PORT"))
	if portValue == "" {
		portValue = "5432"
	}

	port, err := strconv.ParseUint(portValue, 10, 16)
	if err != nil || port == 0 {
		return Config{}, fmt.Errorf("invalid DB_PORT: %q", portValue)
	}

	passwordBytes, err := os.ReadFile(passwordFile)
	if err != nil {
		return Config{}, fmt.Errorf("read DB_PASSWORD_FILE: %w", err)
	}

	password := strings.TrimSuffix(string(passwordBytes), "\n")
	password = strings.TrimSuffix(password, "\r")

	if password == "" {
		return Config{}, errors.New("DB_PASSWORD_FILE contains an empty password")
	}

	return Config{
		Host:     host,
		Port:     uint16(port),
		Name:     name,
		User:     user,
		Password: password,
		SSLMode:  sslMode,
	}, nil
}
