package legisinfo

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"epac/bills-indexer/internal/domain"
)

func TestFetcherBuildsRelationalBillRecordsFromLegisInfoExports(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/legisinfo/en/bills/json":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`[{
				"BillId":13543613,
				"BillNumberFormatted":"C-2",
				"LongTitleEn":"Border bill",
				"CurrentStatusEn":"At second reading",
				"LatestCompletedMajorStageEn":"First reading",
				"BillTypeEn":"House Government Bill",
				"SponsorId":89449,
				"SponsorEn":"Hon. Example",
				"ParliamentNumber":45,
				"SessionNumber":1,
				"PassedHouseFirstReadingDateTime":"2025-06-03T10:02:53.767"
			}]`))
		case "/legisinfo/en/bill/45-1/c-2/json":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`[{
				"Id":13543613,
				"NumberCode":"C-2",
				"LongTitleEn":"Border bill detail",
				"StatusNameEn":"At report stage",
				"OngoingStageNameEn":"Report stage",
				"SponsorPersonId":89449,
				"SponsorPersonName":"Hon. Example",
				"BillDocumentTypeNameEn":"House Government Bill",
				"ParliamentNumber":45,
				"SessionNumber":1,
				"PassedHouseFirstReadingDateTime":"2025-06-03T10:02:53.767",
				"BillStages":{"HouseBillStages":[{
					"BillStageId":60029,
					"BillStageNameEn":"First reading",
					"ChamberOrganizationId":1,
					"ParliamentNumber":45,
					"SessionNumber":1,
					"StateNameEn":"Completed",
					"StateAsOfDate":"2025-06-03T10:02:53.767",
					"SignificantEvents":[{
						"EventTypeId":60110,
						"EventNameEn":"Introduction and first reading",
						"EventDateTime":"2025-06-03T00:00:00",
						"AmendmentNoteId":777
					}]
				},{
					"BillStageId":60030,
					"BillStageNameEn":"Second reading",
					"ChamberOrganizationId":1,
					"ParliamentNumber":45,
					"SessionNumber":1,
					"StateNameEn":"Completed",
					"StateAsOfDate":"2025-10-03T10:55:04",
					"Committee":{
						"CommitteeOrganizationId":30576,
						"CommitteeNameEn":"Standing Committee on Public Safety and National Security",
						"CommitteeAcronym":"SECU",
						"IsHouseOfCommonsCommittee":true
					},
					"SignificantEvents":[{
						"EventTypeId":60121,
						"EventNameEn":"Second reading and referral to committee",
						"EventDateTime":"2025-10-03T00:00:00"
					}]
				},{
					"BillStageId":60049,
					"BillStageNameEn":"Consideration in committee",
					"ChamberOrganizationId":1,
					"ParliamentNumber":45,
					"SessionNumber":1,
					"StateNameEn":"Completed",
					"StateAsOfDate":"2026-03-11T12:40:09.547",
					"Committee":{
						"CommitteeOrganizationId":30576,
						"CommitteeNameEn":"Standing Committee on Public Safety and National Security",
						"CommitteeAcronym":"SECU",
						"IsHouseOfCommonsCommittee":true
					},
					"CommitteeMeetings":[{
						"CommitteeOrganizationId":30576,
						"CommitteeNameEn":"Standing Committee on Public Safety and National Security",
						"CommitteeAcronym":"SECU",
						"Number":"9",
						"Date":"2025-10-28T00:00:00"
					}],
					"SignificantEvents":[{
						"EventTypeId":60124,
						"EventNameEn":"Committee report presented with amendments",
						"EventDateTime":"2026-03-11T00:00:00"
					}]
				}],"SenateBillStages":[]},
				"Publications":[{"PublicationId":13545752,"PublicationTypeNameEn":"First Reading"}],
				"WebReferences":[{
					"TitleEn":"PBO costing note",
					"WebReferenceTypeNameEn":"PBO",
					"UrlEn":"https://www.pbo-dpb.ca/example"
				}]
			}]`))
		case "/DocumentViewer/en/45-1/bill/C-2/first-reading":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<a href="/Content/Bills/451/Government/C-2/C-2_1/C-2_E.xml">XML</a><a href="/Content/Bills/451/Government/C-2/C-2_1/C-2_1.PDF">PDF</a>`))
		case "/Content/Bills/451/Government/C-2/C-2_1/C-2_E.xml":
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(`<?xml version="1.0" encoding="utf-8"?>
<Bill>
  <Body>
    <Section>
      <Label>1</Label>
      <Text>Verbatim clause text of section 1.</Text>
    </Section>
  </Body>
</Bill>`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.String())
		}
	}))
	defer server.Close()

	fetcher := NewFetcher(WithBaseURL(server.URL), WithHTTPClient(server.Client()))
	batch, err := fetcher.FetchBills(context.Background(), domain.Session{ParliamentNumber: 45, SessionNumber: 1})
	if err != nil {
		t.Fatalf("FetchBills: %v", err)
	}
	if len(batch.Bills) != 1 {
		t.Fatalf("bills len = %d", len(batch.Bills))
	}
	bill := batch.Bills[0]
	if bill.Title != "Border bill detail" || len(bill.Stages) != 3 || len(bill.Events) != 3 {
		t.Fatalf("bill = %#v", bill)
	}
	if len(bill.Versions) != 1 || bill.Versions[0].XMLURL == "" || bill.Versions[0].PDFURL == "" {
		t.Fatalf("versions = %#v", bill.Versions)
	}
	if len(bill.Amendments) != 1 {
		t.Fatalf("amendments = %#v", bill.Amendments)
	}
	if len(bill.PBOCostings) != 1 {
		t.Fatalf("pbo costings = %#v", bill.PBOCostings)
	}
	if len(bill.CommitteeStages) != 1 {
		t.Fatalf("committee stages = %#v", bill.CommitteeStages)
	}
	stage := bill.CommitteeStages[0]
	if stage.CommitteeAcronym != "SECU" || stage.StudiedSince != "2025-10-03" || stage.StudyCompletedAt != "2026-03-11" {
		t.Fatalf("committee stage = %#v", stage)
	}
	if len(stage.Meetings) != 1 || stage.Meetings[0].MeetingNumber != 9 || stage.Meetings[0].EvidenceURL == "" {
		t.Fatalf("committee meetings = %#v", stage.Meetings)
	}
}

