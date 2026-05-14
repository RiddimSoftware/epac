//go:build integration

package main

import (
	"context"
	"epac/_testdb"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"
)

func connectIntegrationDB(t *testing.T) *pgx.Conn {
	t.Helper()
	return _testdb.Connect(t)
}

func resetSearchTables(t *testing.T, conn *pgx.Conn) {
	t.Helper()

	if _, err := conn.Exec(context.Background(), `
		DELETE FROM speeches;
		DELETE FROM device_subscriptions;
	`); err != nil {
		t.Fatalf("reset test fixtures: %v", err)
	}
}

func seedSpeech(t *testing.T, conn *pgx.Conn, speech speechFixture) {
	t.Helper()

	_, err := conn.Exec(context.Background(), `
		INSERT INTO speeches (
			intervention_id,
			filename,
			speaker_name,
			content,
			sitting_date,
			member_id,
			subject_title,
			language,
			related_bill_ids
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
		ON CONFLICT (intervention_id) DO UPDATE SET
			filename         = EXCLUDED.filename,
			speaker_name     = EXCLUDED.speaker_name,
			content          = EXCLUDED.content,
			sitting_date     = EXCLUDED.sitting_date,
			member_id        = EXCLUDED.member_id,
			subject_title    = EXCLUDED.subject_title,
			language         = EXCLUDED.language,
			related_bill_ids = EXCLUDED.related_bill_ids;
	`,
		speech.interventionID,
		speech.filename,
		speech.speakerName,
		speech.content,
		speech.sittingDate,
		speech.memberID,
		speech.subjectTitle,
		speech.language,
		speech.relatedBillIDs,
	)
	if err != nil {
		t.Fatalf("seed speech %q failed: %v", speech.interventionID, err)
	}
}

func seedDeviceSubscription(t *testing.T, conn *pgx.Conn, subscription deviceSubscriptionFixture) {
	t.Helper()

	_, err := conn.Exec(context.Background(), `
		INSERT INTO device_subscriptions (
			token,
			topic_ids,
			granularity,
			my_mp_member_id,
			bill_ids
		) VALUES ($1, $2, $3::jsonb, $4, $5)
		ON CONFLICT (token) DO UPDATE SET
			topic_ids       = EXCLUDED.topic_ids,
			granularity     = EXCLUDED.granularity,
			my_mp_member_id = EXCLUDED.my_mp_member_id,
			bill_ids        = EXCLUDED.bill_ids;
	`,
		subscription.token,
		subscription.topicIDs,
		subscription.granularity,
		subscription.myMPMemberID,
		subscription.billIDs,
	)
	if err != nil {
		t.Fatalf("seed device subscription %q failed: %v", subscription.token, err)
	}
}

type speechFixture struct {
	interventionID string
	filename       string
	speakerName    string
	content        string
	sittingDate    *time.Time
	memberID       *string
	subjectTitle   string
	language       string
	relatedBillIDs []string
}

type deviceSubscriptionFixture struct {
	token        string
	topicIDs     []string
	granularity  string
	myMPMemberID *string
	billIDs      []string
}

func executeSearchRequest(t *testing.T, conn *pgx.Conn, query string, userID string, fromDate string, toDate string, cfg RankingConfig) (SearchResponse, error) {
	t.Helper()

	params := map[string]string{"q": query}
	if userID != "" {
		params["user_id"] = userID
	}
	if fromDate != "" {
		params["from_date"] = fromDate
	}
	if toDate != "" {
		params["to_date"] = toDate
	}

	parsed, err := paramsFromRequest(events.APIGatewayProxyRequest{QueryStringParameters: params})
	if err != nil {
		return SearchResponse{}, err
	}

	results, err := search(context.Background(), conn, parsed, cfg)
	if err != nil {
		return SearchResponse{}, err
	}
	if results == nil {
		results = []SearchResult{}
	}

	return SearchResponse{
		Query:        parsed.Query,
		LanguageHint: detectQueryLanguage(parsed.Query),
		Results:      results,
	}, nil
}

func fixedRankingConfig() RankingConfig {
	return RankingConfig{
		TextWeight:        1,
		RecencyWeight:     0,
		FollowWeight:      1,
		RecencyHalfLife:   90,
		LanguageHintBoost: 1,
		MyMPBoost:         2,
		BillBoost:         2,
		TopicBoost:        0,
	}
}

func parseDate(t *testing.T, value string) *time.Time {
	t.Helper()
	if value == "" {
		return nil
	}
	d, err := time.Parse("2006-01-02", value)
	if err != nil {
		t.Fatalf("parse date %q: %v", value, err)
	}
	return &d
}

