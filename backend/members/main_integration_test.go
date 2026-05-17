//go:build integration

package main

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestIntegrationMembersReadsLocalArtifactFixture(t *testing.T) {
	dir := t.TempDir()
	writeMemberFixture(t, dir, MembersResponse{Members: []Member{
		{ID: "278707", Name: "Example MP", Province: "ON", Party: "Liberal"},
	}})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/members",
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body MembersResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Members) != 1 || body.Members[0].Name != "Example MP" {
		t.Fatalf("body = %+v", body)
	}
}
