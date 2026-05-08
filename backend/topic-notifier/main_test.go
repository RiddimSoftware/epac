package main

import "testing"

func TestMatchTopicsUsesCanonicalTaxonomy(t *testing.T) {
	cases := []struct {
		name    string
		subject string
		wantID  string
	}{
		{
			name:    "natural resources retained for forestry subjects",
			subject: "Forestry harvest and timber revenue",
			wantID:  "naturalresources",
		},
		{
			name:    "expanded defence keywords match veterans affairs",
			subject: "Veterans Affairs and NATO readiness",
			wantID:  "defence",
		},
		{
			name:    "expanded justice keywords match parole subjects",
			subject: "Parole reform and correctional policy",
			wantID:  "justice",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			matched := matchTopics(tc.subject)
			if !containsTopicID(matched, tc.wantID) {
				t.Fatalf("matchTopics(%q) = %v, want %q", tc.subject, matched, tc.wantID)
			}
		})
	}
}

func TestTopicNameUsesCanonicalBackendDisplayNames(t *testing.T) {
	if got := topicName("naturalresources"); got != "Natural Resources" {
		t.Fatalf("topicName(naturalresources) = %q, want %q", got, "Natural Resources")
	}
}

func containsTopicID(ids []string, target string) bool {
	for _, id := range ids {
		if id == target {
			return true
		}
	}
	return false
}
