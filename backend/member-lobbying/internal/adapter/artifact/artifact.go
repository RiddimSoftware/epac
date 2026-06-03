package artifact

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"epac/member-content"
	"epac/member-lobbying/internal/usecase"
)

type MPLobbyingRepository interface {
	LoadMPLobbyingArtifact(ctx context.Context, memberID string) (usecase.MPLobbyingArtifact, error)
}

type S3ArtifactRepository struct {
	store membercontent.Store
}

func NewS3ArtifactRepositoryFromEnv(ctx context.Context) (S3ArtifactRepository, error) {
	store, err := membercontent.NewStoreFromEnv(ctx)
	if err != nil {
		return S3ArtifactRepository{}, err
	}
	return S3ArtifactRepository{store: store}, nil
}

func (r S3ArtifactRepository) LoadMPLobbyingArtifact(ctx context.Context, memberID string) (usecase.MPLobbyingArtifact, error) {
	body, err := r.store.Get(ctx, lobbyingJSONKey(memberID))
	if errors.Is(err, membercontent.ErrArtifactNotFound) {
		return usecase.MPLobbyingArtifact{}, usecase.ErrNotFound
	}
	if err != nil {
		return usecase.MPLobbyingArtifact{}, err
	}

	var artifact usecase.MPLobbyingArtifact
	if err := json.Unmarshal(body, &artifact); err != nil {
		return usecase.MPLobbyingArtifact{}, fmt.Errorf("decode lobbying artifact for %s: %w", memberID, err)
	}
	return artifact, nil
}

func lobbyingJSONKey(memberID string) string {
	return fmt.Sprintf("members/v1/by-id/%s/lobbying.json", memberID)
}
