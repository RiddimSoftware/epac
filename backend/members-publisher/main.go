// members-publisher emits S3-ready JSON artifacts from the members table.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/jackc/pgx/v5"
)

const memberSourceURL = "https://www.ourcommons.ca/members/en"

type Member struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Riding    string `json:"riding,omitempty"`
	Province  string `json:"province,omitempty"`
	Party     string `json:"party,omitempty"`
	SourceURL string `json:"source_url,omitempty"`
}

type MembersResponse struct {
	Members []Member `json:"members"`
}

func main() {
	output := flag.String("output", "../../build/artifacts/members", "artifact output directory")
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

	members, err := readMembers(ctx, conn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read members: %v\n", err)
		os.Exit(1)
	}
	if err := writeArtifacts(*output, members); err != nil {
		fmt.Fprintf(os.Stderr, "write artifacts: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published %d member records\n", len(members))
}

func readMembers(ctx context.Context, conn *pgx.Conn) ([]Member, error) {
	rows, err := conn.Query(ctx, `
		SELECT person_id, first_name, last_name, constituency, province, caucus
		FROM members
		ORDER BY
			CASE WHEN to_date IS NULL THEN 0 ELSE 1 END,
			last_name,
			first_name,
			person_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	members := make([]Member, 0)
	for rows.Next() {
		var id, firstName, lastName, riding, province, party string
		if err := rows.Scan(&id, &firstName, &lastName, &riding, &province, &party); err != nil {
			return nil, err
		}
		name := strings.TrimSpace(firstName + " " + lastName)
		members = append(members, Member{
			ID:        id,
			Name:      name,
			Riding:    riding,
			Province:  provinceCode(province),
			Party:     party,
			SourceURL: memberSourceURL,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return members, nil
}

func provinceCode(name string) string {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "alberta":
		return "AB"
	case "british columbia":
		return "BC"
	case "manitoba":
		return "MB"
	case "new brunswick":
		return "NB"
	case "newfoundland and labrador":
		return "NL"
	case "northwest territories":
		return "NT"
	case "nova scotia":
		return "NS"
	case "nunavut":
		return "NU"
	case "ontario":
		return "ON"
	case "prince edward island":
		return "PE"
	case "quebec":
		return "QC"
	case "saskatchewan":
		return "SK"
	case "yukon":
		return "YT"
	default:
		return strings.TrimSpace(name)
	}
}

func writeArtifacts(output string, members []Member) error {
	resp := MembersResponse{Members: members}
	if err := writeJSON(filepath.Join(output, "v1", "all.json"), resp); err != nil {
		return err
	}
	for _, member := range members {
		if strings.TrimSpace(member.ID) == "" {
			continue
		}
		if err := writeJSON(filepath.Join(output, "v1", "by-id", member.ID+".json"), member); err != nil {
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
