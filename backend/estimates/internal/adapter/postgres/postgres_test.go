package postgres

import "testing"

func TestNewEstimatesRepository(t *testing.T) {
	if repo := NewEstimatesRepository(nil); repo == nil {
		t.Fatal("NewEstimatesRepository returned nil")
	}
}
