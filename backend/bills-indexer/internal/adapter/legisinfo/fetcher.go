package legisinfo

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
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
	logger    func(map[string]any)
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

func WithLogger(logger func(map[string]any)) Option {
	return func(f *Fetcher) {
		f.logger = logger
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

	if f.logger != nil {
		f.logger(map[string]any{
			"pipeline": "bills-indexer",
			"event":    "fetch_started",
			"count":    len(list),
		})
	}

	bills := make([]domain.Bill, 0, len(list))
	for i, item := range list {
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

		if f.logger != nil && (i+1)%10 == 0 {
			f.logger(map[string]any{
				"pipeline": "bills-indexer",
				"event":    "fetch_progress",
				"current":  i + 1,
				"total":    len(list),
			})
		}
	}

	if f.logger != nil {
		f.logger(map[string]any{
			"pipeline": "bills-indexer",
			"event":    "fetch_completed",
			"count":    len(bills),
		})
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

		if xmlURL != "" {
			xmlData, err := f.getBytes(ctx, xmlURL, "text/xml")
			if err == nil {
				hash := computeSHA256(xmlData)
				version.TextHash = &hash
				version.TextSourceURL = &xmlURL

				sections, err := parseBillXML(xmlData)
				if err == nil {
					version.Sections = sections
				}
			}
		}

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
	BillStageID                      int                    `json:"BillStageId"`
	BillStageNameEn                  string                 `json:"BillStageNameEn"`
	BillStageName                    string                 `json:"BillStageName"`
	ChamberOrganizationID            int                    `json:"ChamberOrganizationId"`
	ParliamentNumber                 int                    `json:"ParliamentNumber"`
	SessionNumber                    int                    `json:"SessionNumber"`
	StateNameEn                      string                 `json:"StateNameEn"`
	StateName                        string                 `json:"StateName"`
	StateAsOfDate                    string                 `json:"StateAsOfDate"`
	Committee                        *committeeJSON         `json:"Committee"`
	CommitteeMeetings                []committeeMeetingJSON `json:"CommitteeMeetings"`
	SignificantEvents                []eventJSON            `json:"SignificantEvents"`
	LastStageEventStartDate          string                 `json:"LastStageEventStartDateTime"`
	ContainsReferralToCommitteeEvent bool                   `json:"ContainsReferralToCommitteeEvent"`
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

type committeeJSON struct {
	CommitteeOrganizationID   int    `json:"CommitteeOrganizationId"`
	CommitteeNameEn           string `json:"CommitteeNameEn"`
	CommitteeName             string `json:"CommitteeName"`
	CommitteeAcronym          string `json:"CommitteeAcronym"`
	IsHouseOfCommonsCommittee bool   `json:"IsHouseOfCommonsCommittee"`
	IsSenateCommittee         bool   `json:"IsSenateCommittee"`
	IsJointCommittee          bool   `json:"IsJointCommittee"`
}

type committeeMeetingJSON struct {
	CommitteeOrganizationID int    `json:"CommitteeOrganizationId"`
	CommitteeNameEn         string `json:"CommitteeNameEn"`
	CommitteeName           string `json:"CommitteeName"`
	CommitteeAcronym        string `json:"CommitteeAcronym"`
	Number                  string `json:"Number"`
	Date                    string `json:"Date"`
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
	bill.CommitteeStages = d.extractCommitteeStages(baseURL)
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

func (d billDetailJSON) extractCommitteeStages(baseURL string) []domain.BillCommitteeStage {
	all := append([]stageJSON{}, d.BillStages.HouseBillStages...)
	all = append(all, d.BillStages.SenateBillStages...)
	stages := make([]domain.BillCommitteeStage, 0)
	for i, stage := range all {
		if !isCommitteeStage(stage) {
			continue
		}
		committee := stage.Committee
		if committee == nil && len(stage.CommitteeMeetings) > 0 {
			meeting := stage.CommitteeMeetings[0]
			committee = &committeeJSON{
				CommitteeOrganizationID: meeting.CommitteeOrganizationID,
				CommitteeNameEn:         meeting.CommitteeNameEn,
				CommitteeName:           meeting.CommitteeName,
				CommitteeAcronym:        meeting.CommitteeAcronym,
			}
		}
		if committee == nil || strings.TrimSpace(committee.CommitteeAcronym) == "" {
			continue
		}

		stageID := strconv.Itoa(stage.BillStageID)
		stageName := firstNonEmpty(stage.BillStageNameEn, stage.BillStageName)
		chamber := chamberName(stage.ChamberOrganizationID)
		committeeChamber := committeeChamberCode(stage.ChamberOrganizationID, committee)
		completed := strings.EqualFold(firstNonEmpty(stage.StateNameEn, stage.StateName), "Completed")
		completedAt := ""
		if completed {
			completedAt = firstNonEmpty(dateOnly(stage.StateAsOfDate), dateOnly(stage.LastStageEventStartDate))
		}
		meetings := committeeMeetingsForStage(d.NumberCode, stage, committeeChamber)
		stages = append(stages, domain.BillCommitteeStage{
			ID:               stableID(d.NumberCode, "committee", stageID, committee.CommitteeAcronym),
			StageID:          stageID,
			StageName:        stageName,
			Chamber:          chamber,
			State:            firstNonEmpty(stage.StateNameEn, stage.StateName),
			CommitteeID:      strconv.Itoa(committee.CommitteeOrganizationID),
			CommitteeAcronym: strings.TrimSpace(committee.CommitteeAcronym),
			CommitteeName:    firstNonEmpty(committee.CommitteeNameEn, committee.CommitteeName),
			CommitteeChamber: committeeChamber,
			CommitteeURL:     committeeURL(committee.CommitteeAcronym, committeeChamber),
			StudiedSince:     firstNonEmpty(referralDateForCommittee(all[:i], committee.CommitteeAcronym), earliestMeetingDate(meetings)),
			StudyCompletedAt: completedAt,
			Meetings:         meetings,
			SortOrder:        i + 1,
		})
	}
	return stages
}

func isCommitteeStage(stage stageJSON) bool {
	stageName := strings.ToLower(firstNonEmpty(stage.BillStageNameEn, stage.BillStageName))
	return strings.Contains(stageName, "committee") || len(stage.CommitteeMeetings) > 0
}

func committeeMeetingsForStage(number string, stage stageJSON, chamberCode string) []domain.BillCommitteeMeeting {
	meetings := make([]domain.BillCommitteeMeeting, 0, len(stage.CommitteeMeetings))
	for i, meeting := range stage.CommitteeMeetings {
		meetingNumber, _ := strconv.Atoi(strings.TrimSpace(meeting.Number))
		acronym := strings.TrimSpace(meeting.CommitteeAcronym)
		date := dateOnly(meeting.Date)
		meetings = append(meetings, domain.BillCommitteeMeeting{
			ID:            stableID(number, acronym, meeting.Number, date),
			MeetingNumber: meetingNumber,
			Date:          date,
			EvidenceURL:   evidenceURL(stage.ParliamentNumber, stage.SessionNumber, acronym, meetingNumber, chamberCode),
			SortOrder:     i + 1,
		})
	}
	return meetings
}

func referralDateForCommittee(stages []stageJSON, acronym string) string {
	acronym = strings.TrimSpace(acronym)
	for i := len(stages) - 1; i >= 0; i-- {
		stage := stages[i]
		if stage.Committee == nil || !strings.EqualFold(strings.TrimSpace(stage.Committee.CommitteeAcronym), acronym) {
			continue
		}
		for j := len(stage.SignificantEvents) - 1; j >= 0; j-- {
			event := stage.SignificantEvents[j]
			name := strings.ToLower(firstNonEmpty(event.EventNameEn, event.EventName))
			if strings.Contains(name, "referral to committee") || strings.Contains(name, "renvoi en comité") {
				return dateOnly(event.EventDateTime)
			}
		}
		if stage.ContainsReferralToCommitteeEvent {
			return firstNonEmpty(dateOnly(stage.LastStageEventStartDate), dateOnly(stage.StateAsOfDate))
		}
	}
	return ""
}

func earliestMeetingDate(meetings []domain.BillCommitteeMeeting) string {
	earliest := ""
	for _, meeting := range meetings {
		if meeting.Date == "" {
			continue
		}
		if earliest == "" || meeting.Date < earliest {
			earliest = meeting.Date
		}
	}
	return earliest
}

func committeeChamberCode(chamberOrganizationID int, committee *committeeJSON) string {
	if chamberOrganizationID == 2 || committee.IsSenateCommittee {
		return "SEN"
	}
	if committee.IsJointCommittee {
		return "JOINT"
	}
	return "HOC"
}

func committeeURL(acronym, chamberCode string) string {
	acronym = strings.TrimSpace(acronym)
	if acronym == "" {
		return ""
	}
	if chamberCode == "SEN" {
		return fmt.Sprintf("https://sencanada.ca/en/committees/%s/", strings.ToLower(acronym))
	}
	return fmt.Sprintf("https://www.ourcommons.ca/Committees/en/%s", acronym)
}

func evidenceURL(parliament, session int, acronym string, meetingNumber int, chamberCode string) string {
	if chamberCode != "HOC" || parliament == 0 || session == 0 || strings.TrimSpace(acronym) == "" || meetingNumber == 0 {
		return ""
	}
	return fmt.Sprintf(
		"https://www.ourcommons.ca/DocumentViewer/en/%d-%d/%s/meeting-%d/evidence",
		parliament,
		session,
		acronym,
		meetingNumber,
	)
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
		fromVer := ordered[i-1]
		toVer := ordered[i]
		diffID := stableID("diff", number, fromVer.ID, toVer.ID)

		var clauseDiffs []domain.BillClauseDiff
		if len(fromVer.Sections) > 0 && len(toVer.Sections) > 0 {
			rawDiffs := DiffClauses(fromVer.Sections, toVer.Sections)
			clauseDiffs = make([]domain.BillClauseDiff, 0, len(rawDiffs))
			for idx, rd := range rawDiffs {
				clauseID := stableID("clause", number, diffID, rd.Label)
				if rd.Label == "" {
					clauseID = stableID("clause", number, diffID, strconv.Itoa(idx))
				}
				clauseDiffs = append(clauseDiffs, domain.BillClauseDiff{
					ID:               clauseID,
					Label:            rd.Label,
					ChangeType:       rd.ChangeType,
					FromText:         rd.FromText,
					ToText:           rd.ToText,
					HansardAnchorURL: nil,
				})
			}
		}

		diffs = append(diffs, domain.BillDiff{
			ID:            diffID,
			FromVersionID: fromVer.ID,
			ToVersionID:   toVer.ID,
			SourceURL:     detailURL,
			Clauses:       clauseDiffs,
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

func computeSHA256(data []byte) string {
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:])
}

func parseBillXML(xmlData []byte) ([]domain.VersionSection, error) {
	decoder := xml.NewDecoder(bytes.NewReader(xmlData))
	var sections []domain.VersionSection
	var currentSec *domain.VersionSection
	var inLabel bool
	var labelDepth int
	var secDepth int

	for {
		t, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		switch se := t.(type) {
		case xml.StartElement:
			if se.Name.Local == "Section" {
				currentSec = &domain.VersionSection{}
				secDepth = 1
			} else if currentSec != nil {
				secDepth++
				if se.Name.Local == "Label" && secDepth == 2 {
					inLabel = true
					labelDepth = secDepth
				}
			}
		case xml.EndElement:
			if currentSec != nil {
				if se.Name.Local == "Section" && secDepth == 1 {
					currentSec.Label = strings.TrimSpace(currentSec.Label)
					currentSec.Text = cleanSectionText(currentSec.Text)
					sections = append(sections, *currentSec)
					currentSec = nil
				} else {
					if inLabel && secDepth == labelDepth {
						inLabel = false
					}
					secDepth--
				}
			}
		case xml.CharData:
			if currentSec != nil {
				str := string(se)
				if inLabel {
					currentSec.Label += str
				} else {
					currentSec.Text += str
				}
			}
		}
	}
	return sections, nil
}

func cleanSectionText(s string) string {
	words := strings.Fields(s)
	return strings.Join(words, " ")
}

func DiffClauses(fromClauses, toClauses []domain.VersionSection) []domain.BillClauseDiff {
	n := len(fromClauses)
	m := len(toClauses)

	dp := make([][]int, n+1)
	for i := range dp {
		dp[i] = make([]int, m+1)
	}

	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			if fromClauses[i-1].Label != "" && fromClauses[i-1].Label == toClauses[j-1].Label {
				dp[i][j] = dp[i-1][j-1] + 1
			} else {
				dp[i][j] = maxInt(dp[i-1][j], dp[i][j-1])
			}
		}
	}

	var diffs []domain.BillClauseDiff
	i, j := n, m
	for i > 0 || j > 0 {
		if i > 0 && j > 0 && fromClauses[i-1].Label != "" && fromClauses[i-1].Label == toClauses[j-1].Label {
			fc := fromClauses[i-1]
			tc := toClauses[j-1]
			changeType := "unchanged"
			if fc.Text != tc.Text {
				changeType = "modified"
			}
			diffs = append(diffs, domain.BillClauseDiff{
				Label:      fc.Label,
				ChangeType: changeType,
				FromText:   fc.Text,
				ToText:     tc.Text,
			})
			i--
			j--
		} else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
			tc := toClauses[j-1]
			diffs = append(diffs, domain.BillClauseDiff{
				Label:      tc.Label,
				ChangeType: "added",
				ToText:     tc.Text,
			})
			j--
		} else {
			fc := fromClauses[i-1]
			diffs = append(diffs, domain.BillClauseDiff{
				Label:      fc.Label,
				ChangeType: "removed",
				FromText:   fc.Text,
			})
			i--
		}
	}

	for k := 0; k < len(diffs)/2; k++ {
		diffs[k], diffs[len(diffs)-1-k] = diffs[len(diffs)-1-k], diffs[k]
	}

	return diffs
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
