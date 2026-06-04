package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
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

	// Phase identifiers accepted in the Lambda event payload.
	phaseIngestOCLData                = "IngestOCLData"
	phaseBuildMPLobbying              = "BuildMPLobbying"
	phaseBuildOrganizationTables      = "BuildOrganizationTables"
	phaseBuildBillContextTables       = "BuildBillContextTables"
	phasePreBakeMinisterCommunications = "PreBakeMinisterCommunications"
	phaseFinalize                     = "Finalize"
	phaseAll                          = "All"
)

// Event is the Lambda invocation payload. Step Functions and direct invokers
// pass a phase identifier; All preserves the legacy whole-pipeline behavior.
type Event struct {
	Phase string `json:"phase"`
}

// phaseOrder is the linear pipeline order. Each phase reads the previous
// phase's intermediate artifact and writes its own under <prefix>/tmp/.
var phaseOrder = []string{
	phaseIngestOCLData,
	phaseBuildMPLobbying,
	phaseBuildOrganizationTables,
	phaseBuildBillContextTables,
	phasePreBakeMinisterCommunications,
	phaseFinalize,
}

// previousPhase returns the phase whose intermediate output feeds the given
// phase. Returns empty string if the phase has no predecessor.
func previousPhase(phase string) string {
	for i, p := range phaseOrder {
		if p == phase && i > 0 {
			return phaseOrder[i-1]
		}
	}
	return ""
}

func HandleRequest(ctx context.Context, event Event) error {
	phase := strings.TrimSpace(event.Phase)
	if phase == "" {
		return fmt.Errorf("phase is required; pass {\"phase\":\"<name>\"} (one of: %s)", strings.Join(validPhases(), ", "))
	}

	cfg, err := loadRuntimeConfig(ctx)
	if err != nil {
		return err
	}

	logJSON(map[string]any{
		"pipeline": "lobbying-index",
		"event":    "phase_dispatch",
		"phase":    phase,
		"dbPath":   cfg.dbPath,
	})

	switch phase {
	case phaseIngestOCLData:
		return runIngestOCLData(ctx, cfg)
	case phaseBuildMPLobbying:
		return runBuildMPLobbying(ctx, cfg)
	case phaseBuildOrganizationTables:
		return runBuildOrganizationTables(ctx, cfg)
	case phaseBuildBillContextTables:
		return runBuildBillContextTables(ctx, cfg)
	case phasePreBakeMinisterCommunications:
		return runPreBakeMinisterCommunications(ctx, cfg)
	case phaseFinalize:
		return runFinalize(ctx, cfg)
	case phaseAll:
		return runAll(ctx, cfg)
	default:
		return fmt.Errorf("unknown phase %q; valid phases: %s", phase, strings.Join(validPhases(), ", "))
	}
}

func validPhases() []string {
	out := append([]string{}, phaseOrder...)
	out = append(out, phaseAll)
	sort.Strings(out)
	return out
}

// runtimeConfig holds the resolved environment-driven configuration that
// every phase entry point needs.
type runtimeConfig struct {
	dbPath     string
	parliament int
	session    int
	store      *s3adapter.Store
	httpClient *http.Client
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
		httpClient: &http.Client{Timeout: 45 * time.Second},
	}, nil
}

// downloadPriorPhase pulls the previous phase's intermediate working SQLite
// to the local dbPath. Removes any stale local file first so the new
// download starts from a clean slate.
func (c *runtimeConfig) downloadPriorPhase(ctx context.Context, phase string) error {
	prev := previousPhase(phase)
	if prev == "" {
		return nil
	}
	if err := os.Remove(c.dbPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove stale local db: %w", err)
	}
	hash, err := c.store.DownloadIntermediate(ctx, prev, c.dbPath)
	if err != nil {
		return fmt.Errorf("download prior phase %s: %w", prev, err)
	}
	logJSON(map[string]any{
		"pipeline": "lobbying-index",
		"event":    "intermediate_downloaded",
		"phase":    prev,
		"sha256":   hash,
	})
	return nil
}

// uploadPhaseOutput pushes the working SQLite at dbPath to the phase's
// intermediate key for the next phase to consume.
func (c *runtimeConfig) uploadPhaseOutput(ctx context.Context, phase string) error {
	hash, size, err := c.store.UploadIntermediate(ctx, c.dbPath, phase)
	if err != nil {
		return fmt.Errorf("upload phase %s output: %w", phase, err)
	}
	logJSON(map[string]any{
		"pipeline":   "lobbying-index",
		"event":      "intermediate_uploaded",
		"phase":      phase,
		"sha256":     hash,
		"size_bytes": size,
	})
	return nil
}

