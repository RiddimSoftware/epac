//go:build integration

package main

import (
	"context"
	"strings"
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

		_, err := search(ctx, conn, params, cfg)
		if err == nil {
			t.Fatalf("expected error reproducing the live ts_headline bug, got nil")
		}
		if !strings.Contains(err.Error(), "invalid parameter list format") {
			t.Fatalf("expected error to contain 'invalid parameter list format', got: %v", err)
		}
	})
}
