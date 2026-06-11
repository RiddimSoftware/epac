// members Lambda — GET /api/v1/members
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"

	"epac/observability"
	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	_ "modernc.org/sqlite"
)

const (
	membersSQLiteArtifactKey = "members/v1/index.sqlite"
	membersJSONArtifactKey   = "members/v1/all.json"
	sqliteReadOnlyDSN        = "file:%s?mode=ro&_pragma=query_only(1)"
)

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

var newArtifactStore = artifacts.NewFromEnv

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	resp, err := readMembers(ctx)
	if err != nil {
		status := http.StatusInternalServerError
		if artifacts.IsNotFound(err) {
			status = http.StatusNotFound
		}
		return jsonError(status, err.Error()), nil
	}

	province := strings.TrimSpace(req.QueryStringParameters["province"])
	party := strings.TrimSpace(req.QueryStringParameters["party"])
	resp.Members = filterMembers(resp.Members, province, party)

	body, err := json.Marshal(resp)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func readMembers(ctx context.Context) (MembersResponse, error) {
	store, err := newArtifactStore(ctx)
	if err != nil {
		return MembersResponse{}, err
	}
	data, err := store.Get(ctx, membersSQLiteArtifactKey)
	if err != nil {
		if artifacts.IsNotFound(err) {
			return readMembersJSON(ctx, store)
		}
		return MembersResponse{}, err
	}
	return readMembersSQLite(ctx, data)
}

func readMembersJSON(ctx context.Context, store artifacts.Store) (MembersResponse, error) {
	data, err := store.Get(ctx, membersJSONArtifactKey)
	if err != nil {
		return MembersResponse{}, err
	}
	var resp MembersResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return MembersResponse{}, err
	}
	if resp.Members == nil {
		resp.Members = []Member{}
	}
	return resp, nil
}

func readMembersSQLite(ctx context.Context, data []byte) (MembersResponse, error) {
	db, cleanup, err := openSQLiteArtifact(data, "epac-members-*.sqlite")
	if err != nil {
		return MembersResponse{}, err
	}
	defer cleanup()

	rows, err := db.QueryContext(ctx, `
		SELECT id, name, riding, province, party, source_url
		FROM members
		ORDER BY rowid`)
	if err != nil {
		return MembersResponse{}, fmt.Errorf("query members sqlite artifact: %w", err)
	}
	defer rows.Close()

	members := make([]Member, 0)
	for rows.Next() {
		var member Member
		if err := rows.Scan(&member.ID, &member.Name, &member.Riding, &member.Province, &member.Party, &member.SourceURL); err != nil {
			return MembersResponse{}, fmt.Errorf("scan members sqlite artifact: %w", err)
		}
		members = append(members, member)
	}
	if err := rows.Err(); err != nil {
		return MembersResponse{}, fmt.Errorf("iterate members sqlite artifact: %w", err)
	}
	if members == nil {
		members = []Member{}
	}
	return MembersResponse{Members: members}, nil
}

func openSQLiteArtifact(data []byte, tempPattern string) (*sql.DB, func(), error) {
	file, err := os.CreateTemp("", tempPattern)
	if err != nil {
		return nil, nil, fmt.Errorf("create sqlite artifact temp file: %w", err)
	}
	path := file.Name()
	cleanupFile := func() {
		_ = os.Remove(path)
	}
	if _, err := file.Write(data); err != nil {
		file.Close()
		cleanupFile()
		return nil, nil, fmt.Errorf("write sqlite artifact temp file: %w", err)
	}
	if err := file.Close(); err != nil {
		cleanupFile()
		return nil, nil, fmt.Errorf("close sqlite artifact temp file: %w", err)
	}

	db, err := sql.Open("sqlite", fmt.Sprintf(sqliteReadOnlyDSN, path))
	if err != nil {
		cleanupFile()
		return nil, nil, fmt.Errorf("open sqlite artifact: %w", err)
	}
	cleanup := func() {
		_ = db.Close()
		cleanupFile()
	}
	if err := db.Ping(); err != nil {
		cleanup()
		return nil, nil, fmt.Errorf("ping sqlite artifact: %w", err)
	}
	return db, cleanup, nil
}

func filterMembers(members []Member, province, party string) []Member {
	if province == "" && party == "" {
		return members
	}
	filtered := make([]Member, 0, len(members))
	for _, member := range members {
		if province != "" && !provinceMatches(member.Province, province) {
			continue
		}
		if party != "" && !strings.EqualFold(member.Party, party) {
			continue
		}
		filtered = append(filtered, member)
	}
	return filtered
}

func provinceMatches(memberProvince, filter string) bool {
	if strings.EqualFold(memberProvince, filter) {
		return true
	}
	return strings.EqualFold(memberProvince, provinceCode(filter))
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

func jsonResponse(status int, body []byte) events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": "public, max-age=300",
		},
		Body: string(body),
	}
}

func jsonError(status int, message string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return jsonResponse(status, body)
}

func main() {
	lambda.Start(observability.WrapAPIGateway("members", HandleRequest))
}
