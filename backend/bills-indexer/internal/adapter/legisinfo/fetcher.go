package legisinfo

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"epac/bills-indexer/internal/domain"
)

const (
	defaultBaseURL   = "https://www.parl.ca"
	defaultUserAgent = "epac-bills-indexer/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

type Fetcher struct {
	client    *http.Client
	baseURL   string
	userAgent string
	maxBills  int
}

type Option func(*Fetcher)

func WithHTTPClient(client *http.Client) Option {
	return func(f *Fetcher) {
		if client != nil {
			f.client = client
		}
	}
}

func WithBaseURL(baseURL string) Option {
	return func(f *Fetcher) {
		if strings.TrimSpace(baseURL) != "" {
			f.baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
		}
	}
}

func WithUserAgent(userAgent string) Option {
	return func(f *Fetcher) {
		if strings.TrimSpace(userAgent) != "" {
			f.userAgent = strings.TrimSpace(userAgent)
		}
	}
}

func WithMaxBills(max int) Option {
	return func(f *Fetcher) {
		if max > 0 {
			f.maxBills = max
		}
	}
}

func NewFetcher(opts ...Option) *Fetcher {
	f := &Fetcher{
		client:    &http.Client{Timeout: 45 * time.Second},
		baseURL:   defaultBaseURL,
		userAgent: defaultUserAgent,
	}
	for _, opt := range opts {
		opt(f)
	}
	return f
}

func (f *Fetcher) FetchBills(ctx context.Context, session domain.Session) (domain.Batch, error) {
	listURL := fmt.Sprintf("%s/legisinfo/en/bills/json?parlsession=%d-%d&load=yes", f.baseURL, session.ParliamentNumber, session.SessionNumber)
	var list []billListJSON
	if err := f.getJSON(ctx, listURL, &list); err != nil {
		return domain.Batch{}, err
	}
	if f.maxBills > 0 && len(list) > f.maxBills {
		list = list[:f.maxBills]
	}

	bills := make([]domain.Bill, 0, len(list))
	for _, item := range list {
		number := firstNonEmpty(item.BillNumberFormatted, item.NumberCode)
		if strings.TrimSpace(number) == "" {
			continue
		}
		detail, err := f.fetchDetail(ctx, session, number)
		if err != nil {
			return domain.Batch{}, fmt.Errorf("fetch bill %s detail: %w", number, err)
		}
		bill := detail.toDomain(f.baseURL, item)
		bills = append(bills, bill)
	}
	return domain.Batch{Bills: bills}, nil
}

func (f *Fetcher) fetchDetail(ctx context.Context, session domain.Session, number string) (billDetailJSON, error) {
	detailURL := fmt.Sprintf("%s/legisinfo/en/bill/%d-%d/%s/json", f.baseURL, session.ParliamentNumber, session.SessionNumber, strings.ToLower(number))
	var details []billDetailJSON
	if err := f.getJSON(ctx, detailURL, &details); err != nil {
		return billDetailJSON{}, err
	}
	if len(details) == 0 {
		return billDetailJSON{}, fmt.Errorf("empty detail response")
	}
	if strings.TrimSpace(details[0].NumberCode) == "" {
		details[0].NumberCode = number
	}
	details[0].detailURL = strings.TrimSuffix(detailURL, "/json")
	details[0].rawJSON = mustJSON(details[0])
	details[0].versions = f.enrichVersions(ctx, session, details[0].NumberCode, details[0].Publications)
	return details[0], nil
}

func (f *Fetcher) enrichVersions(ctx context.Context, session domain.Session, number string, pubs []publicationJSON) []domain.BillVersion {
	versions := make([]domain.BillVersion, 0, len(pubs))
	for i, pub := range pubs {
		stage := firstNonEmpty(pub.PublicationTypeNameEn, pub.PublicationTypeName)
		slug := publicationSlug(stage)
		htmlURL := fmt.Sprintf("%s/DocumentViewer/en/%d-%d/bill/%s/%s", f.baseURL, session.ParliamentNumber, session.SessionNumber, number, slug)
		version := domain.BillVersion{
			ID:            stableID(number, strconv.Itoa(pub.PublicationID), slug),
			PublicationID: strconv.Itoa(pub.PublicationID),
			Stage:         stage,
			StageSlug:     slug,
			HTMLURL:       htmlURL,
			Source:        "LEGISinfo publication",
			SortOrder:     i + 1,
		}
		xmlURL, pdfURL := f.fetchDocumentLinks(ctx, htmlURL)
		version.XMLURL = xmlURL
		version.PDFURL = pdfURL
		versions = append(versions, version)
	}
	return versions
}

func (f *Fetcher) fetchDocumentLinks(ctx context.Context, pageURL string) (string, string) {
	body, err := f.getBytes(ctx, pageURL, "text/html")
	if err != nil {
		return "", ""
	}
	base, _ := url.Parse(pageURL)
	var xmlURL, pdfURL string
	for _, match := range hrefPattern.FindAllSubmatch(body, -1) {
		href := html.UnescapeString(string(match[1]))
		lower := strings.ToLower(href)
		switch {
		case xmlURL == "" && strings.HasSuffix(lowerURLPath(lower), ".xml"):
			xmlURL = resolveURL(base, href)
		case pdfURL == "" && strings.HasSuffix(lowerURLPath(lower), ".pdf"):
			pdfURL = resolveURL(base, href)
		}
		if xmlURL != "" && pdfURL != "" {
			break
		}
	}
	return xmlURL, pdfURL
}

func (f *Fetcher) getJSON(ctx context.Context, target string, out any) error {
	body, err := f.getBytes(ctx, target, "application/json")
	if err != nil {
		return err
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("decode %s: %w", target, err)
	}
	return nil
}

func (f *Fetcher) getBytes(ctx context.Context, target, accept string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, fmt.Errorf("build request %s: %w", target, err)
	}
	req.Header.Set("Accept", accept)
	req.Header.Set("User-Agent", f.userAgent)
	resp, err := f.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch %s: %w", target, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s returned HTTP %d", target, resp.StatusCode)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", target, err)
	}
	return data, nil
}