func TestConstructURL(t *testing.T) {
	t.Run("XML construction", func(t *testing.T) {
		first := "https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_1/C-11_E.xml"
		want := "https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_2/C-11_E.xml"
		got := constructXMLURL(first, 2)
		if got != want {
			t.Errorf("constructXMLURL = %q, want %q", got, want)
		}

		// Empty URL returns empty
		if constructXMLURL("", 2) != "" {
			t.Error("constructXMLURL with empty string should return empty string")
		}

		// If no _1/ exists, returns first URL unchanged
		noMatch := "https://www.parl.ca/other/url.xml"
		if constructXMLURL(noMatch, 2) != noMatch {
			t.Errorf("constructXMLURL without matching prefix should return input unchanged")
		}
	})

	t.Run("PDF construction", func(t *testing.T) {
		first := "https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_1/C-11_1.PDF"
		want := "https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_2/C-11_2.PDF"
		got := constructPDFURL(first, 2)
		if got != want {
			t.Errorf("constructPDFURL = %q, want %q", got, want)
		}

		firstLower := "https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_1/C-11_1.pdf"
		wantLower := "https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_2/C-11_2.pdf"
		gotLower := constructPDFURL(firstLower, 2)
		if gotLower != wantLower {
			t.Errorf("constructPDFURL lower = %q, want %q", gotLower, wantLower)
		}

		// Empty URL returns empty
		if constructPDFURL("", 2) != "" {
			t.Error("constructPDFURL with empty string should return empty string")
		}
	})
}

