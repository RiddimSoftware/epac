package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func makeRequest(method, contentType, body string) events.APIGatewayV2HTTPRequest {
	headers := map[string]string{}
	if contentType != "" {
		headers["Content-Type"] = contentType
	}
	return events.APIGatewayV2HTTPRequest{
		Headers: headers,
		Body:    body,
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: method,
			},
		},
	}
}

func validPayload(t *testing.T) string {
	t.Helper()
	body := TelemetryRequest{
		DeviceID:   "device-123",
		AppVersion: "1.0.0",
		OSVersion:  "18.0",
		Events: []TelemetryEvent{
			{Type: "event", Name: "app_launch", Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(body)
	return string(data)
}

func captureEMF(t *testing.T, fn func()) string {
	t.Helper()
	var buf bytes.Buffer
	old := emfWriter
	emfWriter = &buf
	t.Cleanup(func() { emfWriter = old })
	fn()
	return buf.String()
}

func TestValidEventBatch(t *testing.T) {
	dur := 150
	payload := TelemetryRequest{
		DeviceID:   "device-abc",
		AppVersion: "2.1.0",
		OSVersion:  "18.1",
		Events: []TelemetryEvent{
			{Type: "event", Name: "app_launch", Ts: "2026-05-26T10:00:00Z"},
			{Type: "error", Name: "network_failure", Message: "timeout", Ts: "2026-05-26T10:01:00Z"},
			{Type: "span", Name: "api_call", Operation: "GET /sittings", DurationMs: &dur, Ts: "2026-05-26T10:02:00Z"},
		},
	}
	data, _ := json.Marshal(payload)

	output := captureEMF(t, func() {
		resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if resp.StatusCode != http.StatusNoContent {
			t.Errorf("expected 204, got %d: %s", resp.StatusCode, resp.Body)
		}
	})

	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 EMF lines, got %d", len(lines))
	}

	for i, line := range lines {
		var emf map[string]any
		if err := json.Unmarshal([]byte(line), &emf); err != nil {
			t.Fatalf("line %d: invalid JSON: %v", i, err)
		}
		awsBlock, ok := emf["_aws"].(map[string]any)
		if !ok {
			t.Fatalf("line %d: missing _aws block", i)
		}
		if _, ok := awsBlock["Timestamp"]; !ok {
			t.Fatalf("line %d: missing Timestamp in _aws", i)
		}
		cwMetrics, ok := awsBlock["CloudWatchMetrics"].([]any)
		if !ok || len(cwMetrics) == 0 {
			t.Fatalf("line %d: missing CloudWatchMetrics", i)
		}
		if emf["EventCount"] != float64(1) {
			t.Errorf("line %d: expected EventCount=1, got %v", i, emf["EventCount"])
		}
		if emf["device_id"] != "device-abc" {
			t.Errorf("line %d: expected device_id=device-abc, got %v", i, emf["device_id"])
		}
	}

	var spanLine map[string]any
	json.Unmarshal([]byte(lines[2]), &spanLine)
	if spanLine["DurationMs"] != float64(150) {
		t.Errorf("span line: expected DurationMs=150, got %v", spanLine["DurationMs"])
	}
	if spanLine["operation"] != "GET /sittings" {
		t.Errorf("span line: expected operation='GET /sittings', got %v", spanLine["operation"])
	}

	var eventLine map[string]any
	json.Unmarshal([]byte(lines[0]), &eventLine)
	if _, hasDuration := eventLine["DurationMs"]; hasDuration {
		t.Error("event line should not have DurationMs")
	}
}

func TestValidEventWithAttributes(t *testing.T) {
	payload := TelemetryRequest{
		DeviceID: "device-attr",
		Events: []TelemetryEvent{
			{
				Type: "event",
				Name: "screen_view",
				Attributes: map[string]string{
					"screen": "home",
					"tab":    "trending",
				},
				Ts: "2026-05-26T12:00:00Z",
			},
		},
	}
	data, _ := json.Marshal(payload)

	output := captureEMF(t, func() {
		resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if resp.StatusCode != http.StatusNoContent {
			t.Errorf("expected 204, got %d", resp.StatusCode)
		}
	})

	var emf map[string]any
	json.Unmarshal([]byte(strings.TrimSpace(output)), &emf)
	attrs, ok := emf["attributes"].(map[string]any)
	if !ok {
		t.Fatal("expected attributes in EMF output")
	}
	if attrs["screen"] != "home" {
		t.Errorf("expected screen=home, got %v", attrs["screen"])
	}
}

func TestPayloadEventIncludesBody(t *testing.T) {
	body := `{"metric":true}`
	payload := TelemetryRequest{
		DeviceID: "device-payload",
		Events: []TelemetryEvent{
			{Type: "payload", Name: "metrickit.metric", Body: body, Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)

	output := captureEMF(t, func() {
		resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if resp.StatusCode != http.StatusNoContent {
			t.Errorf("expected 204, got %d: %s", resp.StatusCode, resp.Body)
		}
	})

	var emf map[string]any
	json.Unmarshal([]byte(strings.TrimSpace(output)), &emf)
	if emf["EventType"] != "payload" {
		t.Errorf("expected EventType=payload, got %v", emf["EventType"])
	}
	if emf["body"] != body {
		t.Errorf("expected payload body to be emitted, got %v", emf["body"])
	}
}

func TestPayloadBodyMaxLength(t *testing.T) {
	payload := TelemetryRequest{
		DeviceID: "d1",
		Events: []TelemetryEvent{
			{Type: "payload", Name: "too_large", Body: strings.Repeat("x", maxBodyLen+1), Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
	if !strings.Contains(resp.Body, "body exceeds") {
		t.Errorf("expected body size error, got: %s", resp.Body)
	}
}

func TestMissingDeviceID(t *testing.T) {
	payload := `{"events":[{"type":"event","name":"test","ts":"2026-05-26T12:00:00Z"}]}`
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", payload))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
	if !strings.Contains(resp.Body, "device_id") {
		t.Errorf("expected error about device_id, got: %s", resp.Body)
	}
}

func TestMissingEvents(t *testing.T) {
	payload := `{"device_id":"d1"}`
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", payload))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
	if !strings.Contains(resp.Body, "events") {
		t.Errorf("expected error about events, got: %s", resp.Body)
	}
}

func TestEmptyEvents(t *testing.T) {
	payload := `{"device_id":"d1","events":[]}`
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", payload))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestOversizeBatch(t *testing.T) {
	evts := make([]TelemetryEvent, 101)
	for i := range evts {
		evts[i] = TelemetryEvent{Type: "event", Name: "e", Ts: "2026-05-26T12:00:00Z"}
	}
	body := TelemetryRequest{DeviceID: "d1", Events: evts}
	data, _ := json.Marshal(body)
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
	if !strings.Contains(resp.Body, "batch size") {
		t.Errorf("expected batch size error, got: %s", resp.Body)
	}
}

func TestOversizeAttributes(t *testing.T) {
	attrs := map[string]string{}
	for i := 0; i < 17; i++ {
		attrs[strings.Repeat("k", 5)] = "v"
		if i < 16 {
			attrs = map[string]string{}
		}
	}
	attrs = map[string]string{}
	for i := 0; i < 17; i++ {
		key := string(rune('a'+i)) + strings.Repeat("x", 4)
		attrs[key] = "v"
	}
	payload := TelemetryRequest{
		DeviceID: "d1",
		Events: []TelemetryEvent{
			{Type: "event", Name: "e", Ts: "2026-05-26T12:00:00Z", Attributes: attrs},
		},
	}
	data, _ := json.Marshal(payload)
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestUnknownType(t *testing.T) {
	payload := `{"device_id":"d1","events":[{"type":"unknown","name":"e","ts":"2026-05-26T12:00:00Z"}]}`
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", payload))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
	if !strings.Contains(resp.Body, "type") {
		t.Errorf("expected error about type, got: %s", resp.Body)
	}
}

func TestInvalidTimestamp(t *testing.T) {
	payload := `{"device_id":"d1","events":[{"type":"event","name":"e","ts":"not-a-date"}]}`
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", payload))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestWrongMethod(t *testing.T) {
	for _, method := range []string{http.MethodGet, http.MethodPut, http.MethodDelete} {
		resp, err := handler(context.Background(), makeRequest(method, "application/json", ""))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if resp.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("%s: expected 405, got %d", method, resp.StatusCode)
		}
	}
}

func TestWrongContentType(t *testing.T) {
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "text/plain", ""))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusUnsupportedMediaType {
		t.Errorf("expected 415, got %d", resp.StatusCode)
	}
}

func TestMissingContentType(t *testing.T) {
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "", ""))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusUnsupportedMediaType {
		t.Errorf("expected 415, got %d", resp.StatusCode)
	}
}

func TestInvalidJSON(t *testing.T) {
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", "not json"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestEMFNamespace(t *testing.T) {
	payload := TelemetryRequest{
		DeviceID: "d1",
		Events: []TelemetryEvent{
			{Type: "event", Name: "test_event", Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)

	output := captureEMF(t, func() {
		handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	})

	var emf map[string]any
	json.Unmarshal([]byte(strings.TrimSpace(output)), &emf)
	awsBlock := emf["_aws"].(map[string]any)
	cwMetrics := awsBlock["CloudWatchMetrics"].([]any)
	metricDef := cwMetrics[0].(map[string]any)
	if metricDef["Namespace"] != "EPAC/Telemetry" {
		t.Errorf("expected namespace EPAC/Telemetry, got %v", metricDef["Namespace"])
	}
}

func TestSpanDurationMetric(t *testing.T) {
	dur := 0
	payload := TelemetryRequest{
		DeviceID: "d1",
		Events: []TelemetryEvent{
			{Type: "span", Name: "fast_op", DurationMs: &dur, Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)

	output := captureEMF(t, func() {
		handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	})

	var emf map[string]any
	json.Unmarshal([]byte(strings.TrimSpace(output)), &emf)
	awsBlock := emf["_aws"].(map[string]any)
	cwMetrics := awsBlock["CloudWatchMetrics"].([]any)
	metricDef := cwMetrics[0].(map[string]any)
	metricsList := metricDef["Metrics"].([]any)
	if len(metricsList) != 2 {
		t.Errorf("span should have 2 metrics (EventCount + DurationMs), got %d", len(metricsList))
	}
	if emf["DurationMs"] != float64(0) {
		t.Errorf("expected DurationMs=0, got %v", emf["DurationMs"])
	}
}

func TestDeviceIDMaxLength(t *testing.T) {
	payload := TelemetryRequest{
		DeviceID: strings.Repeat("x", 65),
		Events: []TelemetryEvent{
			{Type: "event", Name: "e", Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestEventNameMaxLength(t *testing.T) {
	payload := TelemetryRequest{
		DeviceID: "d1",
		Events: []TelemetryEvent{
			{Type: "event", Name: strings.Repeat("x", 129), Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestContentTypeWithCharset(t *testing.T) {
	payload := validPayload(t)

	output := captureEMF(t, func() {
		resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json; charset=utf-8", payload))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if resp.StatusCode != http.StatusNoContent {
			t.Errorf("expected 204, got %d: %s", resp.StatusCode, resp.Body)
		}
	})

	if strings.TrimSpace(output) == "" {
		t.Error("expected EMF output for valid request with charset")
	}
}

func TestDurationMsOutOfRange(t *testing.T) {
	dur := 600_001
	payload := TelemetryRequest{
		DeviceID: "d1",
		Events: []TelemetryEvent{
			{Type: "span", Name: "slow", DurationMs: &dur, Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestNegativeDurationMs(t *testing.T) {
	dur := -1
	payload := TelemetryRequest{
		DeviceID: "d1",
		Events: []TelemetryEvent{
			{Type: "span", Name: "neg", DurationMs: &dur, Ts: "2026-05-26T12:00:00Z"},
		},
	}
	data, _ := json.Marshal(payload)
	resp, err := handler(context.Background(), makeRequest(http.MethodPost, "application/json", string(data)))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}
