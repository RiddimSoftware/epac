// health — Lambda that returns JSON status for every pipeline job.
//
// GET /health  →  200 OK if all pipelines healthy, 503 if any stale.
// A pipeline is "stale" when last_success_at is older than 2× expected_interval_hours.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

type PipelineStatus struct {
	Name                string     `json:"name"`
	LastRunAt           *time.Time `json:"last_run_at"`
	LastSuccessAt       *time.Time `json:"last_success_at"`
	LastError           *string    `json:"last_error,omitempty"`
	RecordCount         *int       `json:"record_count,omitempty"`
	ExpectedIntervalHrs int        `json:"expected_interval_hours"`
	Healthy             bool       `json:"healthy"`
	StaleFor            *string    `json:"stale_for,omitempty"`
}

type HealthResponse struct {
	Status    string           `json:"status"`
	CheckedAt time.Time        `json:"checked_at"`
	Pipelines []PipelineStatus `json:"pipelines"`
}

func handler(ctx context.Context, _ events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	conn, err := pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return apiError(503, fmt.Sprintf("db connect: %v", err)), nil
	}
	defer conn.Close(ctx)

	rows, err := conn.Query(ctx, `
		SELECT name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours
		FROM pipeline_health ORDER BY name
	`)
	if err != nil {
		return apiError(503, fmt.Sprintf("query: %v", err)), nil
	}
	defer rows.Close()

	var pipelines []PipelineStatus
	allHealthy := true
	now := time.Now().UTC()

	for rows.Next() {
		var p PipelineStatus
		if err := rows.Scan(&p.Name, &p.LastRunAt, &p.LastSuccessAt, &p.LastError, &p.RecordCount, &p.ExpectedIntervalHrs); err != nil {
			continue
		}
		deadline := time.Duration(p.ExpectedIntervalHrs*2) * time.Hour
		if p.LastSuccessAt == nil || now.Sub(*p.LastSuccessAt) > deadline {
			p.Healthy = false
			allHealthy = false
			if p.LastSuccessAt != nil {
				stale := now.Sub(*p.LastSuccessAt).Round(time.Minute).String()
				p.StaleFor = &stale
			}
		} else {
			p.Healthy = true
		}
		pipelines = append(pipelines, p)
	}
	if err := rows.Err(); err != nil {
		return apiError(503, fmt.Sprintf("rows iteration: %v", err)), nil
	}

	status := "ok"
	if !allHealthy {
		status = "degraded"
	}
	body, _ := json.Marshal(HealthResponse{Status: status, CheckedAt: now, Pipelines: pipelines})
	code := http.StatusOK
	if !allHealthy {
		code = http.StatusServiceUnavailable
	}
	return events.APIGatewayV2HTTPResponse{
		StatusCode: code,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func apiError(code int, msg string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayV2HTTPResponse{StatusCode: code, Headers: map[string]string{"Content-Type": "application/json"}, Body: string(body)}
}

func main() { lambda.Start(observability.WrapAPIGatewayV2("health", handler)) }
