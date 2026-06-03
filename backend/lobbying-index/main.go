package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"epac/lobbying-index/internal/adapter/ocl"
	mycommons "epac/lobbying-index/internal/adapter/ourcommons"
	sqlite "epac/lobbying-index/internal/adapter/sqlite"
	subjects "epac/lobbying-index/internal/adapter/subjects"
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

	client := &http.Client{Timeout: 45 * time.Second}

	fetcher := ocl.NewFetcher(ocl.WithHTTPClient(client), ocl.WithUserAgent(defaultUserAgent))
	memberSource := mycommons.NewFetcher(mycommons.WithHTTPClient(client), mycommons.WithUserAgent(defaultUserAgent))
	subjectSource := subjects.NewFetcher(subjects.WithHTTPClient(client), subjects.WithUserAgent(defaultUserAgent))
	writer := sqlite.NewWriter()

	uc, err := usecase.NewIngestOCLData(
		fetcher,
		memberSource,
		subjectSource,
		writer,
		usecase.WithDatabasePath(dbPath),
	)
	if err != nil {
		return err
	}

	result, err := uc.Execute(ctx)
	if err != nil {
		return err
	}

	printResult(result)
	return nil
}

func printResult(result usecase.IngestOCLDataResult) {
	payload := map[string]any{
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
	}
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