func billXMLBody(label, text string) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<Bill><Body><Section><Label>%s</Label><Text>%s</Text></Section></Body></Bill>`, label, text)
}

func assertVersionXML(t *testing.T, v domain.BillVersion, xmlSuffix, sectionLabel string) {
	t.Helper()
	if !strings.HasSuffix(v.XMLURL, xmlSuffix) {
		t.Errorf("version %q XMLURL = %q, want suffix %q", v.StageSlug, v.XMLURL, xmlSuffix)
	}
	if v.TextHash == nil || *v.TextHash == "" {
		t.Errorf("version %q TextHash not set", v.StageSlug)
	}
	if v.TextSourceURL == nil || !strings.HasSuffix(*v.TextSourceURL, xmlSuffix) {
		t.Errorf("version %q TextSourceURL = %v, want suffix %q", v.StageSlug, v.TextSourceURL, xmlSuffix)
	}
	if len(v.Sections) != 1 || v.Sections[0].Label != sectionLabel {
		t.Errorf("version %q Sections = %#v, want one section labeled %q", v.StageSlug, v.Sections, sectionLabel)
	}
}

// TestEnrichVersionsResolvesDirectAndPDFSiblingXMLLinks covers the discovery happy paths:
// stages that expose a direct .xml anchor stay populated and stable, and an intermediate
// stage that exposes only a PDF anchor recovers its XML from the sibling beside that PDF —
// at the document directory the page actually links, not the sort-order guess.
func TestEnrichVersionsResolvesDirectAndPDFSiblingXMLLinks(t *testing.T) {
	const xmlType = "application/xml"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/DocumentViewer/en/45-1/bill/C-9/first-reading":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<a href="/Content/Bills/451/Government/C-9/C-9_1/C-9_E.xml">XML</a><a href="/Content/Bills/451/Government/C-9/C-9_1/C-9_1.PDF">PDF</a>`))
		case "/Content/Bills/451/Government/C-9/C-9_1/C-9_E.xml":
			w.Header().Set("Content-Type", xmlType)
			_, _ = w.Write([]byte(billXMLBody("1", "First reading clause.")))

		// Intermediate stage: only a PDF anchor, at a non-sort-order directory (C-9_3).
		case "/DocumentViewer/en/45-1/bill/C-9/as-amended-by-committee":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<a href="/Content/Bills/451/Government/C-9/C-9_3/C-9_3.PDF">PDF</a>`))
		case "/Content/Bills/451/Government/C-9/C-9_3/C-9_E.xml":
			w.Header().Set("Content-Type", xmlType)
			_, _ = w.Write([]byte(billXMLBody("2", "Amended clause.")))

		// Royal assent: both anchors directly, at C-9_4.
		case "/DocumentViewer/en/45-1/bill/C-9/royal-assent":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<a href="/Content/Bills/451/Government/C-9/C-9_4/C-9_E.xml">XML</a><a href="/Content/Bills/451/Government/C-9/C-9_4/C-9_4.PDF">PDF</a>`))
		case "/Content/Bills/451/Government/C-9/C-9_4/C-9_E.xml":
			w.Header().Set("Content-Type", xmlType)
			_, _ = w.Write([]byte(billXMLBody("3", "Royal assent clause.")))

		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	fetcher := NewFetcher(WithBaseURL(server.URL), WithHTTPClient(server.Client()))
	pubs := []publicationJSON{
		{PublicationID: 1001, PublicationTypeNameEn: "First Reading"},
		{PublicationID: 1002, PublicationTypeNameEn: "As Amended by Committee"},
		{PublicationID: 1003, PublicationTypeNameEn: "Royal Assent"},
	}
	versions := fetcher.enrichVersions(context.Background(), domain.Session{ParliamentNumber: 45, SessionNumber: 1}, "C-9", pubs)
	if len(versions) != 3 {
		t.Fatalf("versions len = %d, want 3", len(versions))
	}

	assertVersionXML(t, versions[0], "/C-9_1/C-9_E.xml", "1")
	if !strings.HasSuffix(versions[0].PDFURL, "/C-9_1/C-9_1.PDF") {
		t.Errorf("first-reading PDFURL = %q", versions[0].PDFURL)
	}

	assertVersionXML(t, versions[1], "/C-9_3/C-9_E.xml", "2")
	if !strings.HasSuffix(versions[1].PDFURL, "/C-9_3/C-9_3.PDF") {
		t.Errorf("as-amended PDFURL = %q", versions[1].PDFURL)
	}

	assertVersionXML(t, versions[2], "/C-9_4/C-9_E.xml", "3")
}

