// on-this-day publisher emits the full static historical index used by
// GET /api/v1/on-this-day.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"epac/on-this-day/internal/adapter/postgres"
	"epac/on-this-day/internal/usecase"
	"github.com/jackc/pgx/v5"
)

type allResponse struct {
	Items []usecase.OnThisDayItem `json:"items"`
}

func main() {
	output := flag.String("output", "../../../build/artifacts/on-this-day", "artifact output directory")
	databaseURL := flag.String("database-url", os.Getenv("DATABASE_URL"), "Postgres connection string")
	flag.Parse()

	if strings.TrimSpace(*databaseURL) == "" {
		fmt.Fprintln(os.Stderr, "DATABASE_URL is required")
		os.Exit(1)
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, *databaseURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	items, err := readAllItems(ctx, conn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read on-this-day rows: %v\n", err)
		os.Exit(1)
	}
	if err := writeJSON(filepath.Join(*output, "v1", "all.json"), allResponse{Items: items}); err != nil {
		fmt.Fprintf(os.Stderr, "write artifact: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published %d on-this-day records\n", len(items))
}

func readAllItems(ctx context.Context, conn *pgx.Conn) ([]usecase.OnThisDayItem, error) {
	rows, err := conn.Query(ctx, `
		SELECT
			s.intervention_id,
			EXTRACT(YEAR FROM s.sitting_date)::int AS year,
			s.sitting_date,
			COALESCE(s.speaker_name, ''),
			COALESCE(s.subject_title, ''),
			COALESCE(s.content, ''),
			s.member_id,
			s.source_url
		FROM speeches s
		LEFT JOIN members m ON m.person_id = s.member_id
		WHERE s.sitting_date IS NOT NULL
			AND COALESCE(s.content, '') <> ''
		ORDER BY
			EXTRACT(MONTH FROM s.sitting_date)::int,
			EXTRACT(DAY FROM s.sitting_date)::int,
			CASE WHEN m.person_id IS NOT NULL AND (m.to_date IS NULL OR m.to_date >= CURRENT_DATE) THEN 1 ELSE 0 END DESC,
			COALESCE(cardinality(s.related_bill_ids), 0) DESC,
			COALESCE(cardinality(s.related_vote_ids), 0) DESC,
			s.sitting_date DESC,
			s.intervention_seq ASC NULLS LAST`)
	if err != nil && postgres.IsOptionalRankingSchemaError(err) {
		rows, err = conn.Query(ctx, `
			SELECT
				s.intervention_id,
				EXTRACT(YEAR FROM s.sitting_date)::int AS year,
				s.sitting_date,
				COALESCE(s.speaker_name, ''),
				COALESCE(s.subject_title, ''),
				COALESCE(s.content, ''),
				s.member_id,
				s.source_url
			FROM speeches s
			WHERE s.sitting_date IS NOT NULL
				AND COALESCE(s.content, '') <> ''
			ORDER BY
				EXTRACT(MONTH FROM s.sitting_date)::int,
				EXTRACT(DAY FROM s.sitting_date)::int,
				s.sitting_date DESC,
				s.intervention_seq ASC NULLS LAST`)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]usecase.OnThisDayItem, 0)
	for rows.Next() {
		item, err := postgres.ScanSpeechItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func writeJSON(path string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(value)
}
