package postgres

import "testing"

func TestNewHansardRepository(t *testing.T) {
	if repo := NewHansardRepository(nil); repo == nil {
		t.Fatal("NewHansardRepository returned nil")
	}
}
