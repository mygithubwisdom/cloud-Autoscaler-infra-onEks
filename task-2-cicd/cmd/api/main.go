package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/mygithubwisdom/cloud-Autoscaler-infra-onEks/task-2-cicd/internal/database"
	"github.com/mygithubwisdom/cloud-Autoscaler-infra-onEks/task-2-cicd/internal/httpapi"
)

var version = "dev"

func main() {
	// Load the required PostgreSQL configuration.
	dbConfig, err := database.LoadConfig()
	if err != nil {
		slog.Error("invalid database configuration", "error", err)
		os.Exit(1)
	}

	// Create the bounded PostgreSQL connection pool.
	pool, err := database.OpenPool(
		context.Background(),
		dbConfig,
		os.Getenv("DB_SSLROOTCERT"),
	)
	if err != nil {
		slog.Error("failed to configure database pool", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	// Verify database connectivity before starting the API.
	if err := database.CheckReady(pool); err != nil {
		slog.Error("database unavailable at startup", "error", err)
		os.Exit(1)
	}

	port := envOrDefault("PORT", "8080")

	server := &http.Server{
		Addr: ":" + port,

		// /ready now checks PostgreSQL availability.
		Handler: httpapi.NewHandlerWithReadiness(
			version,
			func() error {
				return database.CheckReady(pool)
			},
		),

		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       75 * time.Second,
	}

	shutdownSignal, stop := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stop()

	go func() {
		slog.Info(
			"starting API",
			"address", server.Addr,
			"version", version,
		)

		if err := server.ListenAndServe(); err != nil &&
			!errors.Is(err, http.ErrServerClosed) {
			slog.Error("API stopped unexpectedly", "error", err)
			os.Exit(1)
		}
	}()

	<-shutdownSignal.Done()
	slog.Info("shutting down API")

	shutdownContext, cancel := context.WithTimeout(
		context.Background(),
		10*time.Second,
	)
	defer cancel()

	if err := server.Shutdown(shutdownContext); err != nil {
		slog.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