func TestSearchSpeechesNoFilters_MatchesEnglishQuery(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	seedSpeech(t, conn, speechFixture{
		interventionID: "en-001",
		filename:       "en-001.xml",
		speakerName:    "Member A",
		content:        "The budget was discussed after a long debate on inflation and interest rates.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-01"),
	})
	seedSpeech(t, conn, speechFixture{
		interventionID: "en-002",
		filename:       "en-002.xml",
		speakerName:    "Member B",
		content:        "Housing costs are high, and affordable options remain scarce.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-02"),
	})
	seedSpeech(t, conn, speechFixture{
		interventionID: "en-003",
		filename:       "en-003.xml",
		speakerName:    "Member C",
		content:        "The budget also included measures for seniors and transit spending.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-03"),
	})

	resp, err := executeSearchRequest(t, conn, "budget", "", "", "", fixedRankingConfig())
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if resp.LanguageHint != "en" {
		t.Fatalf("language hint = %q, want en", resp.LanguageHint)
	}
	if len(resp.Results) == 0 {
		t.Fatal("expected at least one result")
	}
	if !strings.HasPrefix(resp.Results[0].ID, "en-") {
		t.Fatalf("unexpected result id %q", resp.Results[0].ID)
	}
}

func TestSearchSpeechesNoFilters_MatchesFrenchQuery(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	seedSpeech(t, conn, speechFixture{
		interventionID: "fr-001",
		filename:       "fr-001.xml",
		speakerName:    "Membre A",
		content:        "Le budget fédéral prévoit des mesures importantes sur la santé et l'éducation.",
		language:       "fr",
		sittingDate:    parseDate(t, "2026-04-10"),
	})
	seedSpeech(t, conn, speechFixture{
		interventionID: "fr-002",
		filename:       "fr-002.xml",
		speakerName:    "Membre B",
		content:        "Le projet de loi contient une clause budgétaire complète sur la fiscalité.",
		language:       "fr",
		sittingDate:    parseDate(t, "2026-04-11"),
	})

	resp, err := executeSearchRequest(t, conn, "budgétaire", "", "", "", fixedRankingConfig())
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if resp.LanguageHint != "fr" {
		t.Fatalf("language hint = %q, want fr", resp.LanguageHint)
	}
	if len(resp.Results) == 0 {
		t.Fatal("expected at least one French result")
	}
	if resp.Results[0].Snippet == "" {
		t.Fatal("expected non-empty snippet")
	}
}

func TestSearchSpeechesWithDateRange_FiltersOutOfRange(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	seedSpeech(t, conn, speechFixture{
		interventionID: "date-001",
		filename:       "date-001.xml",
		speakerName:    "Member A",
		content:        "Budget discussion in last year planning season.",
		language:       "en",
		sittingDate:    parseDate(t, "2025-01-01"),
	})
	seedSpeech(t, conn, speechFixture{
		interventionID: "date-002",
		filename:       "date-002.xml",
		speakerName:    "Member B",
		content:        "Budget discussion in spring with members joining.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-03-10"),
	})
	seedSpeech(t, conn, speechFixture{
		interventionID: "date-003",
		filename:       "date-003.xml",
		speakerName:    "Member C",
		content:        "Budget discussion in summer sessions.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-07-01"),
	})

	resp, err := executeSearchRequest(t, conn, "budget", "", "2026-03-01", "2026-03-31", fixedRankingConfig())
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if len(resp.Results) != 1 {
		t.Fatalf("got %d results, want 1", len(resp.Results))
	}
	if resp.Results[0].ID != "date-002" {
		t.Fatalf("result id = %q, want %q", resp.Results[0].ID, "date-002")
	}
}

func TestSearchSpeechesEmptyResults_NoError(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	seedSpeech(t, conn, speechFixture{
		interventionID: "noise-001",
		filename:       "noise-001.xml",
		speakerName:    "Member A",
		content:        "Weather conditions and transit delays occupied the chamber today.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-01"),
	})

	resp, err := executeSearchRequest(t, conn, "xzqv_nonexistent_token", "", "", "", fixedRankingConfig())
	if err != nil {
		t.Fatalf("search returned unexpected error: %v", err)
	}
	if resp.Results == nil {
		t.Fatal("expected non-nil results slice")
	}
	if len(resp.Results) != 0 {
		t.Fatalf("got %d results, want 0", len(resp.Results))
	}
}

