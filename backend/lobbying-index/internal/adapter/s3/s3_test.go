package s3

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"epac/lobbying-index/internal/domain"

	"github.com/aws/aws-sdk-go-v2/aws"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

func TestUploadWritesSQLiteWithContentTypeEncryptionAndHashMetadata(t *testing.T) {
	path := filepath.Join(t.TempDir(), "index.sqlite")
	body := []byte("sqlite bytes")
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatalf("write sqlite: %v", err)
	}
	client := &mockClient{}
	store := NewStore(client, "bucket", "lobbying-index/v1")

	hash, size, err := store.Upload(context.Background(), path, "lobbying-index/v1/index.sqlite")
	if err != nil {
		t.Fatalf("Upload: %v", err)
	}
	if size != int64(len(body)) {
		t.Fatalf("size = %d", size)
	}
	if len(hash) != 64 {
		t.Fatalf("hash = %q", hash)
	}
	if len(client.putInputs) != 1 {
		t.Fatalf("expected 1 PutObject call, got %d", len(client.putInputs))
	}
	got := client.putInputs[0]
	if got.ContentType == nil || *got.ContentType != SQLiteContentType {
		t.Fatalf("content type = %v", got.ContentType)
	}
	if got.ServerSideEncryption != types.ServerSideEncryptionAes256 {
		t.Fatalf("encryption = %v", got.ServerSideEncryption)
	}
	if got.Metadata[sha256MetaKey] != hash {
		t.Fatalf("metadata hash = %q", got.Metadata[sha256MetaKey])
	}
}

