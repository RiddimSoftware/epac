package s3

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"epac/bills-indexer/internal/domain"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

func TestStoreUploadsSQLiteAndManifest(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "bills.db")
	if err := os.WriteFile(dbPath, []byte("sqlite bytes"), 0o644); err != nil {
		t.Fatalf("write db: %v", err)
	}
	client := &fakePutObject{}
	store := NewStore(client, "bucket", "bills/v1")

	hash, size, err := store.Upload(context.Background(), dbPath, "bills/v1/index.sqlite")
	if err != nil {
		t.Fatalf("Upload: %v", err)
	}
	if len(hash) != 64 || size != int64(len("sqlite bytes")) {
		t.Fatalf("hash/size = %s/%d", hash, size)
	}
	if got := client.inputs[0]; got.Metadata[sha256MetaKey] != hash {
		t.Fatalf("metadata = %#v", got.Metadata)
	}

	if err := store.Write(context.Background(), domain.Manifest{Version: "v1", SQLiteKey: "bills/v1/index.sqlite"}); err != nil {
		t.Fatalf("Write: %v", err)
	}
	body, err := io.ReadAll(client.inputs[1].Body)
	if err != nil {
		t.Fatalf("read manifest body: %v", err)
	}
	if !strings.Contains(string(body), `"sqlite_key": "bills/v1/index.sqlite"`) {
		t.Fatalf("manifest body = %s", body)
	}
}

type fakePutObject struct {
	inputs []*awss3.PutObjectInput
}

func (f *fakePutObject) PutObject(_ context.Context, input *awss3.PutObjectInput, _ ...func(*awss3.Options)) (*awss3.PutObjectOutput, error) {
	f.inputs = append(f.inputs, input)
	return &awss3.PutObjectOutput{}, nil
}
