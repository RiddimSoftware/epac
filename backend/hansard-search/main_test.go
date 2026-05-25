package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"epac/hansard-search/internal/adapter/sqlitefile"
	"epac/hansard-search/internal/adapter/sqlitefts5"
	"epac/hansard-search/internal/domain"
	"epac/hansard-search/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	_ "modernc.org/sqlite"
)

type stubSearchService struct {
	gotQuery      usecase.SearchQuery
	gotPagination usecase.Pagination
	results       usecase.SearchResults
	err           error
}

func (s *stubSearchService) Execute(_ context.Context, q usecase.SearchQuery, p usecase.Pagination) (usecase.SearchResults, error) {
	s.gotQuery = q
	s.gotPagination = p
	return s.results, s.err
}

type stubManifestLoader struct {
	manifest domain.Manifest
	err      error
}

func (s stubManifestLoader) Load(_ context.Context) (domain.Manifest, error) {
	return s.manifest, s.err
}

type mockS3Downloader struct {
	body []byte
	err  error
}

func (m *mockS3Downloader) GetObject(_ context.Context, _ *s3.GetObjectInput, _ ...func(*s3.Options)) (*s3.GetObjectOutput, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &s3.GetObjectOutput{Body: io.NopCloser(bytes.NewReader(m.body))}, nil
}

func TestHandleRequestParsesQueryParametersAndPreservesSnippetMarkup(t *testing.T) {
	stub := &stubSearchService{
		results: usecase.SearchResults{
			Total: 1,
			Hits: []usecase.SearchHit{
				{
					ParliamentNumber:  45,
					SessionNumber:     1,
					SittingDate:       "2026-05-23",
					InterventionID:    "intervention-4",
					MessageID:         "message-4",
					SpeakerName:       "Jane Smith",
					PartyAbbreviation: "LIB",
					RidingName:        "Ottawa Centre",
					Topic:             "Climate Housing",
					Snippet:           "…<mark>climate</mark> change affects housing supply.…",
					Score:             -1.23,
				},
			},
		},
	}
	setSearchServiceForTest(t, stub)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		QueryStringParameters: map[string]string{
			"q":        "  climate  ",
			"speaker":  " Jane Smith ",
			"topic":    " Climate Housing ",
			"page":     "2",
			"per_page": "1",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", resp.StatusCode, resp.Body)
	}
	if got := resp.Headers["Content-Type"]; got != "application/json" {
		t.Fatalf("content type = %q, want application/json", got)
	}
	if stub.gotQuery != (usecase.SearchQuery{
		Query:   "climate",
		Speaker: "Jane Smith",
		Topic:   "Climate Housing",
	}) {
		t.Fatalf("query = %#v", stub.gotQuery)
	}
	if stub.gotPagination != (usecase.Pagination{Page: 2, PerPage: 1}) {
		t.Fatalf("pagination = %#v", stub.gotPagination)
	}
	if !strings.Contains(resp.Body, "<mark>climate</mark>") {
		t.Fatalf("response body did not preserve snippet markup: %s", resp.Body)
	}
	if strings.Contains(resp.Body, "\\u003cmark\\u003e") {
		t.Fatalf("response body HTML-escaped snippet markup: %s", resp.Body)
	}

	var body searchResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Page != 2 || body.PerPage != 1 || body.Total != 1 {
		t.Fatalf("unexpected pagination body: %#v", body)
	}
	if len(body.Results) != 1 || body.Results[0].Snippet != "…<mark>climate</mark> change affects housing supply.…" {
		t.Fatalf("unexpected results: %#v", body.Results)
	}
}

func TestHandleRequestRejectsInvalidQueryParameters(t *testing.T) {
	tests := []struct {
		name   string
		query  map[string]string
		needle string
	}{
		{name: "missing q", query: map[string]string{}, needle: "q is required"},
		{name: "q too long", query: map[string]string{"q": strings.Repeat("a", maxQueryLength+1)}, needle: "q must be at most"},
		{name: "speaker too long", query: map[string]string{"q": "climate", "speaker": strings.Repeat("b", maxSpeakerLength+1)}, needle: "speaker must be at most"},
		{name: "topic too long", query: map[string]string{"q": "climate", "topic": strings.Repeat("c", maxTopicLength+1)}, needle: "topic must be at most"},
		{name: "page invalid", query: map[string]string{"q": "climate", "page": "0"}, needle: "page must be an integer"},
		{name: "per_page invalid", query: map[string]string{"q": "climate", "per_page": "101"}, needle: "per_page must be an integer between 1 and 100"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
				QueryStringParameters: tt.query,
			})
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			assertJSONError(t, resp, http.StatusBadRequest, tt.needle)
		})
	}
}

