// bills Lambda — GET /api/v1/bills
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"epac/observability"
	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const billsArtifactKey = "bills/v1/all.json"

type BillStage struct {
	ID            string  `json:"id,omitempty"`
	Name          string  `json:"name,omitempty"`
	CompletedDate *string `json:"completed_date,omitempty"`
	IsCompleted   bool    `json:"is_completed"`
}

type Bill struct {
	ID           string      `json:"id"`
	Number       string      `json:"number"`
	Title        string      `json:"title"`
	SponsorName  string      `json:"sponsor_name,omitempty"`
	Status       string      `json:"status,omitempty"`
	CurrentStage string      `json:"current_stage,omitempty"`
	IntroducedOn *string     `json:"introduced_on,omitempty"`
	Stages       []BillStage `json:"stages,omitempty"`
	SourceURL    string      `json:"source_url,omitempty"`
	BillType     string      `json:"bill_type,omitempty"`
	Parliament   *int        `json:"parliament,omitempty"`
	Session      *int        `json:"session,omitempty"`
	LegisInfoURL string      `json:"legis_info_url,omitempty"`
}

type BillsResponse struct {
	Bills []Bill `json:"bills"`
}

var (
	newArtifactStore = artifacts.NewFromEnv
	normalizeRe      = regexp.MustCompile(`[^a-z0-9]+`)
)

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	resp, err := readBills(ctx)
	if err != nil {
		status := http.StatusInternalServerError
		if artifacts.IsNotFound(err) {
			status = http.StatusNotFound
		}
		return jsonError(status, err.Error()), nil
	}
	resp.Bills = filterBills(resp.Bills, req.QueryStringParameters["status"], req.QueryStringParameters["parliament"])
	body, err := json.Marshal(resp)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func readBills(ctx context.Context) (BillsResponse, error) {
	store, err := newArtifactStore(ctx)
	if err != nil {
		return BillsResponse{}, err
	}
	data, err := store.Get(ctx, billsArtifactKey)
	if err != nil {
		return BillsResponse{}, err
	}
	var resp BillsResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return BillsResponse{}, err
	}
	if resp.Bills == nil {
		resp.Bills = []Bill{}
	}
	return resp, nil
}

func filterBills(bills []Bill, statusFilter, parliamentFilter string) []Bill {
	status := normalizeFilter(statusFilter)
	parliament := 0
	if parsed, err := strconv.Atoi(strings.TrimSpace(parliamentFilter)); err == nil && parsed > 0 {
		parliament = parsed
	}
	if status == "" && parliament == 0 {
		return bills
	}
	filtered := make([]Bill, 0, len(bills))
	for _, bill := range bills {
		if status != "" && normalizeFilter(bill.Status) != status && normalizeFilter(bill.CurrentStage) != status {
			continue
		}
		if parliament != 0 && (bill.Parliament == nil || *bill.Parliament != parliament) {
			continue
		}
		filtered = append(filtered, bill)
	}
	return filtered
}

func normalizeFilter(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "inprogress", "in progress")
	value = strings.ReplaceAll(value, "royalassent", "royal assent")
	return normalizeRe.ReplaceAllString(value, "")
}

func jsonResponse(status int, body []byte) events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": "public, max-age=300",
		},
		Body: string(body),
	}
}

func jsonError(status int, message string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return jsonResponse(status, body)
}

func main() {
	lambda.Start(observability.WrapAPIGateway("bills", HandleRequest))
}