func runIngestOCLData(ctx context.Context, cfg *runtimeConfig) error {
	if err := cfg.downloadPriorPhase(ctx, phaseIngestOCLData); err != nil {
		return err
	}
	if err := ingestOCLData(ctx, cfg); err != nil {
		return err
	}
	return cfg.uploadPhaseOutput(ctx, phaseIngestOCLData)
}

func runBuildMPLobbying(ctx context.Context, cfg *runtimeConfig) error {
	if err := cfg.downloadPriorPhase(ctx, phaseBuildMPLobbying); err != nil {
		return err
	}
	if err := aggregateMPLobbyingTables(cfg.dbPath, cfg.parliament); err != nil {
		return err
	}
	return cfg.uploadPhaseOutput(ctx, phaseBuildMPLobbying)
}

func runBuildOrganizationTables(ctx context.Context, cfg *runtimeConfig) error {
	if err := cfg.downloadPriorPhase(ctx, phaseBuildOrganizationTables); err != nil {
		return err
	}
	if err := buildOrganizationTables(ctx, cfg); err != nil {
		return err
	}
	return cfg.uploadPhaseOutput(ctx, phaseBuildOrganizationTables)
}

func runBuildBillContextTables(ctx context.Context, cfg *runtimeConfig) error {
	if err := cfg.downloadPriorPhase(ctx, phaseBuildBillContextTables); err != nil {
		return err
	}
	if err := buildBillContextTables(ctx, cfg); err != nil {
		return err
	}
	return cfg.uploadPhaseOutput(ctx, phaseBuildBillContextTables)
}

func runPreBakeMinisterCommunications(ctx context.Context, cfg *runtimeConfig) error {
	if err := cfg.downloadPriorPhase(ctx, phasePreBakeMinisterCommunications); err != nil {
		return err
	}
	if err := preBakeMinisterCommunications(ctx, cfg); err != nil {
		return err
	}
	return cfg.uploadPhaseOutput(ctx, phasePreBakeMinisterCommunications)
}

func runFinalize(ctx context.Context, cfg *runtimeConfig) error {
	if err := cfg.downloadPriorPhase(ctx, phaseFinalize); err != nil {
		return err
	}
	return finalizeArtifact(ctx, cfg)
}

// runAll preserves the legacy single-invocation whole-pipeline behavior so
// the builder can be exercised end-to-end locally without standing up the
// Step Function. It bypasses the intermediate-transfer round trips and
// publishes the same final artifact + manifest the old HandleRequest did.
func runAll(ctx context.Context, cfg *runtimeConfig) error {
	if err := ingestOCLData(ctx, cfg); err != nil {
		return err
	}
	if err := aggregateMPLobbyingTables(cfg.dbPath, cfg.parliament); err != nil {
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
	fetcher := ocl.NewFetcher(ocl.WithHTTPClient(cfg.httpClient), ocl.WithUserAgent(defaultUserAgent))
	memberSource := mycommons.NewFetcher(mycommons.WithHTTPClient(cfg.httpClient), mycommons.WithUserAgent(defaultUserAgent))
	subjectSource := subjects.NewFetcher(subjects.WithHTTPClient(cfg.httpClient), subjects.WithUserAgent(defaultUserAgent))
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
	legisFetcher := legisinfo.NewFetcher(legisinfo.WithHTTPClient(cfg.httpClient), legisinfo.WithUserAgent(defaultUserAgent))
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
	aggregator := sqlite.NewAggregator()
	cabinetSource := cabinet.NewFetcher(cabinet.WithHTTPClient(cfg.httpClient), cabinet.WithUserAgent(defaultUserAgent))
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

	tableCounts, err := countTables(cfg.dbPath)
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
	t := time.Now()
	logPhase("aggregate_mp_lobbying", "start", 0)
	if err := usecase.BuildMPLobbyingTables(db, aggregationRunner); err != nil {
		return err
	}
	logPhase("aggregate_mp_lobbying", "completed", time.Since(t).Milliseconds())
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
	lambda.Start(observability.WrapEvent("lobbying-index", HandleRequest))
}
