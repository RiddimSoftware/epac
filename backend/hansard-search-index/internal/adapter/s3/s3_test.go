package s3

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"epac/hansard-search-index/internal/domain"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

func TestUploadWritesSQLiteWithContentTypeEncryptionAndHashMetadata(t *testing.T) {
	path := filepath.Join(t.TempDir(), "index.sqlite")
	if err := os.WriteFile(path, []byte("sqlite bytes"), 0o644); err != nil {
		t.Fatalf("write sqlite: %v", err)
	}
	client := &mockPutObjectClient{}
	store := NewStore(client, "bucket", "hansard-search/v1")

	hash, size, err := store.Upload(context.Background(), path, "hansard-search/v1/index.sqlite")
	if err != nil {
		t.Fatalf("Upload: %v", err)
	}
	if size != int64(len("sqlite bytes")) {
		t.Fatalf("size = %d", size)
	}
	if hash == "" || len(hash) != 64 {
		t.Fatalf("hash = %q", hash)
	}
	got := client.inputs[0]
	if got.ContentType == nil || *got.ContentType != SQLiteContentType {
		t.Fatalf("content type = %v", got.ContentType)
	}
	if got.Metadata[sha256MetaKey] != hash {
		t.Fatalf("metadata hash = %q", got.Metadata[sha256MetaKey])
	}
}

func TestWriteUploadsManifestAtPrefixAfterMarshal(t *testing.T) {
	client := &mockPutObjectClient{}
	store := NewStore(client, "bucket", "hansard-search/v1")

	err := store.Write(context.Background(), domain.Manifest{
		Version:      "v1",
		BuiltAt:      "2026-05-25T17:30:00Z",
		SQLiteKey:    "hansard-search/v1/index.sqlite",
		SQLiteSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	})
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	got := client.inputs[0]
	if got.Key == nil || *got.Key != "hansard-search/v1/manifest.json" {
		t.Fatalf("key = %v", got.Key)
	}
	body, err := io.ReadAll(got.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	if !strings.Contains(string(body), `"sqlite_key": "hansard-search/v1/index.sqlite"`) {
		t.Fatalf("manifest body missing sqlite key: %s", body)
	}
}

type mockPutObjectClient struct {
	inputs []*awss3.PutObjectInput
}

func (m *mockPutObjectClient) PutObject(_ context.Context, input *awss3.PutObjectInput, _ ...func(*awss3.Options)) (*awss3.PutObjectOutput, error) {
	m.inputs = append(m.inputs, input)
	return &awss3.PutObjectOutput{}, nil
}
