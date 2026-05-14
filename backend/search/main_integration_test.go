//go:build integration

package main

import (
	"context"
	"testing"
	"time"
	"epac/_testdb"
	"github.com/jackc/pgx/v5"
)

func TestSearchSpeechesNoDateFiltersBudgetQuery(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		ctx := context.Background()

		sittingDate := time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC)
		_testdb.SeedSpeech(t, conn, "speech-1", "This budget is great.", "Jane Doe", "mp-1", "Budget 2026", &sittingDate)

		params := SearchParams{
			Query: "budget",
		}
		cfg := RankingConfig{
			TextWeight:        0.72,
			RecencyWeight:     0.20,
			FollowWeight:      0.08,
			RecencyHalfLife:   90,
			LanguageHintBoost: 1.15,
			MyMPBoost:         1.0,
			BillBoost:         0.85,
			TopicBoost:        0.65,
		}

		results, err := search(ctx, conn, params, cfg)
		if err != nil {
			t.Fatalf("search failed: %v", err)
		}

		if len(results) == 0 {
			t.Fatalf("expected at least one result, got 0")
		}
		if results[0].Snippet == "" {
			t.Errorf("expected non-empty snippet")
		}
	})
}