func TestHandleRequestMapsSearchErrors(t *testing.T) {
	tests := []struct {
		name            string
		err             error
		wantStatus      int
		wantRetryAfter  string
		wantBodyMessage string
	}{
		{
			name:            "invalid query",
			err:             usecase.ErrInvalidQuery,
			wantStatus:      http.StatusBadRequest,
			wantBodyMessage: usecase.ErrInvalidQuery.Error(),
		},
		{
			name:            "invalid query syntax",
			err:             usecase.ErrInvalidQuerySyntax,
			wantStatus:      http.StatusBadRequest,
			wantBodyMessage: usecase.ErrInvalidQuerySyntax.Error(),
		},
		{
			name:            "manifest missing",
			err:             usecase.ErrManifestNotFound,
			wantStatus:      http.StatusServiceUnavailable,
			wantRetryAfter:  searchRetryAfter,
			wantBodyMessage: usecase.ErrManifestNotFound.Error(),
		},
		{
			name:            "checksum mismatch",
			err:             usecase.ErrChecksumMismatch,
			wantStatus:      http.StatusServiceUnavailable,
			wantRetryAfter:  searchRetryAfter,
			wantBodyMessage: usecase.ErrChecksumMismatch.Error(),
		},
		{
			name:            "unexpected",
			err:             errors.New("boom"),
			wantStatus:      http.StatusInternalServerError,
			wantBodyMessage: "internal error",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			setSearchServiceForTest(t, &stubSearchService{err: tt.err})

			resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
				QueryStringParameters: map[string]string{"q": "climate"},
			})
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			assertJSONError(t, resp, tt.wantStatus, tt.wantBodyMessage)
			if tt.wantRetryAfter != "" && resp.Headers["Retry-After"] != tt.wantRetryAfter {
				t.Fatalf("Retry-After = %q, want %q", resp.Headers["Retry-After"], tt.wantRetryAfter)
			}
		})
	}
}

func TestHandleRequestIntegration_HappyPath(t *testing.T) {
	setSearchServiceForTest(t, newFixtureRuntime(t, "v1", nil))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		QueryStringParameters: map[string]string{"q": "climate", "per_page": "1"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", resp.StatusCode, resp.Body)
	}

	var body searchResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Page != 1 || body.PerPage != 1 {
		t.Fatalf("unexpected pagination body: %#v", body)
	}
	if body.Total != 2 || len(body.Results) != 1 {
		t.Fatalf("unexpected results body: %#v", body)
	}
	if body.Results[0].MessageID == "" || !strings.Contains(body.Results[0].Snippet, "<mark>") {
		t.Fatalf("unexpected hit payload: %#v", body.Results[0])
	}
}

