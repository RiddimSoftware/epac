package main

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"epac/estimates/internal/adapter/postgres"
	"epac/estimates/internal/usecase"
	"epac/observability"

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

func main() {
	lambda.Start(handleLambda)
}

func handleLambda(ctx context.Context, raw json.RawMessage) (any, error) {
	_ = observability.Init(ctx)

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

	return handleIngest(ctx)
}

func handleAPI(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if limitedResp, limited := observability.CheckAPIGatewayV2RateLimit(req); limited {
		return limitedResp, nil
	}

	conn, err := postgres.Connect(ctx)
	if err != nil {
		return apiError(http.StatusServiceUnavailable, "database connection failed"), nil
	}
	defer conn.Close(ctx)

	orgIDStr := req.PathParameters["org_id"]
	fiscalYear := req.QueryStringParameters["fiscal_year"]

	filter := usecase.EstimatesFilter{}
	if orgIDStr != "" {
		orgID, _ := strconv.Atoi(orgIDStr)
		filter.OrgID = &orgID
	}
	if fiscalYear != "" {
		filter.FiscalYear = &fiscalYear
	}

	repo := postgres.NewEstimatesRepository(conn)
	estimates, err := usecase.NewGet(repo).Execute(ctx, filter)
	if err == usecase.ErrInvalidFilter {
		return apiError(http.StatusBadRequest, "missing org_id or fiscal_year"), nil
	}
	if err != nil {
		return apiError(http.StatusInternalServerError, "query failed"), nil
	}

	body, _ := json.Marshal(EstimatesResponse{Estimates: estimates})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func handleIngest(ctx context.Context) (string, error) {
	conn, err := postgres.Connect(ctx)
	if err != nil {
		return "", fmt.Errorf("database connection failed: %w", err)
	}
	defer conn.Close(ctx)
	repo := postgres.NewEstimatesRepository(conn)

	// 1. Ingest Organizations
	fmt.Println("Downloading organizations...")
	orgsCSV, err := downloadCSV(organizationsURL)
	if err != nil {
		return "", fmt.Errorf("failed to download organizations: %w", err)
	}

	nameToID := make(map[string]int)
	orgs := parseOrganizations(orgsCSV)
	for _, record := range orgs {
		nameToID[record.Name] = record.ID
		if record.LegalTitle != "" {
			nameToID[record.LegalTitle] = record.ID
		}
		if record.Abbr != "" {
			nameToID[record.Abbr] = record.ID
		}
		if record.DeptID != "" {
			nameToID[record.DeptID] = record.ID
		}
	}

	// 2. Ingest Estimates
	fmt.Println("Downloading estimates...")
	estsCSV, err := downloadCSV(estimatesURL)
	if err != nil {
		return "", fmt.Errorf("failed to download estimates: %w", err)
	}

	count, err := usecase.NewIngest(repo).Execute(ctx, usecase.IngestInput{
		Organizations: orgs,
		Estimates:     parseEstimates(estsCSV, nameToID),
	})
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Processed %d Main Estimates records", count), nil
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
