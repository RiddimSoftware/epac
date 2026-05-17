package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestWriteArtifacts(t *testing.T) {
	dir := t.TempDir()
	members := []Member{{ID: "278707", Name: "Example MP", Province: "ON", Party: "Liberal"}}
	if err := writeArtifacts(dir, members); err != nil {
		t.Fatalf("writeArtifacts: %v", err)
	}

	allData, err := os.ReadFile(filepath.Join(dir, "v1", "all.json"))
	if err != nil {
		t.Fatalf("read all artifact: %v", err)
	}
	var all MembersResponse
	if err := json.Unmarshal(allData, &all); err != nil {
		t.Fatalf("decode all artifact: %v", err)
	}
	if len(all.Members) != 1 || all.Members[0].ID != "278707" {
		t.Fatalf("all artifact = %+v", all)
	}

	if _, err := os.Stat(filepath.Join(dir, "v1", "by-id", "278707.json")); err != nil {
		t.Fatalf("by-id artifact missing: %v", err)
	}
}

func TestProvinceCode(t *testing.T) {
	if got := provinceCode("Ontario"); got != "ON" {
		t.Fatalf("got %q, want ON", got)
	}
	if got := provinceCode("Unknown Region"); got != "Unknown Region" {
		t.Fatalf("got %q, want original value", got)
	}
}