type billListJSON struct {
	BillId                           int    `json:"BillId"`
	NumberCode                       string `json:"NumberCode"`
	BillNumberFormatted              string `json:"BillNumberFormatted"`
	LongTitleEn                      string `json:"LongTitleEn"`
	ShortTitleEn                     string `json:"ShortTitleEn"`
	CurrentStatusEn                  string `json:"CurrentStatusEn"`
	LatestCompletedMajorStageEn      string `json:"LatestCompletedMajorStageEn"`
	BillTypeEn                       string `json:"BillTypeEn"`
	SponsorId                        int    `json:"SponsorId"`
	SponsorEn                        string `json:"SponsorEn"`
	ParliamentNumber                 int    `json:"ParliamentNumber"`
	SessionNumber                    int    `json:"SessionNumber"`
	PassedHouseFirstReadingDateTime  string `json:"PassedHouseFirstReadingDateTime"`
	PassedSenateFirstReadingDateTime string `json:"PassedSenateFirstReadingDateTime"`
}

type billDetailJSON struct {
	ID                                int                `json:"Id"`
	NumberCode                        string             `json:"NumberCode"`
	LongTitleEn                       string             `json:"LongTitleEn"`
	LongTitle                         string             `json:"LongTitle"`
	ShortTitleEn                      string             `json:"ShortTitleEn"`
	ShortTitle                        string             `json:"ShortTitle"`
	StatusNameEn                      string             `json:"StatusNameEn"`
	StatusName                        string             `json:"StatusName"`
	OngoingStageNameEn                string             `json:"OngoingStageNameEn"`
	LatestCompletedMajorStageNameEn   string             `json:"LatestCompletedMajorStageNameEn"`
	SponsorPersonID                   int                `json:"SponsorPersonId"`
	SponsorPersonName                 string             `json:"SponsorPersonName"`
	BillDocumentTypeNameEn            string             `json:"BillDocumentTypeNameEn"`
	ParliamentNumber                  int                `json:"ParliamentNumber"`
	SessionNumber                     int                `json:"SessionNumber"`
	PassedHouseFirstReadingDateTime   string             `json:"PassedHouseFirstReadingDateTime"`
	PassedSenateFirstReadingDateTime  string             `json:"PassedSenateFirstReadingDateTime"`
	LatestBillEventNumberOfAmendments int                `json:"LatestBillEventNumberOfAmendments"`
	LatestBillEventAmendmentNoteID    any                `json:"LatestBillEventAmendmentNoteId"`
	BillStages                        stagesJSON         `json:"BillStages"`
	Publications                      []publicationJSON  `json:"Publications"`
	WebReferences                     []webReferenceJSON `json:"WebReferences"`
	detailURL                         string
	rawJSON                           string
	versions                          []domain.BillVersion
}

