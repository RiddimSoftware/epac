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
				<a href="/Members/en/jane-example(89156)/roles">View all roles Jane Example has held as a member of Parliament.</a>
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
		case "/Members/en/jane-example(89156)/roles":
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte(`<html><body>
				<table id="roles-mp"><tbody>
					<tr><th>Constituency</th><th>Province / Territory</th><th>Start Date</th><th>End Date</th></tr>
					<tr><td>Ottawa Centre</td><td>Ontario</td><td>Monday, April 28, 2025</td><td></td></tr>
				</tbody></table>
				<table id="roles-committees"><tbody>
					<tr><th>Parliament - Session</th><th>Role</th><th>Committee</th><th>Start Date</th><th>End Date</th></tr>
					<tr><td>45-1</td><td>Member</td><td>Health</td><td>Friday, June 13, 2025</td><td></td></tr>
				</tbody></table>
				<table id="roles-iia"><tbody>
					<tr><td>45th</td><td>Member</td><td>Canada-Europe Parliamentary Association</td><td>Wednesday, April 1, 2026</td><td></td></tr>
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
	if len(member.Biography.YearsServed) != 1 || member.Biography.YearsServed[0].FromDate != "2025-04-28" {
		t.Fatalf("years served = %#v", member.Biography.YearsServed)
	}
	if len(member.Biography.PreviousRoles) != 2 || member.Biography.PreviousRoles[0].Organization != "Health" {
		t.Fatalf("previous roles = %#v", member.Biography.PreviousRoles)
	}
	if len(member.PMBSponsorships) != 2 {
		t.Fatalf("sponsorships = %#v", member.PMBSponsorships)
	}
	if len(member.Attendance) != 1 || member.Attendance[0].VoteNumber != "151" {
		t.Fatalf("attendance = %#v", member.Attendance)
	}
}
