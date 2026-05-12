package main

import (
	"testing"
)

func TestParseOrganizations(t *testing.T) {
	records := [][]string{
		{"org_id", "dept_id", "pop_id", "abbr_en", "legal_title", "applied_title", "old_applied_title", "description_en", "min_port", "min_1", "min_2", "min_3", "min_4", "min_5", "min_6", "min_7", "inst_struct", "start", "end_fin", "status"},
		{"1", "AGR", "AAFC", "AAFC", "Department of Agriculture and Agri-Food", "Agriculture and Agri-Food Canada", "", "Desc", "Min", "Min1", "", "", "", "", "", "", "Struct", "1867", "", "a"},
		{"2", "HC", "HOC", "HC", "House of Commons", "", "", "Desc", "Min", "Min1", "", "", "", "", "", "", "Struct", "1867", "", "a"},
	}

	orgs := parseOrganizations(records)
	if len(orgs) != 2 {
		t.Fatalf("expected 2 organizations, got %d", len(orgs))
	}

	if orgs[0].ID != 1 || orgs[0].Name != "Agriculture and Agri-Food Canada" {
		t.Errorf("org[0] mismatch: %+v", orgs[0])
	}
	if orgs[1].ID != 2 || orgs[1].Name != "House of Commons" {
		t.Errorf("org[1] mismatch: %+v", orgs[1])
	}
}

func TestParseEstimates(t *testing.T) {
	nameToID := map[string]int{
		"Department of Agriculture and Agri-Food": 1,
		"Agriculture and Agri-Food Canada":        1,
		"House of Commons":                        2,
	}

	records := [][]string{
		{"fy_ef", "organization", "estimates_document", "vote_number", "vote_type", "authorities"},
		{"2024-25", "Agriculture and Agri-Food Canada", "Main Estimates", "1", "Operating expenditures", "1000000.00"},
		{"2024-25", "House of Commons", "Main Estimates", "1", "Program expenditures", "500000.00"},
		{"2024-25", "Agriculture and Agri-Food Canada", "Supplementary Estimates (A)", "1", "Operating expenditures", "100.00"},
		{"2024-25", "Unknown Org", "Main Estimates", "1", "Operating expenditures", "100.00"},
	}

	estimates := parseEstimates(records, nameToID)
	if len(estimates) != 2 {
		t.Fatalf("expected 2 estimates, got %d", len(estimates))
	}

	if estimates[0].OrganizationID != 1 || estimates[0].Authorities != 1000000.00 {
		t.Errorf("estimate[0] mismatch: %+v", estimates[0])
	}
	if estimates[1].OrganizationID != 2 || estimates[1].Authorities != 500000.00 {
		t.Errorf("estimate[1] mismatch: %+v", estimates[1])
	}
}