type stagesJSON struct {
	HouseBillStages  []stageJSON `json:"HouseBillStages"`
	SenateBillStages []stageJSON `json:"SenateBillStages"`
}

type stageJSON struct {
	BillStageID             int         `json:"BillStageId"`
	BillStageNameEn         string      `json:"BillStageNameEn"`
	BillStageName           string      `json:"BillStageName"`
	ChamberOrganizationID   int         `json:"ChamberOrganizationId"`
	StateNameEn             string      `json:"StateNameEn"`
	StateName               string      `json:"StateName"`
	StateAsOfDate           string      `json:"StateAsOfDate"`
	SignificantEvents       []eventJSON `json:"SignificantEvents"`
	LastStageEventStartDate string      `json:"LastStageEventStartDateTime"`
}

type eventJSON struct {
	EventTypeID        int    `json:"EventTypeId"`
	EventNameEn        string `json:"EventNameEn"`
	EventName          string `json:"EventName"`
	EventDateTime      string `json:"EventDateTime"`
	MeetingNumber      string `json:"MeetingNumber"`
	AmendmentNoteID    any    `json:"AmendmentNoteId"`
	NumberOfAmendments int    `json:"NumberOfAmendments"`
}

type publicationJSON struct {
	PublicationID         int    `json:"PublicationId"`
	PublicationTypeNameEn string `json:"PublicationTypeNameEn"`
	PublicationTypeName   string `json:"PublicationTypeName"`
}

type webReferenceJSON struct {
	TitleEn                string `json:"TitleEn"`
	Title                  string `json:"Title"`
	WebReferenceTypeNameEn string `json:"WebReferenceTypeNameEn"`
	WebReferenceTypeName   string `json:"WebReferenceTypeName"`
	URL                    string `json:"Url"`
	URLEn                  string `json:"UrlEn"`
}

func (d billDetailJSON) toDomain(baseURL string, list billListJSON) domain.Bill {
	id := strconv.Itoa(firstInt(d.ID, list.BillId))
	number := firstNonEmpty(d.NumberCode, list.BillNumberFormatted, list.NumberCode)
	bill := domain.Bill{
		ID:           id,
		Number:       number,
		Title:        firstNonEmpty(d.LongTitleEn, d.LongTitle, list.LongTitleEn),
		ShortTitle:   firstNonEmpty(d.ShortTitleEn, d.ShortTitle, list.ShortTitleEn),
		SponsorID:    strconv.Itoa(firstInt(d.SponsorPersonID, list.SponsorId)),
		SponsorName:  firstNonEmpty(d.SponsorPersonName, list.SponsorEn),
		Status:       firstNonEmpty(d.StatusNameEn, d.StatusName, list.CurrentStatusEn),
		CurrentStage: firstNonEmpty(d.OngoingStageNameEn, d.LatestCompletedMajorStageNameEn, list.LatestCompletedMajorStageEn),
		IntroducedOn: firstNonEmpty(dateOnly(d.PassedHouseFirstReadingDateTime), dateOnly(d.PassedSenateFirstReadingDateTime), dateOnly(list.PassedHouseFirstReadingDateTime), dateOnly(list.PassedSenateFirstReadingDateTime)),
		SourceURL:    d.detailURL,
		BillType:     firstNonEmpty(d.BillDocumentTypeNameEn, list.BillTypeEn),
		Parliament:   firstInt(d.ParliamentNumber, list.ParliamentNumber),
		Session:      firstInt(d.SessionNumber, list.SessionNumber),
		LegisInfoURL: d.detailURL,
		RawJSON:      d.rawJSON,
		Versions:     d.versions,
	}
	bill.Stages, bill.Events, bill.Amendments = d.extractStagesAndEvents()
	bill.RelatedLinks, bill.PBOCostings = d.extractReferences(baseURL)
	bill.Diffs = buildDiffs(number, bill.Versions, d.detailURL)
	if len(bill.Amendments) == 0 && d.LatestBillEventNumberOfAmendments > 0 {
		noteID := anyString(d.LatestBillEventAmendmentNoteID)
		bill.Amendments = append(bill.Amendments, domain.Amendment{
			ID:              stableID(number, "latest", noteID, strconv.Itoa(d.LatestBillEventNumberOfAmendments)),
			AmendmentNoteID: noteID,
			AmendmentCount:  d.LatestBillEventNumberOfAmendments,
			SourceURL:       d.detailURL,
		})
	}
	return bill
}

