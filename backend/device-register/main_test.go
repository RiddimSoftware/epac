package main

import (
	"context"
	"errors"
	"net/http"
	"testing"

	"epac/device-register/application"

	"github.com/aws/aws-lambda-go/events"
)

type mockUseCase struct {
	err error
}

func (m *mockUseCase) Execute(ctx context.Context, req application.RegisterRequest) error {
	return m.err
}

func TestHandler_HandleRequest(t *testing.T) {
	t.Run("invalid JSON returns 400", func(t *testing.T) {
		h := &Handler{useCase: &mockUseCase{}}
		resp, err := h.HandleRequest(context.Background(), events.APIGatewayProxyRequest{
			Body: `{"token": "xyz",`, // malformed JSON
		})
		if err != nil {
			t.Fatalf("expected no error from handler itself, got %v", err)
		}
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("expected status 400, got %d", resp.StatusCode)
		}
	})

	t.Run("use case token error returns 400", func(t *testing.T) {
		h := &Handler{useCase: &mockUseCase{err: application.ErrTokenRequired}}
		resp, _ := h.HandleRequest(context.Background(), events.APIGatewayProxyRequest{
			Body: `{"token": ""}`,
		})
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("expected status 400, got %d", resp.StatusCode)
		}
	})

	t.Run("use case generic error returns 500", func(t *testing.T) {
		h := &Handler{useCase: &mockUseCase{err: errors.New("db down")}}
		resp, _ := h.HandleRequest(context.Background(), events.APIGatewayProxyRequest{
			Body: `{"token": "xyz"}`,
		})
		if resp.StatusCode != http.StatusInternalServerError {
			t.Errorf("expected status 500, got %d", resp.StatusCode)
		}
	})

	t.Run("successful request returns 200", func(t *testing.T) {
		h := &Handler{useCase: &mockUseCase{err: nil}}
		resp, _ := h.HandleRequest(context.Background(), events.APIGatewayProxyRequest{
			Body: `{"token": "valid"}`,
		})
		if resp.StatusCode != http.StatusOK {
			t.Errorf("expected status 200, got %d", resp.StatusCode)
		}
		expectedBody := `{"status":"ok"}`
		if resp.Body != expectedBody {
			t.Errorf("expected body %s, got %s", expectedBody, resp.Body)
		}
	})
}