// TestEnrichVersionsDerivesSortOrderSiblingWhenPageHasNoLinks covers the last-resort path:
// a stage whose DocumentViewer page renders its links client-side (no .xml/.pdf anchors)
// still resolves through the predictable sort-order sibling derived from the first stage.
func TestEnrichVersionsDerivesSortOrderSiblingWhenPageHasNoLinks(t *testing.T) {
	const xmlType = "application/xml"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/DocumentViewer/en/45-1/bill/C-9/first-reading":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<a href="/Content/Bills/451/Government/C-9/C-9_1/C-9_E.xml">XML</a><a href="/Content/Bills/451/Government/C-9/C-9_1/C-9_1.PDF">PDF</a>`))
		case "/Content/Bills/451/Government/C-9/C-9_1/C-9_E.xml":
			w.Header().Set("Content-Type", xmlType)
			_, _ = w.Write([]byte(billXMLBody("1", "First reading clause.")))

		case "/DocumentViewer/en/45-1/bill/C-9/as-passed-by-the-house-of-commons":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<div id="viewer">loaded by script</div>`))
		case "/Content/Bills/451/Government/C-9/C-9_2/C-9_E.xml":
			w.Header().Set("Content-Type", xmlType)
			_, _ = w.Write([]byte(billXMLBody("2", "As passed clause.")))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	fetcher := NewFetcher(WithBaseURL(server.URL), WithHTTPClient(server.Client()))
	pubs := []publicationJSON{
		{PublicationID: 2001, PublicationTypeNameEn: "First Reading"},
		{PublicationID: 2002, PublicationTypeNameEn: "As Passed by the House of Commons"},
	}
	versions := fetcher.enrichVersions(context.Background(), domain.Session{ParliamentNumber: 45, SessionNumber: 1}, "C-9", pubs)
	if len(versions) != 2 {
		t.Fatalf("versions len = %d, want 2", len(versions))
	}
	assertVersionXML(t, versions[0], "/C-9_1/C-9_E.xml", "1")
	assertVersionXML(t, versions[1], "/C-9_2/C-9_E.xml", "2")
}

// TestEnrichVersionsDropsUnvalidatedXMLCandidates covers acceptance: a derived candidate
// that returns an HTTP 200 HTML soft-error, or 404s, is never persisted as xml_url and
// leaves the version carrying no text.
func TestEnrichVersionsDropsUnvalidatedXMLCandidates(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/DocumentViewer/en/45-1/bill/C-9/first-reading":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<a href="/Content/Bills/451/Government/C-9/C-9_1/C-9_E.xml">XML</a>`))
		case "/Content/Bills/451/Government/C-9/C-9_1/C-9_E.xml":
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(billXMLBody("1", "First reading clause.")))

		// Sort-order sibling exists (C-9_2) but returns an HTTP 200 HTML soft-error page.
		case "/DocumentViewer/en/45-1/bill/C-9/as-amended-by-committee":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<div>no document links here</div>`))
		case "/Content/Bills/451/Government/C-9/C-9_2/C-9_E.xml":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<html><body>Document not found</body></html>`))

		// Sort-order sibling (C-9_3) is not served at all, i.e. 404s.
		case "/DocumentViewer/en/45-1/bill/C-9/as-passed-by-the-senate":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<div>still nothing</div>`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	fetcher := NewFetcher(WithBaseURL(server.URL), WithHTTPClient(server.Client()))
	pubs := []publicationJSON{
		{PublicationID: 3001, PublicationTypeNameEn: "First Reading"},
		{PublicationID: 3002, PublicationTypeNameEn: "As Amended by Committee"},
		{PublicationID: 3003, PublicationTypeNameEn: "As Passed by the Senate"},
	}
	versions := fetcher.enrichVersions(context.Background(), domain.Session{ParliamentNumber: 45, SessionNumber: 1}, "C-9", pubs)
	if len(versions) != 3 {
		t.Fatalf("versions len = %d, want 3", len(versions))
	}
	assertVersionXML(t, versions[0], "/C-9_1/C-9_E.xml", "1")

	if versions[1].XMLURL != "" {
		t.Errorf("soft-error stage XMLURL = %q, want empty", versions[1].XMLURL)
	}
	if versions[1].TextHash != nil || len(versions[1].Sections) != 0 {
		t.Errorf("soft-error stage should carry no text: hash=%v sections=%#v", versions[1].TextHash, versions[1].Sections)
	}
	if versions[2].XMLURL != "" {
		t.Errorf("missing-source stage XMLURL = %q, want empty", versions[2].XMLURL)
	}
	if versions[2].TextHash != nil || len(versions[2].Sections) != 0 {
		t.Errorf("missing-source stage should carry no text: hash=%v sections=%#v", versions[2].TextHash, versions[2].Sections)
	}
}

// TestEnrichVersionsDoesNotReuseBaseXMLForLaterStages guards the sort-order fallback: when
// the first resolved XML is not a "_1" directory, a later stage with no links of its own
// must be left empty rather than re-pointed at an earlier stage's document.
func TestEnrichVersionsDoesNotReuseBaseXMLForLaterStages(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		// First-reading page renders client-side: no anchors, and no first-reading XML exists.
		case "/DocumentViewer/en/45-1/bill/C-9/first-reading":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<div>loaded by script</div>`))

		// As amended exposes a direct anchor at a non-"_1" directory (C-9_3).
		case "/DocumentViewer/en/45-1/bill/C-9/as-amended-by-committee":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<a href="/Content/Bills/451/Government/C-9/C-9_3/C-9_E.xml">XML</a>`))
		case "/Content/Bills/451/Government/C-9/C-9_3/C-9_E.xml":
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(billXMLBody("3", "Amended clause.")))

		// As passed renders client-side too: no anchors of its own.
		case "/DocumentViewer/en/45-1/bill/C-9/as-passed-by-the-house-of-commons":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<div>loaded by script</div>`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	fetcher := NewFetcher(WithBaseURL(server.URL), WithHTTPClient(server.Client()))
	pubs := []publicationJSON{
		{PublicationID: 4001, PublicationTypeNameEn: "First Reading"},
		{PublicationID: 4002, PublicationTypeNameEn: "As Amended by Committee"},
		{PublicationID: 4003, PublicationTypeNameEn: "As Passed by the House of Commons"},
	}
	versions := fetcher.enrichVersions(context.Background(), domain.Session{ParliamentNumber: 45, SessionNumber: 1}, "C-9", pubs)
	if len(versions) != 3 {
		t.Fatalf("versions len = %d, want 3", len(versions))
	}
	if versions[0].XMLURL != "" {
		t.Errorf("first-reading XMLURL = %q, want empty", versions[0].XMLURL)
	}
	assertVersionXML(t, versions[1], "/C-9_3/C-9_E.xml", "3")
	if versions[2].XMLURL != "" {
		t.Errorf("as-passed XMLURL = %q, want empty (must not reuse the as-amended document)", versions[2].XMLURL)
	}
}