func (d billDetailJSON) extractStagesAndEvents() ([]domain.BillStage, []domain.BillEvent, []domain.Amendment) {
	all := append([]stageJSON{}, d.BillStages.HouseBillStages...)
	all = append(all, d.BillStages.SenateBillStages...)
	stages := make([]domain.BillStage, 0, len(all))
	events := make([]domain.BillEvent, 0)
	amendments := make([]domain.Amendment, 0)
	for i, stage := range all {
		chamber := chamberName(stage.ChamberOrganizationID)
		stageID := strconv.Itoa(stage.BillStageID)
		stageName := firstNonEmpty(stage.BillStageNameEn, stage.BillStageName)
		completed := strings.EqualFold(firstNonEmpty(stage.StateNameEn, stage.StateName), "Completed")
		stages = append(stages, domain.BillStage{
			ID:            stageID,
			Name:          stageName,
			Chamber:       chamber,
			State:         firstNonEmpty(stage.StateNameEn, stage.StateName),
			CompletedDate: firstNonEmpty(dateOnly(stage.StateAsOfDate), dateOnly(stage.LastStageEventStartDate)),
			SortOrder:     i + 1,
			IsCompleted:   completed,
		})
		for j, event := range stage.SignificantEvents {
			eventID := stableID(d.NumberCode, stageID, strconv.Itoa(event.EventTypeID), event.EventDateTime, strconv.Itoa(j))
			noteID := anyString(event.AmendmentNoteID)
			count := event.NumberOfAmendments
			if noteID != "" && count == 0 {
				count = 1
			}
			events = append(events, domain.BillEvent{
				ID:              eventID,
				StageID:         stageID,
				StageName:       stageName,
				Name:            firstNonEmpty(event.EventNameEn, event.EventName),
				Chamber:         chamber,
				EventDate:       dateOnly(event.EventDateTime),
				MeetingNumber:   event.MeetingNumber,
				AmendmentCount:  count,
				AmendmentNoteID: noteID,
			})
			if count > 0 || noteID != "" {
				amendments = append(amendments, domain.Amendment{
					ID:              stableID("amendment", eventID, noteID, strconv.Itoa(count)),
					EventID:         eventID,
					StageName:       stageName,
					AmendmentNoteID: noteID,
					AmendmentCount:  count,
					SourceURL:       d.detailURL,
				})
			}
		}
	}
	return stages, events, amendments
}

