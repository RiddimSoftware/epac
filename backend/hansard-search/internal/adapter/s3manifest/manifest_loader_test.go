package s3manifest

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"testing"

	"epac/hansard-search/internal/domain"
	"epac/hansard-search/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type mockS3Getter struct {
	body []byte
	err  error
}

func (m *mockS3Getter) GetObject(_ context.Context, _ *s3.GetObjectInput, _ ...func(*s3.Options)) (*s3.GetObjectOutput, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &s3.GetObjectOutput{Body: io.NopCloser(bytes.NewReader(m.body))}, nil
}

func TestManifestLoader_HappyPath(t *testing.T) {
	want := domain.Manifest{
		Version:           "1",
		BuiltAt:           "2026-05-25T00:00:00Z",
		ParliamentNumber:  45,
		SessionNumber:     1,
		SittingCount:      10,
		InterventionCount: 500,
		MessageCount:      1200,
		SQLiteKey:         "hansard-search/v1/index.sqlite",
		SQLiteSizeBytes:   1024000,
		SQLiteSHA256:      "abc123def456",
	}
	body, _ := json.Marshal(want)
	loader := NewManifestLoader(&mockS3Getter{body: body}, "my-bucket", "prefix/manifest.json")

	got, err := loader.Load(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != want {
		t.Errorf("manifest mismatch:\n got  %+v\n want %+v", got, want)
	}
}

func TestManifestLoader_NotFound(t *testing.T) {
	loader := NewManifestLoader(&mockS3Getter{err: &s3types.NoSuchKey{}}, "bucket", "key")

	_, err := loader.Load(context.Background())
	if !errors.Is(err, usecase.ErrManifestNotFound) {
		t.Errorf("want ErrManifestNotFound, got %v", err)
	}
}

func TestManifestLoader_MalformedJSON(t *testing.T) {
	loader := NewManifestLoader(&mockS3Getter{body: []byte("not json {{")}, "bucket", "key")

	_, err := loader.Load(context.Background())
	if err == nil {
		t.Fatal("expected error for malformed JSON")
	}
}
