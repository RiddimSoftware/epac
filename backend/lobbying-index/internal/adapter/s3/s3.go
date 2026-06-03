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
)

type PutObjectClient interface {
	PutObject(ctx context.Context, params *awss3.PutObjectInput, optFns ...func(*awss3.Options)) (*awss3.PutObjectOutput, error)
}

type Store struct {
	client PutObjectClient
	bucket string
	prefix string
}

func NewStore(client PutObjectClient, bucket, prefix string) *Store {
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