func (d billDetailJSON) extractReferences(baseURL string) ([]domain.RelatedLink, []domain.PBOCosting) {
	links := make([]domain.RelatedLink, 0, len(d.WebReferences))
	costings := make([]domain.PBOCosting, 0)
	base, _ := url.Parse(baseURL)
	for i, ref := range d.WebReferences {
		title := firstNonEmpty(ref.TitleEn, ref.Title)
		refType := firstNonEmpty(ref.WebReferenceTypeNameEn, ref.WebReferenceTypeName)
		refURL := resolveURL(base, firstNonEmpty(ref.URLEn, ref.URL))
		if strings.TrimSpace(refURL) == "" {
			continue
		}
		link := domain.RelatedLink{
			ID:     stableID(d.NumberCode, refURL, strconv.Itoa(i)),
			Title:  title,
			URL:    refURL,
			Type:   refType,
			Source: "LEGISinfo web reference",
		}
		links = append(links, link)
		if isPBOCosting(title, refType, refURL) {
			costings = append(costings, domain.PBOCosting{
				ID:     stableID("pbo", d.NumberCode, refURL),
				Title:  title,
				URL:    refURL,
				Source: refType,
			})
		}
	}
	return links, costings
}

func buildDiffs(number string, versions []domain.BillVersion, detailURL string) []domain.BillDiff {
	if len(versions) < 2 {
		return nil
	}
	ordered := append([]domain.BillVersion(nil), versions...)
	sort.SliceStable(ordered, func(i, j int) bool { return ordered[i].SortOrder < ordered[j].SortOrder })
	diffs := make([]domain.BillDiff, 0, len(ordered)-1)
	for i := 1; i < len(ordered); i++ {
		diffs = append(diffs, domain.BillDiff{
			ID:            stableID("diff", number, ordered[i-1].ID, ordered[i].ID),
			FromVersionID: ordered[i-1].ID,
			ToVersionID:   ordered[i].ID,
			SourceURL:     detailURL,
		})
	}
	return diffs
}

func publicationSlug(stage string) string {
	normalized := strings.ToLower(strings.TrimSpace(stage))
	normalized = strings.ReplaceAll(normalized, "'", "")
	normalized = nonSlugPattern.ReplaceAllString(normalized, "-")
	normalized = strings.Trim(normalized, "-")
	if normalized == "" {
		return "latest"
	}
	return normalized
}

func dateOnly(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02T15:04:05.999", "2006-01-02T15:04:05", "2006-01-02"} {
		if parsed, err := time.Parse(layout, raw); err == nil {
			return parsed.Format("2006-01-02")
		}
	}
	if len(raw) >= 10 {
		return raw[:10]
	}
	return raw
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}

func firstInt(values ...int) int {
	for _, value := range values {
		if value != 0 {
			return value
		}
	}
	return 0
}

func anyString(value any) string {
	switch v := value.(type) {
	case nil:
		return ""
	case string:
		return strings.TrimSpace(v)
	case float64:
		if v == 0 {
			return ""
		}
		return strconv.FormatInt(int64(v), 10)
	case int:
		if v == 0 {
			return ""
		}
		return strconv.Itoa(v)
	default:
		return strings.TrimSpace(fmt.Sprint(v))
	}
}

func chamberName(id int) string {
	switch id {
	case 1:
		return "House of Commons"
	case 2:
		return "Senate"
	default:
		return ""
	}
}

func isPBOCosting(values ...string) bool {
	joined := strings.ToLower(strings.Join(values, " "))
	return strings.Contains(joined, "pbo") ||
		strings.Contains(joined, "parliamentary budget officer") ||
		strings.Contains(joined, "budget officer") ||
		strings.Contains(joined, "costing")
}

func stableID(parts ...string) string {
	filtered := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			filtered = append(filtered, part)
		}
	}
	id := strings.ToLower(strings.Join(filtered, "-"))
	id = nonSlugPattern.ReplaceAllString(id, "-")
	id = strings.Trim(id, "-")
	if id == "" {
		return "unknown"
	}
	return id
}

func mustJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	return string(data)
}

func resolveURL(base *url.URL, href string) string {
	parsed, err := url.Parse(strings.TrimSpace(href))
	if err != nil {
		return strings.TrimSpace(href)
	}
	return base.ResolveReference(parsed).String()
}

func lowerURLPath(raw string) string {
	if parsed, err := url.Parse(raw); err == nil {
		return strings.ToLower(parsed.Path)
	}
	return strings.ToLower(raw)
}

var (
	nonSlugPattern = regexp.MustCompile(`[^a-z0-9]+`)
	hrefPattern    = regexp.MustCompile(`(?i)href=["']([^"']+)["']`)
)
