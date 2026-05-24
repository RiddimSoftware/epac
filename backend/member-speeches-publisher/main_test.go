package main

import (
	"testing"

	"epac/member-content"
)

func TestPreviewIsRuneBounded(t *testing.T) {
	got := membercontent.Preview("éééé", 2)
	if got != "éé" {
		t.Fatalf("preview = %q, want first two runes", got)
	}
}
