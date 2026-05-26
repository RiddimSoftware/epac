package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const (
	maxDeviceIDLen   = 64
	maxAppVersionLen = 32
	maxOSVersionLen  = 32
	maxEventNameLen  = 128
	maxOperationLen  = 64
	maxMessageLen    = 512
	maxAttrKeyLen    = 32
	maxAttrValueLen  = 256
	maxAttrKeys      = 16
	maxBatchSize     = 100
	maxDurationMs    = 600_000
)

type TelemetryRequest struct {
	DeviceID   string           `json:"device_id"`
	AppVersion string           `json:"app_version"`
	OSVersion  string           `json:"os_version"`
	Events     []TelemetryEvent `json:"events"`
}

type TelemetryEvent struct {
	Type       string            `json:"type"`
	Name       string            `json:"name"`
	Operation  string            `json:"operation"`
	Message    string            `json:"message"`
	DurationMs *int              `json:"duration_ms"`
	Attributes map[string]string `json:"attributes"`
	Ts         string            `json:"ts"`
}

var emfWriter io.Writer = os.Stderr

func handler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	method := req.RequestContext.HTTP.Method
	if method != http.MethodPost {
		return jsonResponse(http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"}), nil
	}

	ct := headerValue(req.Headers, "Content-Type")
	if !strings.HasPrefix(strings.ToLower(strings.TrimSpace(ct)), "application/json") {
		return jsonResponse(http.StatusUnsupportedMediaType, map[string]string{"error": "unsupported media type"}), nil
	}

	var body TelemetryRequest
	if err := json.Unmarshal([]byte(req.Body), &body); err != nil {
		return jsonResponse(http.StatusBadRequest, map[string]string{"error": "invalid JSON body"}), nil
	}

	if err := validateRequest(&body); err != nil {
		return jsonResponse(http.StatusBadRequest, map[string]string{"error": err.Error()}), nil
	}

	for i := range body.Events {
		emitEMF(&body, &body.Events[i])
	}

	return events.APIGatewayV2HTTPResponse{StatusCode: http.StatusNoContent}, nil
}

func validateRequest(r *TelemetryRequest) error {
	if r.DeviceID == "" {
		return fmt.Errorf("device_id is required")
	}
	if len(r.DeviceID) > maxDeviceIDLen {
		return fmt.Errorf("device_id exceeds %d characters", maxDeviceIDLen)
	}
	if len(r.AppVersion) > maxAppVersionLen {
		return fmt.Errorf("app_version exceeds %d characters", maxAppVersionLen)
	}
	if len(r.OSVersion) > maxOSVersionLen {
		return fmt.Errorf("os_version exceeds %d characters", maxOSVersionLen)
	}
	if len(r.Events) == 0 {
		return fmt.Errorf("events is required and must not be empty")
	}
	if len(r.Events) > maxBatchSize {
		return fmt.Errorf("events exceeds maximum batch size of %d", maxBatchSize)
	}
	for i := range r.Events {
		if err := validateEvent(&r.Events[i]); err != nil {
			return fmt.Errorf("events[%d]: %w", i, err)
		}
	}
	return nil
}

func validateEvent(e *TelemetryEvent) error {
	switch e.Type {
	case "error", "event", "span":
	default:
		return fmt.Errorf("type must be error, event, or span")
	}
	if e.Name == "" {
		return fmt.Errorf("name is required")
	}
	if len(e.Name) > maxEventNameLen {
		return fmt.Errorf("name exceeds %d characters", maxEventNameLen)
	}
	if len(e.Operation) > maxOperationLen {
		return fmt.Errorf("operation exceeds %d characters", maxOperationLen)
	}
	if len(e.Message) > maxMessageLen {
		return fmt.Errorf("message exceeds %d characters", maxMessageLen)
	}
	if e.DurationMs != nil {
		if *e.DurationMs < 0 || *e.DurationMs > maxDurationMs {
			return fmt.Errorf("duration_ms must be between 0 and %d", maxDurationMs)
		}
	}
	if len(e.Attributes) > maxAttrKeys {
		return fmt.Errorf("attributes exceeds maximum of %d keys", maxAttrKeys)
	}
	for k, v := range e.Attributes {
		if len(k) > maxAttrKeyLen {
			return fmt.Errorf("attribute key exceeds %d characters", maxAttrKeyLen)
		}
		if len(v) > maxAttrValueLen {
			return fmt.Errorf("attribute value exceeds %d characters", maxAttrValueLen)
		}
	}
	if e.Ts == "" {
		return fmt.Errorf("ts is required")
	}
	if _, err := time.Parse(time.RFC3339, e.Ts); err != nil {
		return fmt.Errorf("ts must be a valid RFC3339 timestamp")
	}
	return nil
}

func emitEMF(req *TelemetryRequest, e *TelemetryEvent) {
	ts, _ := time.Parse(time.RFC3339, e.Ts)
	tsMs := ts.UnixMilli()

	metrics := []map[string]string{
		{"Name": "EventCount", "Unit": "Count"},
	}
	if e.Type == "span" && e.DurationMs != nil {
		metrics = append(metrics, map[string]string{"Name": "DurationMs", "Unit": "Milliseconds"})
	}

	dimensions := [][]string{{"EventType"}, {"EventType", "Name"}}

	emf := map[string]any{
		"_aws": map[string]any{
			"Timestamp": tsMs,
			"CloudWatchMetrics": []map[string]any{
				{
					"Namespace":  "EPAC/Telemetry",
					"Dimensions": dimensions,
					"Metrics":    metrics,
				},
			},
		},
		"EventType":   e.Type,
		"Name":        e.Name,
		"EventCount":  1,
		"device_id":   req.DeviceID,
		"app_version": req.AppVersion,
		"os_version":  req.OSVersion,
		"message":     e.Message,
	}

	if e.Type == "span" && e.DurationMs != nil {
		emf["DurationMs"] = *e.DurationMs
	}

	if e.Operation != "" {
		emf["operation"] = e.Operation
	}

	if len(e.Attributes) > 0 {
		emf["attributes"] = e.Attributes
	}

	line, _ := json.Marshal(emf)
	fmt.Fprintln(emfWriter, string(line))
}

func headerValue(headers map[string]string, name string) string {
	for k, v := range headers {
		if strings.EqualFold(k, name) {
			return v
		}
	}
	return ""
}

func jsonResponse(status int, body any) events.APIGatewayV2HTTPResponse {
	data, _ := json.Marshal(body)
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(data),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGatewayV2("telemetry", handler))
}
