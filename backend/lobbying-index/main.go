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

	cabinet "epac/lobbying-index/internal/adapter/cabinet"
	"epac/lobbying-index/internal/adapter/legisinfo"
	"epac/lobbying-index/internal/adapter/ocl"
	mycommons "epac/lobbying-index/internal/adapter/ourcommons"
	s3adapter "epac/lobbying-index/internal/adapter/s3"
	sqlite "epac/lobbying-index/internal/adapter/sqlite"
	subjects "epac/lobbying-index/internal/adapter/subjects"
	"epac/lobbying-index/internal/domain"
	"epac/lobbying-index/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	defaultDBPath    = "/tmp/lobbying-index.sqlite"
	defaultUserAgent = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

func HandleRequest(ctx context.Context) error {
	pipelineStart := time.Now()

	dbPath := strings.TrimSpace(os.Getenv("DB_PATH"))
	if dbPath == "" {
		dbPath = defaultDBPath
	}

	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}

	prefix := strings.TrimSpace(os.Getenv("LOBBYING_INDEX_PREFIX"))

	parliament := envInt("PARLIAMENT_NUM", 45)
	session := envInt("SESSION_NUM", 1)

	if err := build(ctx, dbPath, parliament, session); err != nil {
		return err
	}

	t := time.Now()
	logPhase("s3_upload", "start", 0)
	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}
	store := s3adapter.NewStore(awss3.NewFromConfig(awsCfg), bucket, prefix)

	s3Key := store.Prefix() + "/index.sqlite"
	hash, sizeBytes, err := store.Upload(ctx, dbPath, s3Key)
	if err != nil {
		return fmt.Errorf("upload sqlite artifact: %w", err)
	}
	logPhase("s3_upload", "completed", time.Since(t).Milliseconds())

	tableCounts, err := countTables(dbPath)
	if err != nil {
		logJSON(map[string]any{
			"pipeline": "lobbying-index",
			"level":    "warn",
			"event":    "table_count_failed",
			"error":    err.Error(),
		})
	}

	manifest := domain.Manifest{
		Version:         domain.ManifestVersion,
		BuiltAt:         time.Now().UTC().Format(time.RFC3339),
		SQLiteKey:       s3Key,
		SQLiteSizeBytes: sizeBytes,
		SQLiteSHA256:    hash,
		TableCounts:     tableCounts,
	}

	if err := store.Write(ctx, manifest); err != nil {
		return fmt.Errorf("write manifest: %w", err)
	}

	logJSON(map[string]any{
		"pipeline":            "lobbying-index",
		"event":               "artifact_uploaded",
		"sqlite_key":          manifest.SQLiteKey,
		"sqlite_size_bytes":   manifest.SQLiteSizeBytes,
		"sqlite_sha256":       manifest.SQLiteSHA256,
		"table_counts":        manifest.TableCounts,
		"pipeline_elapsed_ms": time.Since(pipelineStart).Milliseconds(),
	})

	return nil
}

func build(ctx context.Context, dbPath string, parliament, session int) error {
	client := &http.Client{Timeout: 45 * time.Second}

	fetcher := ocl.NewFetcher(ocl.WithHTTPClient(client), ocl.WithUserAgent(defaultUserAgent))
	memberSource := mycommons.NewFetcher(mycommons.WithHTTPClient(client), mycommons.WithUserAgent(defaultUserAgent))
	subjectSource := subjects.NewFetcher(subjects.WithHTTPClient(client), subjects.WithUserAgent(defaultUserAgent))
	cabinetSource := cabinet.NewFetcher(cabinet.WithHTTPClient(client), cabinet.WithUserAgent(defaultUserAgent))
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

	t := time.Now()
	logPhase("ingest_ocl_data", "start", 0)
	ingestResult, err := ingestUC.Execute(ctx)
	if err != nil {
		return err
	}
	logIngestResult(ingestResult)
	logPhase("ingest_ocl_data", "completed", time.Since(t).Milliseconds())

	t = time.Now()
	logPhase("aggregate_mp_lobbying", "start", 0)
	if err := aggregateMPLobbyingTables(dbPath, parliament); err != nil {
		return err
	}
	logPhase("aggregate_mp_lobbying", "completed", time.Since(t).Milliseconds())

	aggregator := sqlite.NewAggregator()
	orgUC, err := usecase.NewBuildOrganizationTables(aggregator, dbPath)
	if err != nil {
		return err
	}

	t = time.Now()
	logPhase("build_organization_tables", "start", 0)
	orgResult, err := orgUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("build organization tables: %w", err)
	}
	logOrgResult(orgResult)
	logPhase("build_organization_tables", "completed", time.Since(t).Milliseconds())

	topicMap, err := loadTopicMap()
	if err != nil {
		logJSON(map[string]any{
			"pipeline": "lobbying-index",
			"level":    "warn",
			"event":    "topic_map_not_loaded",
			"error":    err.Error(),
		})
	}

	legisFetcher := legisinfo.NewFetcher(legisinfo.WithHTTPClient(client), legisinfo.WithUserAgent(defaultUserAgent))
	billUC, err := usecase.NewBuildBillContextTables(legisFetcher, aggregator, topicMap, dbPath, parliament, session)
	if err != nil {
		return err
	}

	t = time.Now()
	logPhase("build_bill_context_tables", "start", 0)
	billResult, err := billUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("build bill context tables: %w", err)
	}
	logBillResult(billResult)
	logPhase("build_bill_context_tables", "completed", time.Since(t).Milliseconds())

	ministerUC, err := usecase.NewPreBakeMinisterCommunications(cabinetSource, aggregator, dbPath, parliament)
	if err != nil {
		return err
	}

	t = time.Now()
	logPhase("prebake_minister_communications", "start", 0)
	ministerResult, err := ministerUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("pre-bake minister communications: %w", err)
	}
	logMinisterResult(ministerResult)
	logMinisterWarnings(ministerResult)
	logPhase("prebake_minister_communications", "completed", time.Since(t).Milliseconds())

	return nil
}

