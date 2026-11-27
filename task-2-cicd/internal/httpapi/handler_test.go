package httpapi

import (
	"encoding/json"
	"net/http"
	"errors"
	"net/http/httptest"
	"testing"
)

func TestHealthEndpoint(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	responseRecorder := httptest.NewRecorder()

	NewHandler("test").ServeHTTP(responseRecorder, request)

	if responseRecorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, responseRecorder.Code)
	}

	var body response
	if err := json.NewDecoder(responseRecorder.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Status != "healthy" {
		t.Fatalf("expected healthy status, got %q", body.Status)
	}
}

func TestVersionEndpoint(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/api/version", nil)
	responseRecorder := httptest.NewRecorder()

	NewHandler("abc1234").ServeHTTP(responseRecorder, request)

	if responseRecorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, responseRecorder.Code)
	}

	var body response
	if err := json.NewDecoder(responseRecorder.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Version != "abc1234" {
		t.Fatalf("expected version abc1234, got %q", body.Version)
	}
}

func TestUnknownEndpointReturnsNotFound(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/missing", nil)
	responseRecorder := httptest.NewRecorder()

	NewHandler("test").ServeHTTP(responseRecorder, request)

	if responseRecorder.Code != http.StatusNotFound {
		t.Fatalf("expected status %d, got %d", http.StatusNotFound, responseRecorder.Code)
	}
}

func TestReadyEndpoint(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/ready", nil)
	responseRecorder := httptest.NewRecorder()

	NewHandler("test").ServeHTTP(responseRecorder, request)

	if responseRecorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, responseRecorder.Code)
	}

	var body response
	if err := json.NewDecoder(responseRecorder.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	if body.Status != "ready" {
		t.Fatalf("expected ready status, got %q", body.Status)
	}
}

func TestReadyEndpointWhenDependencyFails(t *testing.T) {
    request := httptest.NewRequest(http.MethodGet, "/ready", nil)
    recorder := httptest.NewRecorder()

    checkReady := func() error {
        return errors.New("database unavailable")
    }

    NewHandlerWithReadiness("test", checkReady).ServeHTTP(recorder, request)

    if recorder.Code != http.StatusServiceUnavailable {
        t.Fatalf(
            "expected status %d, got %d",
            http.StatusServiceUnavailable,
            recorder.Code,
        )
    }

    var body response
    if err := json.NewDecoder(recorder.Body).Decode(&body); err != nil {
        t.Fatalf("decode response: %v", err)
    }

    if body.Status != "not_ready" {
        t.Fatalf("expected not_ready, got %q", body.Status)
    }
}