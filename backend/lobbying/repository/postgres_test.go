package repository

import "testing"

func TestNewPostgresLobbyistOrganizationRepositoryStoresQueryer(t *testing.T) {
	queryer := stubQueryer{}
	repo := NewPostgresLobbyistOrganizationRepository(queryer)

	if repo.db != queryer {
		t.Fatal("repository did not store queryer")
	}
}

type stubQueryer struct {
	Queryer
}