func aggregateMPLobbyingTables(dbPath string, parliament int) error {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return fmt.Errorf("open sqlite for MP lobbying aggregation: %w", err)
	}
	defer db.Close()

	if _, err := db.Exec("PRAGMA foreign_keys = ON"); err != nil {
		return fmt.Errorf("enable foreign keys for MP lobbying aggregation: %w", err)
	}

	aggregationRunner := sqlite.NewAggregationRunner(sqlite.WithParliament(parliament))
	if err := usecase.BuildMPLobbyingTables(db, aggregationRunner); err != nil {
		return err
	}
	return nil
}

func countTables(dbPath string) (map[string]int, error) {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("open sqlite for table counts: %w", err)
	}
	defer db.Close()

	// Names come from sqlite_master (not user input), so dynamic SQL is safe here.
	rows, err := db.Query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
	if err != nil {
		return nil, fmt.Errorf("list tables: %w", err)
	}
	defer rows.Close()

	var tableNames []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, fmt.Errorf("scan table name: %w", err)
		}
		tableNames = append(tableNames, name)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate tables: %w", err)
	}

	counts := make(map[string]int, len(tableNames))
	for _, name := range tableNames {
		var count int
		if err := db.QueryRow("SELECT COUNT(*) FROM " + name).Scan(&count); err != nil { //nolint:gosec
			counts[name] = -1
			continue
		}
		counts[name] = count
	}
	return counts, nil
}

func loadTopicMap() ([]domain.TopicMapping, error) {
	candidates := []string{"ocl_topic_map.json"}
	if exe, err := os.Executable(); err == nil {
		candidates = append([]string{filepath.Join(filepath.Dir(exe), "ocl_topic_map.json")}, candidates...)
	}
	for _, p := range candidates {
		data, err := os.ReadFile(p)
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

func logIngestResult(result usecase.IngestOCLDataResult) {
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

func logOrgResult(result usecase.BuildOrganizationTablesResult) {
	logJSON(map[string]any{
		"pipeline":      "lobbying-index",
		"event":         "build_organization_tables_completed",
		"database_path": result.DatabasePath,
	})
}

func logBillResult(result usecase.BuildBillContextTablesResult) {
	logJSON(map[string]any{
		"pipeline":      "lobbying-index",
		"event":         "build_bill_context_tables_completed",
		"database_path": result.DatabasePath,
		"bill_count":    result.BillCount,
	})
}

func logMinisterResult(result usecase.PreBakeMinisterCommunicationsResult) {
	logJSON(map[string]any{
		"pipeline":                         "lobbying-index",
		"event":                            "prebake_minister_communications_completed",
		"database_path":                    result.DatabasePath,
		"ministers_processed":              result.MinistersProcessed,
		"portfolio_rows":                   result.PortfolioRows,
		"mandate_rows":                     result.MandateRows,
		"communication_rows":               result.CommunicationRows,
		"member_resolution_miss_count":     result.MemberResolutionMissCount,
		"ministers_without_communications": result.MinistersWithoutCommunications,
	})
}

func logMinisterWarnings(result usecase.PreBakeMinisterCommunicationsResult) {
	for _, name := range result.UnresolvedMinisters {
		logJSON(map[string]any{
			"pipeline":      "lobbying-index",
			"level":         "warn",
			"event":         "minister_member_resolution_missing",
			"minister_name": name,
			"message":       "could not resolve member_id from members table; wrote portfolio rows with member_id=''",
		})
	}
}

func logPhase(phase, status string, elapsedMs int64) {
	entry := map[string]any{
		"pipeline": "lobbying-index",
		"event":    "phase_" + status,
		"phase":    phase,
	}
	if status == "completed" {
		entry["elapsed_ms"] = elapsedMs
	}
	logJSON(entry)
}

func logJSON(payload map[string]any) {
	encoded, err := json.Marshal(payload)
	if err == nil {
		fmt.Println(string(encoded))
		return
	}
	fmt.Printf("{\"pipeline\":\"lobbying-index\",\"event\":\"marshaling_error\",\"error\":\"%v\"}\n", err)
}

func envInt(name string, fallback int) int {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		if parsed, err := strconv.Atoi(value); err == nil && parsed > 0 {
			return parsed
		}
	}
	return fallback
}

func main() {
	lambda.Start(observability.WrapNoEvent("lobbying-index", HandleRequest))
}
