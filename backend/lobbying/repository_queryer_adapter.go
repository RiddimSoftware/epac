package main

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"epac/lobbying/repository"
)

func newLobbyingQueryer(conn *pgx.Conn) repository.Queryer {
	return &lobbyingQueryer{conn: conn}
}

type lobbyingQueryer struct {
	conn *pgx.Conn
}

func (q *lobbyingQueryer) Exec(ctx context.Context, query string, args ...any) (repository.QueryExecResult, error) {
	tag, err := q.conn.Exec(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	return commandTagResult{tag: tag}, nil
}

func (q *lobbyingQueryer) Query(ctx context.Context, query string, args ...any) (repository.QueryRows, error) {
	rows, err := q.conn.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	return &pgxRows{rows: rows}, nil
}

func (q *lobbyingQueryer) QueryRow(ctx context.Context, query string, args ...any) repository.QueryRow {
	return pgxRow{row: q.conn.QueryRow(ctx, query, args...)}
}

type commandTagResult struct {
	tag pgconn.CommandTag
}

func (r commandTagResult) RowsAffected() (int64, error) {
	return int64(r.tag.RowsAffected()), nil
}

type pgxRows struct {
	rows pgx.Rows
}

func (r *pgxRows) Close() {
	r.rows.Close()
}

func (r *pgxRows) Next() bool {
	return r.rows.Next()
}

func (r *pgxRows) Scan(dest ...any) error {
	return r.rows.Scan(dest...)
}

func (r *pgxRows) Err() error {
	return r.rows.Err()
}

type pgxRow struct {
	row pgx.Row
}

func (r pgxRow) Scan(dest ...any) error {
	return r.row.Scan(dest...)
}
