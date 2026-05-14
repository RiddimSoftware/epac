# _testdb

A shared Go integration-test harness for epac backend Lambda handlers.

## Usage

This package spins up a connection to a test Postgres database, applies the real migrations in `backend/migrations/` sequentially, and provides helper functions to seed tables with fixtures.

### How to run locally

Ensure you have Docker running, then from the `backend/` directory:

```bash
make test-integration
```

This will:
1. Start a `postgres:16` instance via `docker-compose.test.yml`.
2. Set the `DATABASE_URL` environment variable.
3. Run `go test -tags=integration ./...`.

If you prefer to run a single test locally:
```bash
docker compose -f ../docker-compose.test.yml up -d
DATABASE_URL="postgresql://epac:epac@localhost:5432/epac_test?sslmode=disable" go test -tags=integration -run TestName ./...
```

### How CI runs the suite

CI spins up a Postgres 16 service using GitHub Actions' `services:` feature, effectively creating an identical environment to `docker-compose.test.yml`. Tests are invoked identically with `go test -tags=integration ./...` and the corresponding `DATABASE_URL`.

### Isolation Contract (BEGIN/ROLLBACK)

Every test must wrap its operations in a transaction and roll it back. This ensures tests are isolated and don't pollute the database for subsequent tests.

Use the `WithTx` helper, which yields a raw `*pgx.Conn` that has an active transaction. Since the transaction is started with raw `BEGIN`, you can pass the connection directly to handler functions that expect a `*pgx.Conn` object:

```go
func TestMyHandler(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		// Seed your fixtures using the connection
		_testdb.SeedSpeech(t, conn, "123", "Hello", "John", "mp-1", "Debate", nil)

		// Call your handler logic directly with the connection
		// myHandler(ctx, conn, ...)
	})
}
```

### Adding a fixture helper

To add a new fixture helper (e.g. `SeedPipelineHealth`), add a new function to `testdb.go`. Ensure it takes `t *testing.T` and `conn *pgx.Conn` so it uses the isolated transaction connection.
