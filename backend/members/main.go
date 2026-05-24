// members Lambda — GET /api/v1/members
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"epac/observability"
	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const membersArtifactKey = "members/v1/all.json"

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
	data, err := store.Get(ctx, membersArtifactKey)
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
