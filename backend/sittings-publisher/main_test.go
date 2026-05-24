package main

import "testing"

func TestSourceURLForSittingFromFilename(t *testing.T) {
	parliament := 45
	session := 1
	got := sourceURLForSitting("", "45-1-HAN074-E.XML", &parliament, &session)
	want := "https://www.ourcommons.ca/documentviewer/en/45-1/house/sitting-74/hansard"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestSittingNumFromFilename(t *testing.T) {
	got := sittingNumFromFilename("45-1-HAN007-E.XML")
	if got == nil || *got != 7 {
		t.Fatalf("got %#v, want 7", got)
	}
}
