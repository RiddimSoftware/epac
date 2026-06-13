package main

import (
	"context"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequestRejectsMalformedPayloadBeforeBuild(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{Body: `{"division_id":`})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != 400 {
		t.Fatalf("StatusCode = %d, want 400", resp.StatusCode)
	}
	if resp.Body != `{"error": "bad request"}` {
		t.Fatalf("Body = %q, want bad request response", resp.Body)
	}
}

func TestHandleRequestRejectsIncompletePayloadBeforeBuild(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{Body: `{"division_id":42}`})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != 400 {
		t.Fatalf("StatusCode = %d, want 400", resp.StatusCode)
	}
	if resp.Body != `{"error": "bad request"}` {
		t.Fatalf("Body = %q, want bad request response", resp.Body)
	}
}
