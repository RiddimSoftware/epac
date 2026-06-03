package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"epac/lobbying-index/internal/adapter/legisinfo"
	"epac/lobbying-index/internal/adapter/ocl"
	mycommons "epac/lobbying-index/internal/adapter/ourcommons"
	sqlite "epac/lobbying-index/internal/adapter/sqlite"
	subjects "epac/lobbying-index/internal/adapter/subjects"
	"epac/lobbying-index/internal/domain"
	"epac/lobbying-index/internal/usecase"
)

const (
	defaultDBPath    = "/tmp/ocl-index.sqlite"
	defaultUserAgent = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

func main() {
	ctx := context.Background()
	if err := run(ctx); err != nil {
		logger := NewJSONLogger()
		logger.Error("pipeline failed", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = defaultDBPath
	}
	parliament := envInt("PARLIAMENT_NUM", 45)
	session := envInt("SESSION_NUM", 1)

	client := &http.Client{Timeout: 45 * time.Second}

	fetcher := ocl.NewFetcher(ocl.WithHTTPClient(client), ocl.WithUserAgent(defaultUserAgent))
	memberSource := mycommons.NewFetcher(mycommons.WithHTTPClient(client), mycommons.WithUserAgent(defaultUserAgent))
	subjectSource := subjects.NewFetcher(subjects.WithHTTPClient(client), subjects.WithUserAgent(defaultUserAgent))
	writer := sqlite.NewWriter()

	ingestUC, err := usecase.NewIngestOCLData(
		fetcher,
		memberSource,
		subjectSource,
		writer,
		usecase.WithDatabasePath(dbPath),
	)
	if err != nil {
		return err
	}

	ingestResult, err := ingestUC.Execute(ctx)
	if err != nil {
		return err
	}
	printResult(ingestResult)

	if err := aggregateMPLobbyingTables(dbPath); err != nil {
		return err
	}

	aggregator := sqlite.NewAggregator()
	orgUC, err := usecase.NewBuildOrganizationTables(aggregator, dbPath)
	if err != nil {
		return err
	}
	orgResult, err := orgUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("build organization tables: %w", err)
	}
	printOrgResult(orgResult)

	topicMap, err := loadTopicMap()
	if err != nil {
		fmt.Fprintf(os.Stderr, `{"pipeline":"lobbying-index","level":"warn","message":"topic map not loaded","error":"%v"}`+"\n", err)
	}

	legisFetcher := legisinfo.NewFetcher(legisinfo.WithHTTPClient(client), legisinfo.WithUserAgent(defaultUserAgent))
	billUC, err := usecase.NewBuildBillContextTables(legisFetcher, aggregator, topicMap, dbPath, parliament, session)
	if err != nil {
		return err
	}
	billResult, err := billUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("build bill context tables: %w", err)
	}
	printBillResult(billResult)

	return nil
}

func aggregateMPLobbyingTables(dbPath string) error {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return fmt.Errorf("open sqlite for MP lobbying aggregation: %w", err)
	}
	defer db.Close()

	if _, err := db.Exec("PRAGMA foreign_keys = ON"); err != nil {
		return fmt.Errorf("enable foreign keys for MP lobbying aggregation: %w", err)
	}

	aggregationRunner := sqlite.NewAggregationRunner()
	if err := usecase.BuildMPLobbyingTables(db, aggregationRunner); err != nil {
		return err
	}
	return nil
}

// loadTopicMap reads ocl_topic_map.json from the binary's directory or the working directory.
func loadTopicMap() ([]domain.TopicMapping, error) {
	candidates := []string{"ocl_topic_map.json"}
	if exe, err := os.Executable(); err == nil {
		candidates = append([]string{filepath.Join(filepath.Dir(exe), "ocl_topic_map.json")}, candidates...)
	}
	for _, path := range candidates {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		var mappings []domain.TopicMapping
		if err := json.Unmarshal(data, &mappings); err != nil {
			return nil, fmt.Errorf("parse topic map: %w", err)
		}
		return mappings, nil
	}
	return nil, fmt.Errorf("ocl_topic_map.json not found")
}

func printResult(result usecase.IngestOCLDataResult) {
	logJSON(map[string]any{
		"pipeline":                     "lobbying-index",
		"event":                        "ingest_ocl_data_completed",
		"database_path":                result.DatabasePath,
		"communication_primary_rows":   result.CommunicationPrimaryRows,
		"communication_dpoh_rows":      result.CommunicationDPOHRows,
		"communication_subject_rows":   result.CommunicationSubjectMatterRows,
		"registration_primary_rows":    result.RegistrationPrimaryRows,
		"registration_subject_rows":    result.RegistrationSubjectMatterRows,
		"registration_in_house_rows":   result.RegistrationInHouseRows,
		"registration_consultant_rows": result.RegistrationConsultantRows,
		"members_rows":                 result.MemberRows,
		"subject_matter_type_rows":     result.SubjectMatterTypeRows,
	})
}

func printOrgResult(result usecase.BuildOrganizationTablesResult) {
	logJSON(map[string]any{
		"pipeline":      "lobbying-index",
		"event":         "build_organization_tables_completed",
		"database_path": result.DatabasePath,
	})
}

func printBillResult(result usecase.BuildBillContextTablesResult) {
	logJSON(map[string]any{
		"pipeline":      "lobbying-index",
		"event":         "build_bill_context_tables_completed",
		"database_path": result.DatabasePath,
		"bill_count":    result.BillCount,
	})
}

func logJSON(payload map[string]any) {
	encoded, err := json.Marshal(payload)
	if err == nil {
		fmt.Println(string(encoded))
		return
	}
	fmt.Printf("{\"pipeline\":\"lobbying-index\",\"event\":\"marshaling_error\",\"error\":\"%v\"}\n", err)
}

func (l jsonLogger) Error(message string, err error) {
	payload := map[string]any{
		"pipeline": "lobbying-index",
		"level":    "error",
		"message":  message,
		"error":    err.Error(),
	}
	encoded, marshalErr := json.Marshal(payload)
	if marshalErr != nil {
		fmt.Printf(`{"pipeline":"lobbying-index","level":"error","message":"%v","error":"%v"}`+"\n", message, err)
		return
	}
	fmt.Println(string(encoded))
}

func NewJSONLogger() jsonLogger {
	return jsonLogger{}
}

type jsonLogger struct{}

func envInt(name string, fallback int) int {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		if parsed, err := strconv.Atoi(value); err == nil && parsed > 0 {
			return parsed
		}
	}
	return fallback
}