func TestSearchSpeechesSnippet_HighlightsMatch(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	seedSpeech(t, conn, speechFixture{
		interventionID: "snippet-001",
		filename:       "snippet-001.xml",
		speakerName:    "Member A",
		content:        "The housing budget was carefully amended in committee to include new support measures.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-01"),
	})

	resp, err := executeSearchRequest(t, conn, "housing", "", "", "", fixedRankingConfig())
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if len(resp.Results) != 1 {
		t.Fatalf("got %d results, want 1", len(resp.Results))
	}
	if !strings.Contains(strings.ToLower(resp.Results[0].Snippet), "housing") {
		t.Fatalf("snippet does not include query term: %q", resp.Results[0].Snippet)
	}
}

func TestSearchSpeechesUserContext_AppliesMyMPBoost(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	memberID := "member-123"
	seedSpeech(t, conn, speechFixture{
		interventionID: "my-mp-hit",
		filename:       "my-mp-hit.xml",
		speakerName:    "Preferred MP",
		content:        "Budget planning includes transport and housing investments.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-01"),
		memberID:       &memberID,
	})
	otherMemberID := "member-999"
	seedSpeech(t, conn, speechFixture{
		interventionID: "my-mp-miss",
		filename:       "my-mp-miss.xml",
		speakerName:    "Other MP",
		content:        "Budget planning includes transport and housing investments.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-01"),
		memberID:       &otherMemberID,
	})
	seedDeviceSubscription(t, conn, deviceSubscriptionFixture{
		token:        "user-mp",
		topicIDs:     []string{},
		granularity:  "{}",
		myMPMemberID: &memberID,
		billIDs:      []string{},
	})

	cfg := fixedRankingConfig()
	cfg.MyMPBoost = 5

	resp, err := executeSearchRequest(t, conn, "budget", "user-mp", "", "", cfg)
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if len(resp.Results) != 2 {
		t.Fatalf("got %d results, want 2", len(resp.Results))
	}
	if resp.Results[0].ID != "my-mp-hit" {
		t.Fatalf("top result id = %q, want my-mp-hit", resp.Results[0].ID)
	}
}

func TestSearchSpeechesUserContext_AppliesBillBoost(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	aMember := "member-a"
	bMember := "member-b"
	seedSpeech(t, conn, speechFixture{
		interventionID: "bill-hit",
		filename:       "bill-hit.xml",
		speakerName:    "Member A",
		content:        "The budget bill review covers amendments for public infrastructure.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-02"),
		memberID:       &aMember,
		relatedBillIDs: []string{"bill-123"},
	})
	seedSpeech(t, conn, speechFixture{
		interventionID: "bill-miss",
		filename:       "bill-miss.xml",
		speakerName:    "Member B",
		content:        "The budget bill review covers amendments for public infrastructure.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-02"),
		memberID:       &bMember,
	})
	seedDeviceSubscription(t, conn, deviceSubscriptionFixture{
		token:        "user-bill",
		topicIDs:     []string{},
		granularity:  "{}",
		myMPMemberID: nil,
		billIDs:      []string{"bill-123"},
	})

	cfg := fixedRankingConfig()
	cfg.BillBoost = 4

	resp, err := executeSearchRequest(t, conn, "budget", "user-bill", "", "", cfg)
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if len(resp.Results) != 2 {
		t.Fatalf("got %d results, want 2", len(resp.Results))
	}
	if resp.Results[0].ID != "bill-hit" {
		t.Fatalf("top result id = %q, want bill-hit", resp.Results[0].ID)
	}
}

