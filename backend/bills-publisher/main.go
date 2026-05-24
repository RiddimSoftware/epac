// bills-publisher emits S3-ready bill artifacts from the public LEGISinfo feed.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const defaultLEGISinfoBase = "https://www.parl.ca/legisinfo/en/bills/json"

type BillStage struct {
	ID            string  `json:"id,omitempty"`
	Name          string  `json:"name,omitempty"`
	CompletedDate *string `json:"completed_date,omitempty"`
	IsCompleted   bool    `json:"is_completed"`
}

type Bill struct {
	ID           string      `json:"id"`
	Number       string      `json:"number"`
	Title        string      `json:"title"`
	SponsorName  string      `json:"sponsor_name,omitempty"`
	Status       string      `json:"status,omitempty"`
	CurrentStage string      `json:"current_stage,omitempty"`
	IntroducedOn *string     `json:"introduced_on,omitempty"`
	Stages       []BillStage `json:"stages,omitempty"`
	SourceURL    string      `json:"source_url,omitempty"`
	BillType     string      `json:"bill_type,omitempty"`
	Parliament   *int        `json:"parliament,omitempty"`
	Session      *int        `json:"session,omitempty"`
	LegisInfoURL string      `json:"legis_info_url,omitempty"`
}

type BillsResponse struct {
	Bills []Bill `json:"bills"`
}

type legisInfoBill struct {
	BillNumberFormatted               string `json:"BillNumberFormatted"`
	LongTitleEn                       string `json:"LongTitleEn"`
	ShortTitleEn                      string `json:"ShortTitleEn"`
	LatestCompletedMajorStageEn       string `json:"LatestCompletedMajorStageEn"`
	CurrentStatusEn                   string `json:"CurrentStatusEn"`
	BillTypeEn                        string `json:"BillTypeEn"`
	SponsorEn                         string `json:"SponsorEn"`
	OriginatingChamberID              int    `json:"OriginatingChamberId"`
	PassedHouseFirstReadingDateTime   string `json:"PassedHouseFirstReadingDateTime"`
	PassedHouseSecondReadingDateTime  string `json:"PassedHouseSecondReadingDateTime"`
	PassedHouseThirdReadingDateTime   string `json:"PassedHouseThirdReadingDateTime"`
	PassedSenateFirstReadingDateTime  string `json:"PassedSenateFirstReadingDateTime"`
	PassedSenateSecondReadingDateTime string `json:"PassedSenateSecondReadingDateTime"`
	PassedSenateThirdReadingDateTime  string `json:"PassedSenateThirdReadingDateTime"`
	ReceivedRoyalAssentDateTime       string `json:"ReceivedRoyalAssentDateTime"`
}

func main() {
	output := flag.String("output", "../../build/artifacts/bills", "artifact output directory")
	parliament := flag.Int("parliament", envInt("PARLIAMENT_NUM", 45), "Parliament number")
	session := flag.Int("session", envInt("SESSION_NUM", 1), "Session number")
	sourceBase := flag.String("source-url", envOrDefault("LEGISINFO_BILLS_URL", defaultLEGISinfoBase), "LEGISinfo bills JSON endpoint")
	flag.Parse()

	ctx := context.Background()
	raw, err := fetchLEGISinfoBills(ctx, http.DefaultClient, *sourceBase, *parliament, *session)
	if err != nil {
		fmt.Fprintf(os.Stderr, "fetch LEGISinfo bills: %v\n", err)
		os.Exit(1)
	}
	bills := make([]Bill, 0, len(raw))
	for _, item := range raw {
		bill, ok := mapBill(item, *parliament, *session)
		if ok {
			bills = append(bills, bill)
		}
	}
	sort.SliceStable(bills, func(i, j int) bool {
		left := dateValue(bills[i].IntroducedOn)
		right := dateValue(bills[j].IntroducedOn)
		if left.Equal(right) {
			return bills[i].Number < bills[j].Number
		}
		return left.After(right)
	})
	if err := writeArtifacts(*output, bills); err != nil {
		fmt.Fprintf(os.Stderr, "write artifacts: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published %d bill records\n", len(bills))
}

func fetchLEGISinfoBills(ctx context.Context, client *http.Client, baseURL string, parliament, session int) ([]legisInfoBill, error) {
	url := fmt.Sprintf("%s?parlsession=%d-%d&load=yes", strings.TrimRight(baseURL, "?"), parliament, session)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("LEGISinfo returned HTTP %d", resp.StatusCode)
	}
	var bills []legisInfoBill
	if err := json.NewDecoder(resp.Body).Decode(&bills); err != nil {
		return nil, err
	}
	return bills, nil
}