func TestHandleRequestIntegration_InvalidQueryReturns400(t *testing.T) {
	setSearchServiceForTest(t, newFixtureRuntime(t, "v1", nil))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		QueryStringParameters: map[string]string{"q": "\u0007"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertJSONError(t, resp, http.StatusBadRequest, usecase.ErrInvalidQuery.Error())
}

func TestHandleRequestIntegration_InvalidQuerySyntaxReturns400(t *testing.T) {
	setSearchServiceForTest(t, newFixtureRuntime(t, "v1", nil))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		QueryStringParameters: map[string]string{"q": "\"unclosed"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertJSONError(t, resp, http.StatusBadRequest, usecase.ErrInvalidQuerySyntax.Error())
}

func TestHandleRequestIntegration_ManifestMissingReturns503(t *testing.T) {
	setSearchServiceForTest(t, newFixtureRuntime(t, "v1", usecase.ErrManifestNotFound))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		QueryStringParameters: map[string]string{"q": "climate"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertJSONError(t, resp, http.StatusServiceUnavailable, usecase.ErrManifestNotFound.Error())
	if resp.Headers["Retry-After"] != searchRetryAfter {
		t.Fatalf("Retry-After = %q, want %q", resp.Headers["Retry-After"], searchRetryAfter)
	}
}

func TestHandleRequestIntegration_SchemaMismatchReturns503(t *testing.T) {
	setSearchServiceForTest(t, newFixtureRuntime(t, "v99", nil))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		QueryStringParameters: map[string]string{"q": "climate"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertJSONError(t, resp, http.StatusServiceUnavailable, usecase.ErrSchemaMismatch.Error())
	if resp.Headers["Retry-After"] != searchRetryAfter {
		t.Fatalf("Retry-After = %q, want %q", resp.Headers["Retry-After"], searchRetryAfter)
	}
}

func TestHandleRequestIntegration_Pagination(t *testing.T) {
	setSearchServiceForTest(t, newFixtureRuntime(t, "v1", nil))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		QueryStringParameters: map[string]string{"q": "climate", "page": "2", "per_page": "1"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", resp.StatusCode, resp.Body)
	}

	var body searchResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Page != 2 || body.PerPage != 1 || body.Total != 2 {
		t.Fatalf("unexpected pagination body: %#v", body)
	}
	if len(body.Results) != 1 {
		t.Fatalf("results len = %d, want 1", len(body.Results))
	}
}

func setSearchServiceForTest(t *testing.T, service searchExecutor) {
	t.Helper()

	previous := searchService
	searchService = service
	t.Cleanup(func() {
		searchService = previous
	})
}

func assertJSONError(t *testing.T, resp events.APIGatewayV2HTTPResponse, wantStatus int, wantBodyFragment string) {
	t.Helper()

	if resp.StatusCode != wantStatus {
		t.Fatalf("status = %d, want %d: %s", resp.StatusCode, wantStatus, resp.Body)
	}
	if got := resp.Headers["Content-Type"]; got != "application/json" {
		t.Fatalf("content type = %q, want application/json", got)
	}

	var body map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	if !strings.Contains(body["error"], wantBodyFragment) {
		t.Fatalf("error body = %q, want fragment %q", body["error"], wantBodyFragment)
	}
}

func newFixtureRuntime(t *testing.T, schemaVersion string, manifestErr error) searchExecutor {
	t.Helper()

	manifest, sqliteBytes := createFixtureManifestAndSQLite(t, schemaVersion)
	openIndex := usecase.NewOpenSearchIndex(
		stubManifestLoader{manifest: manifest, err: manifestErr},
		sqlitefile.NewIndexDownloader(&mockS3Downloader{body: sqliteBytes}, "fixture-bucket"),
	).Execute

	return newSearchRuntime(
		openIndex,
		openSQLiteReadOnly,
		func(db *sql.DB) searchExecutor {
			return usecase.SearchHansard{Repo: sqlitefts5.New(db)}
		},
	)
}

func createFixtureManifestAndSQLite(t *testing.T, schemaVersion string) (domain.Manifest, []byte) {
	t.Helper()

	path := filepath.Join(t.TempDir(), "fixture.sqlite")
	db, err := sql.Open("sqlite", "file:"+path)
	if err != nil {
		t.Fatalf("open sqlite fixture: %v", err)
	}

	statements := []string{
		`CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
		`INSERT INTO meta (key, value) VALUES ('version', '` + schemaVersion + `')`,
		`CREATE TABLE interventions (
			rowid INTEGER PRIMARY KEY,
			parliament_number INTEGER NOT NULL,
			session_number INTEGER NOT NULL,
			sitting_date TEXT NOT NULL,
			intervention_id TEXT NOT NULL UNIQUE,
			speaker_name TEXT NOT NULL,
			party_abbreviation TEXT NOT NULL DEFAULT '',
			riding_name TEXT NOT NULL DEFAULT '',
			topic TEXT NOT NULL DEFAULT ''
		)`,
		`CREATE TABLE messages (
			rowid INTEGER PRIMARY KEY,
			intervention_rowid INTEGER NOT NULL REFERENCES interventions(rowid),
			message_id TEXT NOT NULL UNIQUE,
			position INTEGER NOT NULL,
			content TEXT NOT NULL
		)`,
		`CREATE VIRTUAL TABLE messages_fts USING fts5(content)`,
		`INSERT INTO interventions (rowid, parliament_number, session_number, sitting_date, intervention_id, speaker_name, party_abbreviation, riding_name, topic) VALUES
			(1, 45, 1, '2026-05-20', 'intervention-1', 'Jane Smith', 'LIB', 'Ottawa Centre', 'Climate Action'),
			(2, 45, 1, '2026-05-21', 'intervention-2', 'Bob Brown', 'CPC', 'Calgary West', 'Energy Policy'),
			(3, 45, 1, '2026-05-22', 'intervention-3', 'Alice Green', 'NDP', 'Toronto Centre', 'Housing'),
			(4, 45, 1, '2026-05-23', 'intervention-4', 'Jane Smith', 'LIB', 'Ottawa Centre', 'Climate Housing')`,
		`INSERT INTO messages (rowid, intervention_rowid, message_id, position, content) VALUES
			(1, 1, 'message-1', 1, 'Climate change demands urgent action from Parliament.'),
			(2, 2, 'message-2', 1, 'Reliable energy policy should protect workers.'),
			(3, 3, 'message-3', 1, 'Housing affordability is central to this debate.'),
			(4, 4, 'message-4', 1, 'Climate change affects housing supply.')`,
		`INSERT INTO messages_fts (rowid, content) VALUES
			(1, 'Climate change demands urgent action from Parliament.'),
			(2, 'Reliable energy policy should protect workers.'),
			(3, 'Housing affordability is central to this debate.'),
			(4, 'Climate change affects housing supply.')`,
	}

	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			t.Fatalf("exec fixture statement: %v", err)
		}
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close sqlite fixture: %v", err)
	}

	sqliteBytes, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read sqlite fixture: %v", err)
	}

	return domain.Manifest{
		Version:           "1",
		BuiltAt:           "2026-05-25T00:00:00Z",
		ParliamentNumber:  45,
		SessionNumber:     1,
		SittingCount:      4,
		InterventionCount: 4,
		MessageCount:      4,
		SQLiteKey:         "hansard-search/v1/index.sqlite",
		SQLiteSizeBytes:   int64(len(sqliteBytes)),
		SQLiteSHA256:      sha256hex(sqliteBytes),
	}, sqliteBytes
}

func sha256hex(data []byte) string {
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:])
}