func TestLooksLikeBillXML(t *testing.T) {
	cases := []struct {
		name string
		body string
		want bool
	}{
		{"bill with prolog", `<?xml version="1.0"?><Bill><Body/></Bill>`, true},
		{"bill with namespace", `<Bill xmlns="http://parl.ca/schema"><Body/></Bill>`, true},
		{"leading whitespace", "\n\t  <Bill></Bill>", true},
		{"html soft error", `<html><body>Not found</body></html>`, false},
		{"doctype html", `<!DOCTYPE html><html></html>`, false},
		{"unrelated xml", `<Document><Section/></Document>`, false},
		{"empty", "", false},
		{"whitespace only", "   \n  ", false},
		{"plain text", `Document not found`, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := looksLikeBillXML([]byte(tc.body)); got != tc.want {
				t.Errorf("looksLikeBillXML(%q) = %v, want %v", tc.body, got, tc.want)
			}
		})
	}
}

func TestXMLSiblingFromPDF(t *testing.T) {
	got := xmlSiblingFromPDF("https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_3/C-11_3.PDF", "C-11")
	want := "https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_3/C-11_E.xml"
	if got != want {
		t.Errorf("xmlSiblingFromPDF = %q, want %q", got, want)
	}
	if s := xmlSiblingFromPDF("https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_3/C-11_E.xml", "C-11"); s != "" {
		t.Errorf("xmlSiblingFromPDF on non-pdf input = %q, want empty", s)
	}
	if s := xmlSiblingFromPDF("", "C-11"); s != "" {
		t.Errorf("xmlSiblingFromPDF empty url = %q, want empty", s)
	}
	if s := xmlSiblingFromPDF("https://www.parl.ca/x/C-11_3.PDF", ""); s != "" {
		t.Errorf("xmlSiblingFromPDF empty number = %q, want empty", s)
	}
}

func TestDedupeNonEmpty(t *testing.T) {
	got := strings.Join(dedupeNonEmpty("a", "", "  ", "b", "a", "c", "b"), ",")
	if got != "a,b,c" {
		t.Errorf("dedupeNonEmpty = %q, want %q", got, "a,b,c")
	}
}
