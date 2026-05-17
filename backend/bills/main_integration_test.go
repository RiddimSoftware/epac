//go:build integration

package main

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestIntegrationBillsReadsLocalArtifactFixture(t *testing.T) {
	dir := t.TempDir()
	writeBillFixture(t, dir, BillsResponse{Bills: []Bill{
		{ID: "C-12", Number: "C-12", Title: "Example Act", Status: "InProgress"},
	}})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/bills",
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body BillsResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Bills) != 1 || body.Bills[0].Number != "C-12" {
		t.Fatalf("body = %+v", body)
	}
}