func mapBill(raw legisInfoBill, parliament, session int) (Bill, bool) {
	number := strings.TrimSpace(raw.BillNumberFormatted)
	if number == "" {
		return Bill{}, false
	}
	title := firstNonEmpty(raw.ShortTitleEn, raw.LongTitleEn)
	if title == "" {
		return Bill{}, false
	}
	houseFirst := parseDate(raw.PassedHouseFirstReadingDateTime)
	houseSecond := parseDate(raw.PassedHouseSecondReadingDateTime)
	houseThird := parseDate(raw.PassedHouseThirdReadingDateTime)
	senateFirst := parseDate(raw.PassedSenateFirstReadingDateTime)
	senateSecond := parseDate(raw.PassedSenateSecondReadingDateTime)
	senateThird := parseDate(raw.PassedSenateThirdReadingDateTime)
	royalAssent := parseDate(raw.ReceivedRoyalAssentDateTime)
	introduced := earliestDate(houseFirst, senateFirst)
	parl := parliament
	sess := session
	legisInfoURL := fmt.Sprintf("https://www.parl.ca/legisinfo/en/bill/%d-%d/%s", parliament, session, strings.ToLower(number))

	return Bill{
		ID:           number,
		Number:       number,
		Title:        title,
		SponsorName:  strings.TrimSpace(raw.SponsorEn),
		Status:       billStatus(raw),
		CurrentStage: firstNonEmpty(raw.LatestCompletedMajorStageEn, raw.CurrentStatusEn),
		IntroducedOn: introduced,
		Stages:       stages(number, raw.OriginatingChamberID, houseFirst, houseSecond, houseThird, senateFirst, senateSecond, senateThird, royalAssent),
		SourceURL:    legisInfoURL,
		BillType:     billType(raw.BillTypeEn),
		Parliament:   &parl,
		Session:      &sess,
		LegisInfoURL: legisInfoURL,
	}, true
}

func stages(number string, chamberID int, houseFirst, houseSecond, houseThird, senateFirst, senateSecond, senateThird, royalAssent *string) []BillStage {
	houseStages := []BillStage{
		stage(number+"-h1", "House First Reading", houseFirst),
		stage(number+"-h2", "House Second Reading", houseSecond),
		stage(number+"-h3", "House Third Reading", houseThird),
	}
	senateStages := []BillStage{
		stage(number+"-s1", "Senate First Reading", senateFirst),
		stage(number+"-s2", "Senate Second Reading", senateSecond),
		stage(number+"-s3", "Senate Third Reading", senateThird),
	}
	royalAssentStage := stage(number+"-ra", "Royal Assent", royalAssent)
	if chamberID == 2 {
		return append(append(senateStages, houseStages...), royalAssentStage)
	}
	return append(append(houseStages, senateStages...), royalAssentStage)
}

func stage(id, name string, completedDate *string) BillStage {
	return BillStage{
		ID:            id,
		Name:          name,
		CompletedDate: completedDate,
		IsCompleted:   completedDate != nil,
	}
}

func billStatus(raw legisInfoBill) string {
	statusLower := strings.ToLower(raw.CurrentStatusEn)
	if raw.ReceivedRoyalAssentDateTime != "" || strings.Contains(statusLower, "royal assent") {
		return "RoyalAssent"
	}
	if strings.Contains(statusLower, "defeat") {
		return "Defeated"
	}
	return "InProgress"
}

func billType(raw string) string {
	value := strings.ToLower(raw)
	switch {
	case strings.Contains(value, "house government"):
		return "HouseGovernment"
	case strings.Contains(value, "private member"):
		return "PrivateMember"
	case strings.Contains(value, "senate government"):
		return "SenateGovernment"
	case strings.Contains(value, "senate public"):
		return "SenatePublic"
	case strings.Contains(value, "senate private"):
		return "SenatePrivate"
	default:
		return "Unknown"
	}
}

func writeArtifacts(output string, bills []Bill) error {
	resp := BillsResponse{Bills: bills}
	if err := writeJSON(filepath.Join(output, "v1", "all.json"), resp); err != nil {
		return err
	}
	for _, bill := range bills {
		if strings.TrimSpace(bill.Number) == "" {
			continue
		}
		if err := writeJSON(filepath.Join(output, "v1", "by-id", bill.Number+".json"), bill); err != nil {
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

func parseDate(raw string) *string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	formats := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05",
		"2006-01-02",
	}
	for _, format := range formats {
		if parsed, err := time.Parse(format, raw); err == nil {
			day := parsed.Format("2006-01-02")
			return &day
		}
	}
	return nil
}

func earliestDate(values ...*string) *string {
	var best *time.Time
	for _, value := range values {
		if value == nil {
			continue
		}
		parsed, err := time.Parse("2006-01-02", *value)
		if err != nil {
			continue
		}
		if best == nil || parsed.Before(*best) {
			copy := parsed
			best = &copy
		}
	}
	if best == nil {
		return nil
	}
	day := best.Format("2006-01-02")
	return &day
}

func dateValue(value *string) time.Time {
	if value == nil {
		return time.Time{}
	}
	parsed, err := time.Parse("2006-01-02", *value)
	if err != nil {
		return time.Time{}
	}
	return parsed
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func envInt(name string, fallback int) int {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		var parsed int
		if _, err := fmt.Sscanf(value, "%d", &parsed); err == nil && parsed > 0 {
			return parsed
		}
	}
	return fallback
}

func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
