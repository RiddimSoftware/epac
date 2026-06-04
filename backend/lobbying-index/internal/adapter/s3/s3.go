package s3

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path"
	"strings"

	"epac/lobbying-index/internal/domain"

	"github.com/aws/aws-sdk-go-v2/aws"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

const (
	SQLiteContentType   = "application/x-sqlite3"
	ManifestContentType = "application/json"
	sha256MetaKey       = "content-hash-sha256"
	defaultPrefix       = "lobbying-index/v1"
	intermediateSegment = "tmp"
)

// Client is the S3 surface the Store relies on. The real *s3.Client returned
// by awss3.NewFromConfig satisfies it; tests provide a mock implementation.
type Client interface {
	PutObject(ctx context.Context, params *awss3.PutObjectInput, optFns ...func(*awss3.Options)) (*awss3.PutObjectOutput, error)
	GetObject(ctx context.Context, params *awss3.GetObjectInput, optFns ...func(*awss3.Options)) (*awss3.GetObjectOutput, error)
}

type Store struct {
	client Client
	bucket string
	prefix string
}

func NewStore(client Client, bucket, prefix string) *Store {
	return &Store{
		client: client,
		bucket: strings.TrimSpace(bucket),
		prefix: cleanPrefix(prefix),
	}
}

// Prefix returns the resolved S3 key prefix for this store.
func (s *Store) Prefix() string { return s.prefix }

func (s *Store) Upload(ctx context.Context, localPath, s3Key string) (string, int64, error) {
	if s.client == nil {
		return "", 0, fmt.Errorf("s3 client is required")
	}
	if s.bucket == "" {
		return "", 0, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	hash, err := sha256File(localPath)
	if err != nil {
		return "", 0, err
	}
	file, err := os.Open(localPath)
	if err != nil {
		return "", 0, fmt.Errorf("open sqlite for upload: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return "", 0, fmt.Errorf("stat sqlite for upload: %w", err)
	}
	_, err = s.client.PutObject(ctx, &awss3.PutObjectInput{
		Bucket:               aws.String(s.bucket),
		Key:                  aws.String(cleanKey(s3Key)),
		Body:                 file,
		ContentType:          aws.String(SQLiteContentType),
		ServerSideEncryption: types.ServerSideEncryptionAes256,
		Metadata: map[string]string{
			sha256MetaKey: hash,
		},
	})
	if err != nil {
		return "", 0, fmt.Errorf("put sqlite object: %w", err)
	}
	return hash, info.Size(), nil
}

// IntermediateKey returns the S3 key used for a phase's intermediate
// SQLite working file under <prefix>/tmp/<phaseKey>.sqlite.
func (s *Store) IntermediateKey(phaseKey string) (string, error) {
	clean := strings.TrimSpace(phaseKey)
	if clean == "" {
		return "", fmt.Errorf("phase key is required")
	}
	if strings.ContainsAny(clean, "/\\") {
		return "", fmt.Errorf("phase key must not contain path separators: %q", phaseKey)
	}
	return path.Join(s.prefix, intermediateSegment, clean+".sqlite"), nil
}

// UploadIntermediate uploads a phase's working SQLite file to the intermediate
// prefix and returns the content sha256 and size, matching the integrity
// metadata semantics of Upload.
func (s *Store) UploadIntermediate(ctx context.Context, localPath, phaseKey string) (string, int64, error) {
	key, err := s.IntermediateKey(phaseKey)
	if err != nil {
		return "", 0, err
	}
	return s.Upload(ctx, localPath, key)
}

// DownloadIntermediate streams a phase's working SQLite file from the
// intermediate prefix to localPath. It verifies the streamed bytes against
// the content-hash-sha256 metadata stored at upload time and returns the
// verified hash. If the metadata is missing, the computed hash is returned
// without comparison so callers can decide whether to enforce.
func (s *Store) DownloadIntermediate(ctx context.Context, phaseKey, localPath string) (string, error) {
	if s.client == nil {
		return "", fmt.Errorf("s3 client is required")
	}
	if s.bucket == "" {
		return "", fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	key, err := s.IntermediateKey(phaseKey)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(localPath) == "" {
		return "", fmt.Errorf("local path is required")
	}
	out, err := s.client.GetObject(ctx, &awss3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(cleanKey(key)),
	})
	if err != nil {
		return "", fmt.Errorf("get intermediate object %s: %w", key, err)
	}
	defer out.Body.Close()

	file, err := os.Create(localPath)
	if err != nil {
		return "", fmt.Errorf("create local intermediate file: %w", err)
	}
	defer file.Close()

	hasher := sha256.New()
	if _, err := io.Copy(io.MultiWriter(file, hasher), out.Body); err != nil {
		return "", fmt.Errorf("stream intermediate object: %w", err)
	}
	hash := hex.EncodeToString(hasher.Sum(nil))

	if expected, ok := out.Metadata[sha256MetaKey]; ok && expected != "" && expected != hash {
		return "", fmt.Errorf("intermediate sha256 mismatch for %s: expected %s, got %s", key, expected, hash)
	}
	return hash, nil
}

func (s *Store) Write(ctx context.Context, manifest domain.Manifest) error {
	if s.client == nil {
		return fmt.Errorf("s3 client is required")
	}
	if s.bucket == "" {
		return fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal manifest: %w", err)
	}
	_, err = s.client.PutObject(ctx, &awss3.PutObjectInput{
		Bucket:               aws.String(s.bucket),
		Key:                  aws.String(path.Join(s.prefix, "manifest.json")),
		Body:                 bytes.NewReader(data),
		ContentType:          aws.String(ManifestContentType),
		ServerSideEncryption: types.ServerSideEncryptionAes256,
	})
	if err != nil {
		return fmt.Errorf("put manifest object: %w", err)
	}
	return nil
}

func sha256File(filePath string) (string, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("open file for hashing: %w", err)
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("hash file: %w", err)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func cleanPrefix(prefix string) string {
	prefix = strings.Trim(strings.TrimSpace(prefix), "/")
	if prefix == "" || prefix == "." {
		return defaultPrefix
	}
	return prefix
}

func cleanKey(key string) string {
	return strings.TrimLeft(path.Clean("/"+strings.TrimSpace(key)), "/")
}
