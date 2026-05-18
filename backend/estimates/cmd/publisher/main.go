// estimates publisher emits S3-ready Main Estimates artifacts.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"epac/estimates/internal/adapter/postgres"
	"epac/estimates/internal/usecase"
)

func main() {
	output := flag.String("output", "../../../build/artifacts/estimates", "artifact output directory")
	databaseURL := flag.String("database-url", os.Getenv("DATABASE_URL"), "Postgres connection string")
	flag.Parse()

	if strings.TrimSpace(*databaseURL) == "" {
		fmt.Fprintln(os.Stderr, "DATABASE_URL is required")
		os.Exit(1)
	}

	ctx := context.Background()
	conn, err := postgres.ConnectWithURL(ctx, *databaseURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	estimates, err := usecase.NewGet(postgres.NewEstimatesRepository(conn)).Execute(ctx, usecase.EstimatesFilter{All: true})
	if err != nil {
		fmt.Fprintf(os.Stderr, "read estimates: %v\n", err)
		os.Exit(1)
	}
	if err := writeArtifacts(*output, estimates); err != nil {
		fmt.Fprintf(os.Stderr, "write artifacts: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published %d estimate records\n", len(estimates))
}

func writeArtifacts(output string, estimates []usecase.Estimate) error {
	if err := writeJSON(filepath.Join(output, "v1", "all.json"), usecase.EstimatesResponse{Estimates: estimates}); err != nil {
		return err
	}
	byOrg := map[int][]usecase.Estimate{}
	for _, estimate := range estimates {
		byOrg[estimate.OrganizationID] = append(byOrg[estimate.OrganizationID], estimate)
	}
	orgIDs := make([]int, 0, len(byOrg))
	for orgID := range byOrg {
		orgIDs = append(orgIDs, orgID)
	}
	sort.Ints(orgIDs)
	for _, orgID := range orgIDs {
		if err := writeJSON(filepath.Join(output, "v1", "by-org", fmt.Sprintf("%d.json", orgID)), usecase.EstimatesResponse{Estimates: byOrg[orgID]}); err != nil {
			return err
		}
	}
	return nil
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
