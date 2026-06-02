package main

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	artifactadapter "epac/estimates/internal/adapter/artifacts"
	"epac/estimates/internal/usecase"
	"epac/observability"
	"epac/shared/artifacts"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const (
	organizationsURL = "https://open.canada.ca/data/dataset/a35cf382-690c-4221-a971-cf0fd189a46f/resource/7c131a87-7784-4208-8e5c-043451240d95/download/ifoi_roif_en.csv"
	estimatesURL     = "https://open.canada.ca/data/dataset/a35cf382-690c-4221-a971-cf0fd189a46f/resource/f87c5f47-dd85-4c6f-b85e-2c59ccf8d84c/download/abv_apc_en.csv"
)

type Estimate = usecase.Estimate
type EstimatesResponse = usecase.EstimatesResponse
type OrgRecord = usecase.OrgRecord

var newArtifactStore = artifacts.NewFromEnv

func main() {
	lambda.Start(handleLambda)
}

func handleLambda(ctx context.Context, raw json.RawMessage) (any, error) {
	var probe struct {
		Version        string `json:"version"`
		RequestContext struct {
			HTTP struct {
				Method string `json:"method"`
			} `json:"http"`
		} `json:"requestContext"`
	}
	_ = json.Unmarshal(raw, &probe)

	if probe.Version == "2.0" || probe.RequestContext.HTTP.Method != "" {
		var req events.APIGatewayV2HTTPRequest
		if err := json.Unmarshal(raw, &req); err != nil {
			return apiError(http.StatusBadRequest, "invalid request"), nil
		}
		return handleAPI(ctx, req)
	}

	return "main estimates ingest moved to backend/estimates/cmd/publisher", nil
}

func handleAPI(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if limitedResp, limited := observability.CheckAPIGatewayV2RateLimit(req); limited {
		return limitedResp, nil
	}

	store, err := newArtifactStore(ctx)
	if err != nil {
		return apiError(http.StatusServiceUnavailable, err.Error()), nil
	}
	repo := artifactadapter.NewEstimatesRepository(store)

	orgIDStr := req.PathParameters["org_id"]
	fiscalYear := req.QueryStringParameters["fiscal_year"]

	filter := usecase.EstimatesFilter{}
	if orgIDStr != "" {
		orgID, err := strconv.Atoi(orgIDStr)
		if err != nil || orgID <= 0 {
			return apiError(http.StatusBadRequest, "org_id must be a positive integer"), nil
		}
		filter.OrgID = &orgID
	}
	if fiscalYear != "" {
		filter.FiscalYear = &fiscalYear
	}

	estimates, err := usecase.NewGet(repo).Execute(ctx, filter)
	if err == usecase.ErrInvalidFilter {
		return apiError(http.StatusBadRequest, "missing org_id or fiscal_year"), nil
	}
	if err != nil {
		status := http.StatusInternalServerError
		if artifacts.IsNotFound(err) {
			status = http.StatusNotFound
		}
		return apiError(status, err.Error()), nil
	}

	body, _ := json.Marshal(EstimatesResponse{Estimates: estimates})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func parseOrganizations(records [][]string) []OrgRecord {
	var orgs []OrgRecord
	for i, record := range records {
		if i == 0 || len(record) < 20 {
			continue // skip header or short records
		}
		id, _ := strconv.Atoi(record[0])
		legalTitle := record[4]
		appliedTitle := record[5]
		abbr := record[3]
		deptID := record[1]
		status := record[19]

		name := appliedTitle
		if name == "" {
			name = legalTitle
		}

		orgs = append(orgs, OrgRecord{
			ID:         id,
			Name:       name,
			LegalTitle: legalTitle,
			Abbr:       abbr,
			DeptID:     deptID,
			Status:     status,
		})
	}
	return orgs
}

func parseEstimates(records [][]string, nameToID map[string]int) []Estimate {
	var estimates []Estimate
	for i, record := range records {
		if i == 0 || len(record) < 6 {
			continue // skip header or short records
		}
		fy := record[0]
		orgName := record[1]
		doc := record[2]
		voteNum, _ := strconv.Atoi(record[3])
		voteDesc := record[4]
		authorities, _ := strconv.ParseFloat(record[5], 64)

		if doc != "Main Estimates" {
			continue
		}

		orgID, ok := nameToID[orgName]
		if !ok {
			fmt.Printf("Warning: unknown organization name: %s\n", orgName)
			continue
		}

		estimates = append(estimates, Estimate{
			FiscalYear:      fy,
			OrganizationID:  orgID,
			VoteNumber:      voteNum,
			VoteDescription: voteDesc,
			Authorities:     authorities,
			Source:          "GC InfoBase",
		})
	}
	return estimates
}

func downloadCSV(url string) ([][]string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	reader := csv.NewReader(resp.Body)
	return reader.ReadAll()
}

func apiError(status int, message string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}