func TestWriteUploadsManifestAtPrefixAfterMarshal(t *testing.T) {
	client := &mockClient{}
	store := NewStore(client, "bucket", "lobbying-index/v1")

	err := store.Write(context.Background(), domain.Manifest{
		Version:      "v1",
		BuiltAt:      "2026-05-25T17:30:00Z",
		SQLiteKey:    "lobbying-index/v1/index.sqlite",
		SQLiteSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	})
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	got := client.putInputs[0]
	if got.Key == nil || *got.Key != "lobbying-index/v1/manifest.json" {
		t.Fatalf("key = %v", got.Key)
	}
	if got.ServerSideEncryption != types.ServerSideEncryptionAes256 {
		t.Fatalf("encryption = %v", got.ServerSideEncryption)
	}
	body, err := io.ReadAll(got.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	if !strings.Contains(string(body), `"sqlite_key": "lobbying-index/v1/index.sqlite"`) {
		t.Fatalf("manifest body missing sqlite key: %s", body)
	}
}

func TestIntermediateKey(t *testing.T) {
	store := NewStore(&mockClient{}, "bucket", "lobbying-index/v1")
	cases := []struct {
		name      string
		phaseKey  string
		want      string
		wantError bool
	}{
		{"basic phase", "IngestOCLData", "lobbying-index/v1/tmp/IngestOCLData.sqlite", false},
		{"trims whitespace", "  BuildMPLobbying  ", "lobbying-index/v1/tmp/BuildMPLobbying.sqlite", false},
		{"empty rejected", "", "", true},
		{"whitespace only rejected", "   ", "", true},
		{"forward slash rejected", "foo/bar", "", true},
		{"backslash rejected", "foo\\bar", "", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := store.IntermediateKey(tc.phaseKey)
			if tc.wantError {
				if err == nil {
					t.Fatalf("expected error, got %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Fatalf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestUploadIntermediateWritesUnderTmpPrefixWithIntegrityMetadata(t *testing.T) {
	path := filepath.Join(t.TempDir(), "phase.sqlite")
	body := []byte("intermediate phase bytes")
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatalf("write sqlite: %v", err)
	}
	client := &mockClient{}
	store := NewStore(client, "bucket", "lobbying-index/v1")

	hash, size, err := store.UploadIntermediate(context.Background(), path, "IngestOCLData")
	if err != nil {
		t.Fatalf("UploadIntermediate: %v", err)
	}
	if size != int64(len(body)) {
		t.Fatalf("size = %d", size)
	}
	wantHash := sha256Hex(body)
	if hash != wantHash {
		t.Fatalf("hash = %q, want %q", hash, wantHash)
	}
	if len(client.putInputs) != 1 {
		t.Fatalf("expected 1 PutObject call, got %d", len(client.putInputs))
	}
	got := client.putInputs[0]
	if got.Key == nil || *got.Key != "lobbying-index/v1/tmp/IngestOCLData.sqlite" {
		t.Fatalf("key = %v", got.Key)
	}
	if got.ContentType == nil || *got.ContentType != SQLiteContentType {
		t.Fatalf("content type = %v", got.ContentType)
	}
	if got.ServerSideEncryption != types.ServerSideEncryptionAes256 {
		t.Fatalf("encryption = %v", got.ServerSideEncryption)
	}
	if got.Metadata[sha256MetaKey] != hash {
		t.Fatalf("metadata hash = %q", got.Metadata[sha256MetaKey])
	}
}

func TestUploadIntermediateRejectsEmptyPhase(t *testing.T) {
	store := NewStore(&mockClient{}, "bucket", "lobbying-index/v1")
	if _, _, err := store.UploadIntermediate(context.Background(), "/tmp/whatever", ""); err == nil {
		t.Fatalf("expected error for empty phase key")
	}
}

func TestDownloadIntermediateStreamsBodyAndReturnsHash(t *testing.T) {
	body := []byte("downloaded intermediate bytes")
	wantHash := sha256Hex(body)
	client := &mockClient{
		getResponses: map[string]getResponse{
			"lobbying-index/v1/tmp/BuildMPLobbying.sqlite": {
				body:     body,
				metadata: map[string]string{sha256MetaKey: wantHash},
			},
		},
	}
	store := NewStore(client, "bucket", "lobbying-index/v1")
	dst := filepath.Join(t.TempDir(), "out.sqlite")

	hash, err := store.DownloadIntermediate(context.Background(), "BuildMPLobbying", dst)
	if err != nil {
		t.Fatalf("DownloadIntermediate: %v", err)
	}
	if hash != wantHash {
		t.Fatalf("hash = %q, want %q", hash, wantHash)
	}
	on, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read dst: %v", err)
	}
	if !bytes.Equal(on, body) {
		t.Fatalf("dst contents = %q, want %q", on, body)
	}
	if len(client.getInputs) != 1 {
		t.Fatalf("expected 1 GetObject call, got %d", len(client.getInputs))
	}
	got := client.getInputs[0]
	if got.Bucket == nil || *got.Bucket != "bucket" {
		t.Fatalf("bucket = %v", got.Bucket)
	}
	if got.Key == nil || *got.Key != "lobbying-index/v1/tmp/BuildMPLobbying.sqlite" {
		t.Fatalf("key = %v", got.Key)
	}
}

func TestDownloadIntermediateRejectsHashMismatch(t *testing.T) {
	body := []byte("real bytes")
	client := &mockClient{
		getResponses: map[string]getResponse{
			"lobbying-index/v1/tmp/BuildOrganizationTables.sqlite": {
				body:     body,
				metadata: map[string]string{sha256MetaKey: "00000000000000000000000000000000ffffffffffffffffffffffffffffffff"},
			},
		},
	}
	store := NewStore(client, "bucket", "lobbying-index/v1")
	dst := filepath.Join(t.TempDir(), "out.sqlite")

	if _, err := store.DownloadIntermediate(context.Background(), "BuildOrganizationTables", dst); err == nil || !strings.Contains(err.Error(), "sha256 mismatch") {
		t.Fatalf("expected sha256 mismatch error, got %v", err)
	}
}

func TestDownloadIntermediateAcceptsMissingMetadata(t *testing.T) {
	body := []byte("no metadata bytes")
	client := &mockClient{
		getResponses: map[string]getResponse{
			"lobbying-index/v1/tmp/BuildBillContextTables.sqlite": {body: body},
		},
	}
	store := NewStore(client, "bucket", "lobbying-index/v1")
	dst := filepath.Join(t.TempDir(), "out.sqlite")

	hash, err := store.DownloadIntermediate(context.Background(), "BuildBillContextTables", dst)
	if err != nil {
		t.Fatalf("DownloadIntermediate: %v", err)
	}
	if hash != sha256Hex(body) {
		t.Fatalf("hash = %q", hash)
	}
}

func TestDownloadIntermediateRejectsEmptyPhase(t *testing.T) {
	store := NewStore(&mockClient{}, "bucket", "lobbying-index/v1")
	if _, err := store.DownloadIntermediate(context.Background(), "", "/tmp/out.sqlite"); err == nil {
		t.Fatalf("expected error for empty phase key")
	}
}

func TestDownloadIntermediateRejectsEmptyLocalPath(t *testing.T) {
	store := NewStore(&mockClient{}, "bucket", "lobbying-index/v1")
	if _, err := store.DownloadIntermediate(context.Background(), "IngestOCLData", ""); err == nil {
		t.Fatalf("expected error for empty local path")
	}
}

func TestDownloadIntermediatePropagatesGetError(t *testing.T) {
	client := &mockClient{getErr: errors.New("boom")}
	store := NewStore(client, "bucket", "lobbying-index/v1")
	dst := filepath.Join(t.TempDir(), "out.sqlite")
	if _, err := store.DownloadIntermediate(context.Background(), "IngestOCLData", dst); err == nil || !strings.Contains(err.Error(), "boom") {
		t.Fatalf("expected get error, got %v", err)
	}
}

func sha256Hex(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

type getResponse struct {
	body     []byte
	metadata map[string]string
}

type mockClient struct {
	putInputs    []*awss3.PutObjectInput
	getInputs    []*awss3.GetObjectInput
	getResponses map[string]getResponse
	getErr       error
}

func (m *mockClient) PutObject(_ context.Context, input *awss3.PutObjectInput, _ ...func(*awss3.Options)) (*awss3.PutObjectOutput, error) {
	m.putInputs = append(m.putInputs, input)
	return &awss3.PutObjectOutput{}, nil
}

func (m *mockClient) GetObject(_ context.Context, input *awss3.GetObjectInput, _ ...func(*awss3.Options)) (*awss3.GetObjectOutput, error) {
	m.getInputs = append(m.getInputs, input)
	if m.getErr != nil {
		return nil, m.getErr
	}
	if input.Key == nil {
		return nil, errors.New("nil key")
	}
	resp, ok := m.getResponses[*input.Key]
	if !ok {
		return nil, errors.New("not found")
	}
	out := &awss3.GetObjectOutput{
		Body:          io.NopCloser(bytes.NewReader(resp.body)),
		ContentLength: aws.Int64(int64(len(resp.body))),
	}
	if resp.metadata != nil {
		out.Metadata = resp.metadata
	}
	return out, nil
}
