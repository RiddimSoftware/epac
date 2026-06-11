package main

import (
	"context"
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

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	defaultDBPath    = "/tmp/lobbying-index.sqlite"
	defaultUserAgent = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"

)

type runtimeConfig struct {
	dbPath     string
	parliament int
	session    int
	store      *s3adapter.Store
}

func loadRuntimeConfig(ctx context.Context) (*runtimeConfig, error) {
	dbPath := strings.TrimSpace(os.Getenv("DB_PATH"))
	if dbPath == "" {
		dbPath = defaultDBPath
	}

	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return nil, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	prefix := strings.TrimSpace(os.Getenv("LOBBYING_INDEX_PREFIX"))

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	store := s3adapter.NewStore(awss3.NewFromConfig(awsCfg), bucket, prefix)

	return &runtimeConfig{
		dbPath:     dbPath,
		parliament: envInt("PARLIAMENT_NUM", 45),
		session:    envInt("SESSION_NUM", 1),
		store:      store,
	}, nil
}

// runAll bypasses the intermediate-transfer round trips and publishes the same
// final artifact + manifest.
func runAll(ctx context.Context, cfg *runtimeConfig) error {
	if err := ingestOCLData(ctx, cfg); err != nil {
		return err
	}
	if err := buildMPLobbyingTables(ctx, cfg); err != nil {
		return err
	}
	if err := buildOrganizationTables(ctx, cfg); err != nil {
		return err
	}
	if err := buildBillContextTables(ctx, cfg); err != nil {
		return err
	}
	if err := preBakeMinisterCommunications(ctx, cfg); err != nil {
		return err
	}
	return finalizeArtifact(ctx, cfg)
}

func ingestOCLData(ctx context.Context, cfg *runtimeConfig) error {
	client := newHTTPClient()
	fetcher := ocl.NewFetcher(ocl.WithHTTPClient(client), ocl.WithUserAgent(defaultUserAgent))
	memberSource := mycommons.NewFetcher(mycommons.WithHTTPClient(client), mycommons.WithUserAgent(defaultUserAgent))
	subjectSource := subjects.NewFetcher(subjects.WithHTTPClient(client), subjects.WithUserAgent(defaultUserAgent))
	writer := sqlite.NewWriter()

	ingestUC, err := usecase.NewIngestOCLData(
		fetcher,
		memberSource,
		subjectSource,
		writer,
		usecase.WithDatabasePath(cfg.dbPath),
	)
	if err != nil {
		return err
	}
	t := time.Now()
	logPhase("ingest_ocl_data", "start", 0)
	result, err := ingestUC.Execute(ctx)
	if err != nil {
		return err
	}
	logIngestResult(result)
	if err := sqlite.EnsureOCLIndexes(ctx, cfg.dbPath); err != nil {
		return err
	}
	logPhase("ingest_ocl_data", "completed", time.Since(t).Milliseconds())
	return nil
}

func buildOrganizationTables(ctx context.Context, cfg *runtimeConfig) error {
	aggregator := sqlite.NewAggregator()
	orgUC, err := usecase.NewBuildOrganizationTables(aggregator, cfg.dbPath)
	if err != nil {
		return err
	}
	t := time.Now()
	logPhase("build_organization_tables", "start", 0)
	result, err := orgUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("build organization tables: %w", err)
	}
	logOrgResult(result)
	logPhase("build_organization_tables", "completed", time.Since(t).Milliseconds())
	return nil
}

func buildBillContextTables(ctx context.Context, cfg *runtimeConfig) error {
	client := newHTTPClient()
	aggregator := sqlite.NewAggregator()
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
	billUC, err := usecase.NewBuildBillContextTables(legisFetcher, aggregator, topicMap, cfg.dbPath, cfg.parliament, cfg.session)
	if err != nil {
		return err
	}
	t := time.Now()
	logPhase("build_bill_context_tables", "start", 0)
	result, err := billUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("build bill context tables: %w", err)
	}
	logBillResult(result)
	logPhase("build_bill_context_tables", "completed", time.Since(t).Milliseconds())
	return nil
}

func preBakeMinisterCommunications(ctx context.Context, cfg *runtimeConfig) error {
	client := newHTTPClient()
	aggregator := sqlite.NewAggregator()
	cabinetSource := cabinet.NewFetcher(cabinet.WithHTTPClient(client), cabinet.WithUserAgent(defaultUserAgent))
	ministerUC, err := usecase.NewPreBakeMinisterCommunications(cabinetSource, aggregator, cfg.dbPath, cfg.parliament)
	if err != nil {
		return err
	}
	t := time.Now()
	logPhase("prebake_minister_communications", "start", 0)
	result, err := ministerUC.Execute(ctx)
	if err != nil {
		return fmt.Errorf("pre-bake minister communications: %w", err)
	}
	logMinisterResult(result)
	logMinisterWarnings(result)
	logPhase("prebake_minister_communications", "completed", time.Since(t).Milliseconds())
	return nil
}

func finalizeArtifact(ctx context.Context, cfg *runtimeConfig) error {
	t := time.Now()
	logPhase("s3_upload", "start", 0)
	s3Key := cfg.store.Prefix() + "/index.sqlite"
	hash, sizeBytes, err := cfg.store.Upload(ctx, cfg.dbPath, s3Key)
	if err != nil {
		return fmt.Errorf("upload sqlite artifact: %w", err)
	}
	logPhase("s3_upload", "completed", time.Since(t).Milliseconds())

	tableCounts, err := sqlite.CountTables(ctx, cfg.dbPath)
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

	if err := cfg.store.Write(ctx, manifest); err != nil {
		return fmt.Errorf("write manifest: %w", err)
	}

	logJSON(map[string]any{
		"pipeline":          "lobbying-index",
		"event":             "artifact_uploaded",
		"sqlite_key":        manifest.SQLiteKey,
		"sqlite_size_bytes": manifest.SQLiteSizeBytes,
		"sqlite_sha256":     manifest.SQLiteSHA256,
		"table_counts":      manifest.TableCounts,
	})
	return nil
}

func newHTTPClient() *http.Client {
	return &http.Client{Timeout: 45 * time.Second}
}

func buildMPLobbyingTables(ctx context.Context, cfg *runtimeConfig) error {
	aggregationRunner := sqlite.NewAggregationRunner(sqlite.WithParliament(cfg.parliament))
	mpUC, err := usecase.NewBuildMPLobbyingTables(aggregationRunner, cfg.dbPath)
	if err != nil {
		return err
	}
	t := time.Now()
	logPhase("aggregate_mp_lobbying", "start", 0)
	if _, err := mpUC.Execute(ctx); err != nil {
		return fmt.Errorf("build MP lobbying tables: %w", err)
	}
	logPhase("aggregate_mp_lobbying", "completed", time.Since(t).Milliseconds())
	return nil
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
	ctx := context.Background()
	cfg, err := loadRuntimeConfig(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	if err := runAll(ctx, cfg); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
