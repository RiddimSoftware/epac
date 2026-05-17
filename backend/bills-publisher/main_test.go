package main

import "testing"

func TestMapBill(t *testing.T) {
	bill, ok := mapBill(legisInfoBill{
		BillNumberFormatted:             "C-12",
		ShortTitleEn:                    "Example Act",
		CurrentStatusEn:                 "At second reading",
		BillTypeEn:                      "House Government Bill",
		SponsorEn:                       "Example Sponsor",
		OriginatingChamberID:            1,
		PassedHouseFirstReadingDateTime: "2026-04-27T08:44:38.9-04:00",
	}, 45, 1)
	if !ok {
		t.Fatal("mapBill returned false")
	}
	if bill.ID != "C-12" || bill.Title != "Example Act" || bill.Status != "InProgress" {
		t.Fatalf("bill = %+v", bill)
	}
	if bill.IntroducedOn == nil || *bill.IntroducedOn != "2026-04-27" {
		t.Fatalf("introduced_on = %#v", bill.IntroducedOn)
	}
	if len(bill.Stages) != 7 {
		t.Fatalf("len(stages) = %d, want 7", len(bill.Stages))
	}
}

func TestBillStatusRoyalAssent(t *testing.T) {
	got := billStatus(legisInfoBill{ReceivedRoyalAssentDateTime: "2026-05-01T00:00:00-04:00"})
	if got != "RoyalAssent" {
		t.Fatalf("got %q, want RoyalAssent", got)
	}
}
