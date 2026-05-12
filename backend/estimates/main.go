package main

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

const (
	organizationsURL = "https://open.canada.ca/data/dataset/a35cf382-690c-4221-a971-cf0fd189a46f/resource/7c131a87-7784-4208-8e5c-043451240d95/download/ifoi_roif_en.csv"
	estimatesURL     = "https://open.canada.ca/data/dataset/a35cf382-690c-4221-a971-cf0fd189a46f/resource/f87c5f47-dd85-4c6f-b85e-2c59ccf8d84c/download/abv_apc_en.csv"
	pipelineName     = "main-estimates-ingest"
)

type Estimate struct {
	FiscalYear       string  `json:"fiscal_year"`
	OrganizationID   int     `json:"organization_id"`
	OrganizationName string  `json:"organization_name"`
	VoteNumber       int     `json:"vote_number"`
	VoteDescription  string  `json:"vote_description"`
	Authorities      float64 `json:"authorities"`
	Source           string  `json:"source"`
}

type EstimatesResponse struct {
	Estimates []Estimate `json:"estimates"`
}

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

	connStr := os.Getenv("DATABASE_URL")
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		return apiError(http.StatusServiceUnavailable, "database connection failed"), nil
	}
	defer conn.Close(ctx)

	orgIDStr := req.PathParameters["org_id"]
	fiscalYear := req.QueryStringParameters["fiscal_year"]

	var rows pgx.Rows
	if orgIDStr != "" {
		orgID, _ := strconv.Atoi(orgIDStr)
		if fiscalYear != "" {
			rows, err = conn.Query(ctx, `
				SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number, e.vote_description, e.authorities, e.source
				FROM estimates e
				JOIN organizations o ON e.organization_id = o.id
				WHERE e.organization_id = $1 AND e.fiscal_year = $2
				ORDER BY e.vote_number`, orgID, fiscalYear)
		} else {
			rows, err = conn.Query(ctx, `
				SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number, e.vote_description, e.authorities, e.source
				FROM estimates e
				JOIN organizations o ON e.organization_id = o.id
				WHERE e.organization_id = $1
				ORDER BY e.fiscal_year DESC, e.vote_number`, orgID)
		}
	} else if fiscalYear != "" {
		rows, err = conn.Query(ctx, `
			SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number, e.vote_description, e.authorities, e.source
			FROM estimates e
			JOIN organizations o ON e.organization_id = o.id
			WHERE e.fiscal_year = $1
			ORDER BY o.name, e.vote_number`, fiscalYear)
	} else {
		return apiError(http.StatusBadRequest, "missing org_id or fiscal_year"), nil
	}

	if err != nil {
		return apiError(http.StatusInternalServerError, "query failed"), nil
	}
	defer rows.Close()

	var estimates []Estimate
	for rows.Next() {
		var e Estimate
		if err := rows.Scan(&e.FiscalYear, &e.OrganizationID, &e.OrganizationName, &e.VoteNumber, &e.VoteDescription, &e.Authorities, &e.Source); err != nil {
			continue
		}
		estimates = append(estimates, e)
	}

	body, _ := json.Marshal(EstimatesResponse{Estimates: estimates})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func handleIngest(ctx context.Context) (string, error) {
	connStr := os.Getenv("DATABASE_URL")
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		return "", fmt.Errorf("database connection failed: %w", err)
	}
	defer conn.Close(ctx)

	// 1. Ingest Organizations
	fmt.Println("Downloading organizations...")
	orgsCSV, err := downloadCSV(organizationsURL)
	if err != nil {
		return "", fmt.Errorf("failed to download organizations: %w", err)
	}

	nameToID := make(map[string]int)
	for _, record := range parseOrganizations(orgsCSV) {
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

		_, err = conn.Exec(ctx, `
			INSERT INTO organizations (id, name, legal_title, abbr, dept_id, status)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (id) DO UPDATE SET
				name = EXCLUDED.name,
				legal_title = EXCLUDED.legal_title,
				abbr = EXCLUDED.abbr,
				dept_id = EXCLUDED.dept_id,
				status = EXCLUDED.status`,
			record.ID, record.Name, record.LegalTitle, record.Abbr, record.DeptID, record.Status)
		if err != nil {
			fmt.Printf("Warning: failed to insert organization %d: %v\n", record.ID, err)
		}
	}

	// 2. Ingest Estimates
	fmt.Println("Downloading estimates...")
	estsCSV, err := downloadCSV(estimatesURL)
	if err != nil {
		return "", fmt.Errorf("failed to download estimates: %w", err)
	}

	count := 0
	for _, est := range parseEstimates(estsCSV, nameToID) {
		_, err = conn.Exec(ctx, `
			INSERT INTO estimates (fiscal_year, organization_id, vote_number, vote_description, authorities, source)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (fiscal_year, organization_id, vote_number, vote_description) DO UPDATE SET
				authorities = EXCLUDED.authorities,
				source = EXCLUDED.source`,
			est.FiscalYear, est.OrganizationID, est.VoteNumber, est.VoteDescription, est.Authorities, est.Source)
		if err != nil {
			fmt.Printf("Warning: failed to insert estimate: %v\n", err)
		} else {
			count++
		}
	}

	recordHealth(ctx, conn, count, nil)
	return fmt.Sprintf("Processed %d Main Estimates records", count), nil
}

type OrgRecord struct {
	ID         int
	Name       string
	LegalTitle string
	Abbr       string
	DeptID     string
	Status     string
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
			FiscalYear:     fy,
			OrganizationID: orgID,
			VoteNumber:     voteNum,
			VoteDescription: voteDesc,
			Authorities:    authorities,
			Source:         "GC InfoBase",
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

func recordHealth(ctx context.Context, conn *pgx.Conn, count int, runErr error) {
	now := time.Now().UTC()
	var errMsg *string
	var successAt *time.Time
	var recordCount *int
	if runErr == nil {
		successAt = &now
		recordCount = &count
	} else {
		s := runErr.Error()
		errMsg = &s
	}
	_, _ = conn.Exec(ctx, `
		INSERT INTO pipeline_health (name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours)
		VALUES ($1, $2, $3, $4, $5, 24)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at     = EXCLUDED.last_run_at,
			last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
			last_error      = EXCLUDED.last_error,
			record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
	`, pipelineName, now, successAt, errMsg, recordCount)
}

func apiError(status int, message string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}
