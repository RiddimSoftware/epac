package ourcommons

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetcherBuildsMemberBiographyAttendanceAndPMBSponsorships(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/Members/en/search/XML":
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(`<ArrayOfMemberOfParliament><MemberOfParliament>
				<PersonId>89156</PersonId>
				<PersonShortHonorific>Hon.</PersonShortHonorific>
				<PersonOfficialFirstName>Jane</PersonOfficialFirstName>
				<PersonOfficialLastName>Example</PersonOfficialLastName>
				<ConstituencyName>Ottawa Centre</ConstituencyName>
				<ConstituencyProvinceTerritoryName>Ontario</ConstituencyProvinceTerritoryName>
				<CaucusShortName>Liberal</CaucusShortName>
				<FromDateTime>2025-04-28T00:00:00</FromDateTime>
			</MemberOfParliament></ArrayOfMemberOfParliament>`))
		case "/Members/en/89156":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<html><head><meta name="description" content="Jane Example - Member of Parliament"></head><body>
				<img class="ce-mip-mp-picture" src="/photo.jpg">
				<dl><dt>Preferred Language:</dt><dd>English / French</dd></dl>
				<table id="ce-mip-bill-sponsored-table"><tbody>
					<tr><th>Bill Number</th><th>Title</th></tr>
					<tr><td><a href="//parl.ca/LegisInfo/BillDetails.aspx?billId=1">C-234</a></td><td>Living Donor Recognition Medal Act</td></tr>
				</tbody></table>
				<table id="ce-mip-bill-seconded-table"><tbody>
					<tr><td><a href="//parl.ca/LegisInfo/BillDetails.aspx?billId=2">C-276</a></td><td>Cash Act</td></tr>
				</tbody></table>
				<table id="ce-mip-vote-table"><tbody>
					<tr><th>Vote Number</th><th>Subject</th><th>Voted</th><th>Result</th><th>Date</th></tr>
					<tr><td><a href="/Members/en/votes/45/1/151">No. 151</a></td><td>Report stage</td><td>Yea</td><td>Agreed To</td><td>Wednesday, June 10, 2026</td></tr>
				</tbody></table>
			</body></html>`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	fetcher := NewFetcher(WithBaseURL(server.URL), WithHTTPClient(server.Client()))
	batch, err := fetcher.FetchMembers(context.Background())
	if err != nil {
		t.Fatalf("FetchMembers: %v", err)
	}
	if len(batch.Members) != 1 {
		t.Fatalf("members len = %d", len(batch.Members))
	}
	member := batch.Members[0]
	if member.Name != "Jane Example" || member.Biography.PreferredLanguage != "English / French" {
		t.Fatalf("member = %#v", member)
	}
	if len(member.PMBSponsorships) != 2 {
		t.Fatalf("sponsorships = %#v", member.PMBSponsorships)
	}
	if len(member.Attendance) != 1 || member.Attendance[0].VoteNumber != "151" {
		t.Fatalf("attendance = %#v", member.Attendance)
	}
}
