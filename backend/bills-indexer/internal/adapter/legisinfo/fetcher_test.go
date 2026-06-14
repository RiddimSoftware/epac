package legisinfo

import (
	"context"
	"net/http"
	"net/http/httptest"
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

