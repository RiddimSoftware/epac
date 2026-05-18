package postgres

import "testing"

func TestRepositoryConstructors(t *testing.T) {
	if repo := NewHansardRepository(nil); repo == nil {
		t.Fatal("NewHansardRepository returned nil")
	}
	if repo := NewMemberRepository(nil); repo == nil {
		t.Fatal("NewMemberRepository returned nil")
	}
}
