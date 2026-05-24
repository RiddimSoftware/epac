package repository

import "testing"

func TestNewPostgresSubjectsRepository(t *testing.T) {
	repo := NewPostgresSubjectsRepository(nil)
	if repo == nil {
		t.Fatal("repository is nil")
	}
}
