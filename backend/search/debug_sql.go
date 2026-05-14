//go:build integration

package main

import (
	"context"
	"fmt"
	"testing"
	"time"

	"epac/_testdb"
	"github.com/jackc/pgx/v5"
)

func TestDebugSQL(t *testing.T) {
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

		languageHint := "en"
		searchContext := SearchContext{}

		_, err := conn.Query(ctx, rankedSpeechSearchSQL,
			params.Query,
			languageHint,
			searchContext.MyMPMemberID,
			searchContext.TopicKeywordHints,
			searchContext.BillIDs,
			params.FromDate,
			params.ToDate,
			cfg.TextWeight,
			cfg.RecencyWeight,
			cfg.FollowWeight,
			cfg.RecencyHalfLife,
			cfg.LanguageHintBoost,
			cfg.MyMPBoost,
			cfg.BillBoost,
			cfg.TopicBoost,
		)
		fmt.Printf("Ranked err: %v\n", err)

		_, err2 := conn.Query(ctx, legacySpeechSearchSQL,
			params.Query,
			params.FromDate,
			params.ToDate,
			cfg.TextWeight,
			cfg.RecencyWeight,
			cfg.RecencyHalfLife,
		)
		fmt.Printf("Legacy err: %v\n", err2)
		t.Fail()
	})
}
