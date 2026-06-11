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

	"epac/bills-indexer/internal/domain"

	"github.com/aws/aws-sdk-go-v2/aws"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

const (
	SQLiteContentType   = "application/x-sqlite3"
	ManifestContentType = "application/json"
	sha256MetaKey       = "content-hash-sha256"
)

type PutObjectClient interface {
	PutObject(ctx context.Context, input *awss3.PutObjectInput, optFns ...func(*awss3.Options)) (*awss3.PutObjectOutput, error)
}

type Store struct {
	client PutObjectClient
	bucket string
	prefix string
	logger func(map[string]any)
}

type Option func(*Store)

func WithLogger(logger func(map[string]any)) Option {
	return func(s *Store) {
		s.logger = logger
	}
}

func NewStore(client PutObjectClient, bucket, prefix string, opts ...Option) *Store {
	s := &Store{
		client: client,
		bucket: strings.TrimSpace(bucket),
		prefix: cleanPrefix(prefix),
	}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

func (s *Store) Upload(ctx context.Context, localPath, key string) (string, int64, error) {
	if s.client == nil {
		return "", 0, fmt.Errorf("s3 client is required")
	}
	if s.bucket == "" {
		return "", 0, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	hash, size, body, err := fileBody(localPath)
	if err != nil {
		return "", 0, err
	}
	defer body.Close()

	if s.logger != nil {
		s.logger(map[string]any{
			"pipeline": "bills-indexer",
			"event":    "upload_started",
		})
	}

	_, err = s.client.PutObject(ctx, &awss3.PutObjectInput{
		Bucket:               aws.String(s.bucket),
		Key:                  aws.String(cleanKey(key)),
		Body:                 body,
		ContentType:          aws.String(SQLiteContentType),
		ServerSideEncryption: types.ServerSideEncryptionAes256,
		Metadata: map[string]string{
			sha256MetaKey: hash,
		},
	})
	if err != nil {
		return "", 0, fmt.Errorf("put sqlite object: %w", err)
	}
	return hash, size, nil
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

func fileBody(localPath string) (string, int64, *os.File, error) {
	file, err := os.Open(localPath)
	if err != nil {
		return "", 0, nil, fmt.Errorf("open sqlite for upload: %w", err)
	}
	hash := sha256.New()
	size, err := io.Copy(hash, file)
	if err != nil {
		file.Close()
		return "", 0, nil, fmt.Errorf("hash sqlite for upload: %w", err)
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		file.Close()
		return "", 0, nil, fmt.Errorf("rewind sqlite for upload: %w", err)
	}
	return hex.EncodeToString(hash.Sum(nil)), size, file, nil
}

func cleanPrefix(prefix string) string {
	prefix = strings.Trim(strings.TrimSpace(prefix), "/")
	if prefix == "" || prefix == "." {
		return "bills/v1"
	}
	return prefix
}

func cleanKey(key string) string {
	return strings.TrimLeft(path.Clean("/"+strings.TrimSpace(key)), "/")
}
