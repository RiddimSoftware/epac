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
					"StateNameEn":"Completed",
					"StateAsOfDate":"2025-06-03T10:02:53.767",
					"SignificantEvents":[{
						"EventTypeId":60110,
						"EventNameEn":"Introduction and first reading",
						"EventDateTime":"2025-06-03T00:00:00",
						"AmendmentNoteId":777
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
	if bill.Title != "Border bill detail" || len(bill.Stages) != 1 || len(bill.Events) != 1 {
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
}
