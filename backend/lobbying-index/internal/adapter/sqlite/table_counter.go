package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	_ "modernc.org/sqlite"
)

func CountTables(ctx context.Context, databasePath string) (map[string]int, error) {
	path := strings.TrimSpace(databasePath)
	if path == "" {
		path = DefaultDatabasePath
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open sqlite for table counts: %w", err)
	}
	defer db.Close()

	rows, err := db.QueryContext(ctx, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
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
		// Names come from sqlite_master (not user input), so dynamic SQL is safe here.
		if err := db.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+name).Scan(&count); err != nil { //nolint:gosec
			counts[name] = -1
			continue
		}
		counts[name] = count
	}
	return counts, nil
}
