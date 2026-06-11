// bills Lambda — GET /api/v1/bills
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"

	"epac/observability"
	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	_ "modernc.org/sqlite"
)

const (
	billsSQLiteArtifactKey = "bills/v1/index.sqlite"
	billsJSONArtifactKey   = "bills/v1/all.json"
	sqliteReadOnlyDSN      = "file:%s?mode=ro&_pragma=query_only(1)"
)

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
	data, err := store.Get(ctx, billsSQLiteArtifactKey)
	if err != nil {
		if artifacts.IsNotFound(err) {
			return readBillsJSON(ctx, store)
		}
		return BillsResponse{}, err
	}
	return readBillsSQLite(ctx, data)
}

func readBillsJSON(ctx context.Context, store artifacts.Store) (BillsResponse, error) {
	data, err := store.Get(ctx, billsJSONArtifactKey)
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

func readBillsSQLite(ctx context.Context, data []byte) (BillsResponse, error) {
	db, cleanup, err := openSQLiteArtifact(data, "epac-bills-*.sqlite")
	if err != nil {
		return BillsResponse{}, err
	}
	defer cleanup()

	rows, err := db.QueryContext(ctx, `
		SELECT
			id,
			number,
			title,
			sponsor_name,
			status,
			current_stage,
			introduced_on,
			source_url,
			bill_type,
			parliament,
			session,
			legis_info_url
		FROM bills
		ORDER BY rowid`)
	if err != nil {
		return BillsResponse{}, fmt.Errorf("query bills sqlite artifact: %w", err)
	}
	defer rows.Close()

	bills := make([]Bill, 0)
	for rows.Next() {
		var bill Bill
		var introducedOn sql.NullString
		var parliament sql.NullInt64
		var session sql.NullInt64
		if err := rows.Scan(
			&bill.ID,
			&bill.Number,
			&bill.Title,
			&bill.SponsorName,
			&bill.Status,
			&bill.CurrentStage,
			&introducedOn,
			&bill.SourceURL,
			&bill.BillType,
			&parliament,
			&session,
			&bill.LegisInfoURL,
		); err != nil {
			return BillsResponse{}, fmt.Errorf("scan bills sqlite artifact: %w", err)
		}
		bill.IntroducedOn = stringPtr(introducedOn)
		bill.Parliament = intPtr(parliament)
		bill.Session = intPtr(session)
		bills = append(bills, bill)
	}
	if err := rows.Err(); err != nil {
		return BillsResponse{}, fmt.Errorf("iterate bills sqlite artifact: %w", err)
	}

	stages, err := readBillStagesSQLite(ctx, db)
	if err != nil {
		return BillsResponse{}, err
	}
	for i := range bills {
		bills[i].Stages = stages[bills[i].ID]
	}
	if bills == nil {
		bills = []Bill{}
	}
	return BillsResponse{Bills: bills}, nil
}

func readBillStagesSQLite(ctx context.Context, db *sql.DB) (map[string][]BillStage, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT bill_id, id, name, completed_date, is_completed
		FROM bill_stages
		ORDER BY bill_id, sort_order, rowid`)
	if err != nil {
		return nil, fmt.Errorf("query bill stages sqlite artifact: %w", err)
	}
	defer rows.Close()

	stages := make(map[string][]BillStage)
	for rows.Next() {
		var billID string
		var stage BillStage
		var completedDate sql.NullString
		var isCompleted int
		if err := rows.Scan(&billID, &stage.ID, &stage.Name, &completedDate, &isCompleted); err != nil {
			return nil, fmt.Errorf("scan bill stages sqlite artifact: %w", err)
		}
		stage.CompletedDate = stringPtr(completedDate)
		stage.IsCompleted = isCompleted != 0
		stages[billID] = append(stages[billID], stage)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill stages sqlite artifact: %w", err)
	}
	return stages, nil
}

func openSQLiteArtifact(data []byte, tempPattern string) (*sql.DB, func(), error) {
	file, err := os.CreateTemp("", tempPattern)
	if err != nil {
		return nil, nil, fmt.Errorf("create sqlite artifact temp file: %w", err)
	}
	path := file.Name()
	cleanupFile := func() {
		_ = os.Remove(path)
	}
	if _, err := file.Write(data); err != nil {
		file.Close()
		cleanupFile()
		return nil, nil, fmt.Errorf("write sqlite artifact temp file: %w", err)
	}
	if err := file.Close(); err != nil {
		cleanupFile()
		return nil, nil, fmt.Errorf("close sqlite artifact temp file: %w", err)
	}

	db, err := sql.Open("sqlite", fmt.Sprintf(sqliteReadOnlyDSN, path))
	if err != nil {
		cleanupFile()
		return nil, nil, fmt.Errorf("open sqlite artifact: %w", err)
	}
	cleanup := func() {
		_ = db.Close()
		cleanupFile()
	}
	if err := db.Ping(); err != nil {
		cleanup()
		return nil, nil, fmt.Errorf("ping sqlite artifact: %w", err)
	}
	return db, cleanup, nil
}

func stringPtr(value sql.NullString) *string {
	if !value.Valid {
		return nil
	}
	return &value.String
}

func intPtr(value sql.NullInt64) *int {
	if !value.Valid {
		return nil
	}
	converted := int(value.Int64)
	return &converted
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
