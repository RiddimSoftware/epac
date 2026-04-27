//go:build ignore

package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run test_conn.go <connection_string>")
		os.Exit(1)
	}

	connStr := os.Args[1]
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		fmt.Printf("Connection failed: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	var val int
	err = conn.QueryRow(ctx, "SELECT 1").Scan(&val)
	if err != nil {
		fmt.Printf("Query failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Connection successful! Query returned: %d\n", val)
}

