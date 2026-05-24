package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
	dropTables := flag.Bool("drop", false, "drop tables instead of truncating")
	flag.Parse()

	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		fmt.Println("Error: DATABASE_URL environment variable is not set")
		return
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connect to database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	if *dropTables {
		fmt.Println("Dropping tables...")
		_, err = conn.Exec(ctx, "DROP TABLE IF EXISTS members, speeches;")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error dropping tables: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Tables dropped successfully.")
	} else {
		fmt.Println("Truncating tables...")
		_, err = conn.Exec(ctx, "TRUNCATE TABLE members, speeches;")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error truncating tables: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Tables truncated successfully.")
	}
}
