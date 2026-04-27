// device-register Lambda — POST /api/v1/device/register
//
// Called by the iOS app when its APNs token changes or its topic
// subscription preferences change.
//
// Request body:
//
//	{
//	  "token":           "hex-encoded APNs device token",
//	  "topic_ids":       ["housing", "climate"],
//	  "granularity":     {"housing": "everyDebate", "climate": "onlyMyMP"},
//	  "my_mp_member_id": "278707"   // optional; Hansard Affiliation DbId
//	}
//
// Upserts a row in device_subscriptions. Safe to call on every launch.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

type RegisterRequest struct {
	Token        string            `json:"token"`
	TopicIds     []string          `json:"topic_ids"`
	Granularity  map[string]string `json:"granularity"`
	MyMPMemberId string            `json:"my_mp_member_id"`
}

var dbConn *pgx.Conn

func getConn(ctx context.Context) (*pgx.Conn, error) {
	if dbConn != nil {
		if err := dbConn.Ping(ctx); err == nil {
			return dbConn, nil
		}
		dbConn.Close(ctx)
		dbConn = nil
	}
	var err error
	dbConn, err = pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	return dbConn, err
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var r RegisterRequest
	if err := json.Unmarshal([]byte(req.Body), &r); err != nil {
		return errResp(http.StatusBadRequest, "invalid JSON"), nil
	}
	r.Token = strings.TrimSpace(r.Token)
	if r.Token == "" {
		return errResp(http.StatusBadRequest, "token is required"), nil
	}
	if r.TopicIds == nil {
		r.TopicIds = []string{}
	}
	if r.Granularity == nil {
		r.Granularity = map[string]string{}
	}

	conn, err := getConn(ctx)
	if err != nil {
		return errResp(http.StatusInternalServerError, fmt.Sprintf("db: %v", err)), nil
	}

	granJSON, err := json.Marshal(r.Granularity)
	if err != nil {
		return errResp(http.StatusInternalServerError, "marshal error"), nil
	}

	var myMP *string
	if r.MyMPMemberId != "" {
		myMP = &r.MyMPMemberId
	}

	_, err = conn.Exec(ctx, `
		INSERT INTO device_subscriptions (token, topic_ids, granularity, my_mp_member_id, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (token) DO UPDATE SET
			topic_ids       = EXCLUDED.topic_ids,
			granularity     = EXCLUDED.granularity,
			my_mp_member_id = EXCLUDED.my_mp_member_id,
			updated_at      = EXCLUDED.updated_at`,
		r.Token, r.TopicIds, granJSON, myMP, time.Now().UTC(),
	)
	if err != nil {
		return errResp(http.StatusInternalServerError, fmt.Sprintf("upsert: %v", err)), nil
	}

	body, _ := json.Marshal(map[string]string{"status": "ok"})
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func errResp(status int, msg string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGateway("device-register", HandleRequest))
}
