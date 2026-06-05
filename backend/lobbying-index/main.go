package main

import (
	"context"
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

	// Phase identifiers accepted through the Step Functions event payload or PHASE environment variable.
	phaseIngestOCLData                 = "IngestOCLData"
	phaseBuildMPLobbyingTables         = "BuildMPLobbyingTables"
	phaseBuildOrganizationTables       = "BuildOrganizationTables"
	phaseBuildBillContextTables        = "BuildBillContextTables"
	phasePreBakeMinisterCommunications = "PreBakeMinisterCommunications"
	phaseFinalize                      = "Finalize"
	phaseAll                           = "all"
)

// phaseOrder is the linear pipeline order. Each phase reads the previous
// phase's intermediate artifact and writes its own under <prefix>/tmp/.
var phaseOrder = []string{
	phaseIngestOCLData,
	phaseBuildMPLobbyingTables,
	phaseBuildOrganizationTables,
	phaseBuildBillContextTables,
	phasePreBakeMinisterCommunications,
	phaseFinalize,
}

var knownPhases = append(append([]string{}, phaseOrder...), phaseAll)

type PhaseEvent struct {
	Phase string `json:"phase"`
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

// HandleRequest is the Lambda entrypoint. It is invoked once per Step Functions
// state-machine phase; the event payload selects which phase runs, with PHASE
// kept as a fallback for direct Lambda invocations.
func HandleRequest(ctx context.Context, event PhaseEvent) error {
	phase := strings.TrimSpace(event.Phase)
	if phase == "" {
		phase = strings.TrimSpace(os.Getenv("PHASE"))
	}
	if err := validatePhase(phase, phaseRunners(nil)); err != nil {
		return err
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

	return dispatchPhase(ctx, phase, phaseRunners(cfg))
}

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

func phaseRunners(cfg *runtimeConfig) map[string]func(context.Context) error {
	return map[string]func(context.Context) error{
		phaseIngestOCLData: func(ctx context.Context) error {
			return runIngestOCLData(ctx, cfg)
		},
		phaseBuildMPLobbyingTables: func(ctx context.Context) error {
			return runBuildMPLobbyingTables(ctx, cfg)
		},
		phaseBuildOrganizationTables: func(ctx context.Context) error {
			return runBuildOrganizationTables(ctx, cfg)
		},
		phaseBuildBillContextTables: func(ctx context.Context) error {
			return runBuildBillContextTables(ctx, cfg)
		},
		phasePreBakeMinisterCommunications: func(ctx context.Context) error {
			return runPreBakeMinisterCommunications(ctx, cfg)
		},
		phaseFinalize: func(ctx context.Context) error {
			return runFinalize(ctx, cfg)
		},
		phaseAll: func(ctx context.Context) error {
			return runAll(ctx, cfg)
		},
	}
}

func dispatchPhase(ctx context.Context, phase string, runners map[string]func(context.Context) error) error {
	if err := validatePhase(phase, runners); err != nil {
		return err
	}
	return runners[strings.TrimSpace(phase)](ctx)
}

func validatePhase(phase string, runners map[string]func(context.Context) error) error {
	phase = strings.TrimSpace(phase)
	if phase == "" {
		return fmt.Errorf("PHASE is required; valid phases: %s", strings.Join(validPhaseNames(runners), ", "))
	}
	if runners[phase] == nil {
		return fmt.Errorf("unknown PHASE %q; valid phases: %s", phase, strings.Join(validPhaseNames(runners), ", "))
	}
	return nil
}

func validPhaseNames(runners map[string]func(context.Context) error) []string {
	names := make([]string, 0, len(runners))
	for name := range runners {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
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

func runBuildMPLobbyingTables(ctx context.Context, cfg *runtimeConfig) error {
	if err := cfg.downloadPriorPhase(ctx, phaseBuildMPLobbyingTables); err != nil {
		return err
	}
	if err := buildMPLobbyingTables(ctx, cfg); err != nil {
		return err
	}
	return cfg.uploadPhaseOutput(ctx, phaseBuildMPLobbyingTables)
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

// runAll is a local-development-only PHASE=all escape hatch. Production
// orchestration should invoke the named phases above through Step Functions.
// It bypasses the intermediate-transfer round trips and publishes the same
// final artifact + manifest the old HandleRequest did.
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
	lambda.Start(observability.WrapEvent("lobbying-index", HandleRequest))
}
