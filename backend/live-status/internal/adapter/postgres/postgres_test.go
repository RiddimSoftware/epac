package postgres

import "testing"

func TestNewLiveParliamentStatusFetching(t *testing.T) {
	if repo := NewLiveParliamentStatusFetching(nil); repo == nil {
		t.Fatal("NewLiveParliamentStatusFetching returned nil")
	}
}