func TestSearchSpeechesLegacyFallback(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	// No defer conn.Close here: testdb.Connect registers its own t.Cleanup to close
	// the connection, and closing it early via defer would cause the t.Cleanup
	// registered below (restoreSpeechVectors) to fail with "conn closed".
	resetSearchTables(t, conn)

	seedSpeech(t, conn, speechFixture{
		interventionID: "legacy-001",
		filename:       "legacy-001.xml",
		speakerName:    "Member A",
		content:        "Budget planning continues under the legacy text search path.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-01"),
	})

	cfg := fixedRankingConfig()
	cfg.MyMPBoost = 0
	cfg.BillBoost = 0

	hadVectorColumns := hasSpeechVectorColumns(t, conn)
	if hadVectorColumns {
		if _, err := conn.Exec(ctx, `ALTER TABLE speeches DROP COLUMN search_vector_en; ALTER TABLE speeches DROP COLUMN search_vector_fr;`); err != nil {
			t.Fatalf("drop search_vector columns for legacy fallback test: %v", err)
		}
		t.Cleanup(func() {
			restoreSpeechVectors(t, conn)
		})
	}

	if _, err := conn.Query(ctx, rankedSpeechSearchSQL,
		"legacy",
		"en",
		"",
		[]string{},
		[]string{},
		nil,
		nil,
		cfg.TextWeight,
		cfg.RecencyWeight,
		cfg.FollowWeight,
		cfg.RecencyHalfLife,
		cfg.LanguageHintBoost,
		cfg.MyMPBoost,
		cfg.BillBoost,
		cfg.TopicBoost,
	); err == nil {
		t.Fatalf("expected ranked query to fail when bilingual vectors are unavailable")
	}

	resp, err := executeSearchRequest(t, conn, "legacy", "", "", "", cfg)
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if len(resp.Results) != 1 {
		t.Fatalf("got %d results, want 1", len(resp.Results))
	}
	if resp.Results[0].ID != "legacy-001" {
		t.Fatalf("result id = %q, want legacy-001", resp.Results[0].ID)
	}
}

func TestSearchSpeechesMaliciousInput_SafeFromSQLi(t *testing.T) {
	ctx := context.Background()
	conn := connectIntegrationDB(t)
	defer conn.Close(ctx)
	resetSearchTables(t, conn)

	seedSpeech(t, conn, speechFixture{
		interventionID: "safe-001",
		filename:       "safe-001.xml",
		speakerName:    "Member A",
		content:        "Budget transparency remains a priority for all members.",
		language:       "en",
		sittingDate:    parseDate(t, "2026-05-01"),
	})

	cfg := fixedRankingConfig()
	resp, err := executeSearchRequest(t, conn, ")' ; DROP TABLE speeches; --", "", "", "", cfg)
	if err != nil {
		t.Fatalf("search returned unexpected error: %v", err)
	}

	if resp.Results == nil {
		t.Fatalf("expected non-nil results slice")
	}

	var speechesExists bool
	if err := conn.QueryRow(ctx, "SELECT to_regclass('public.speeches') IS NOT NULL").Scan(&speechesExists); err != nil {
		t.Fatalf("check speeches table existence: %v", err)
	}
	if !speechesExists {
		t.Fatal("speeches table does not exist after malicious query")
	}
}

func hasSpeechVectorColumns(t *testing.T, conn *pgx.Conn) bool {
	t.Helper()

	var exists bool
	if err := conn.QueryRow(context.Background(), `
		SELECT COUNT(*) = 2
		FROM information_schema.columns
		WHERE table_name = 'speeches'
			AND column_name IN ('search_vector_en', 'search_vector_fr')
	`).Scan(&exists); err != nil {
		t.Fatalf("check speech vector columns: %v", err)
	}
	return exists
}

func restoreSpeechVectors(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	if _, err := conn.Exec(context.Background(), `
		ALTER TABLE speeches
			ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'en';
		ALTER TABLE speeches
			ADD COLUMN IF NOT EXISTS search_vector_en TSVECTOR GENERATED ALWAYS AS (
				CASE
					WHEN language IN ('en', 'mixed', 'und')
						THEN to_tsvector('english', COALESCE(content, ''))
					ELSE NULL
				END
			) STORED;
		ALTER TABLE speeches
			ADD COLUMN IF NOT EXISTS search_vector_fr TSVECTOR GENERATED ALWAYS AS (
				CASE
					WHEN language IN ('fr', 'mixed', 'und')
						THEN to_tsvector('french', COALESCE(content, ''))
					ELSE NULL
				END
			) STORED;
		ALTER TABLE speeches
			DROP CONSTRAINT IF EXISTS speeches_language_check,
			ADD CONSTRAINT speeches_language_check
				CHECK (language IN ('en', 'fr', 'mixed', 'und'));
		UPDATE speeches
			SET language = CASE
				WHEN filename ILIKE '%-F.XML' THEN 'fr'
				WHEN language IS NULL OR language = '' THEN 'en'
				ELSE language
			END;
		CREATE INDEX IF NOT EXISTS speeches_fts_en_idx
			ON speeches USING gin(search_vector_en)
			WHERE search_vector_en IS NOT NULL;
			CREATE INDEX IF NOT EXISTS speeches_fts_fr_idx
				ON speeches USING gin(search_vector_fr)
				WHERE search_vector_fr IS NOT NULL;
	`); err != nil {
		t.Fatalf("restore speech vectors: %v", err)
	}
}
