// Package s3manifest implements ManifestLoader backed by Amazon S3.
package s3manifest

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"epac/hansard-search/internal/domain"
	"epac/hansard-search/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type s3Getter interface {
	GetObject(ctx context.Context, params *s3.GetObjectInput, optFns ...func(*s3.Options)) (*s3.GetObjectOutput, error)
}

// ManifestLoader fetches and parses the hansard-search manifest from S3.
type ManifestLoader struct {
	s3     s3Getter
	bucket string
	key    string
}

// NewManifestLoaderFromEnv constructs a ManifestLoader from environment variables.
// Requires EPAC_ARTIFACT_BUCKET; uses EPAC_HANSARD_SEARCH_PREFIX (default "hansard-search/v1").
func NewManifestLoaderFromEnv(ctx context.Context) (*ManifestLoader, error) {
	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return nil, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	prefix := strings.TrimSpace(os.Getenv("EPAC_HANSARD_SEARCH_PREFIX"))
	if prefix == "" {
		prefix = "hansard-search/v1"
	}
	key := strings.TrimSuffix(prefix, "/") + "/manifest.json"

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return NewManifestLoader(s3.NewFromConfig(cfg), bucket, key), nil
}

// NewManifestLoader constructs a ManifestLoader from explicit dependencies (for testing).
func NewManifestLoader(s3Client s3Getter, bucket, key string) *ManifestLoader {
	return &ManifestLoader{s3: s3Client, bucket: bucket, key: key}
}

// Load fetches s3://bucket/key and parses it as a Manifest.
// Returns usecase.ErrManifestNotFound on S3 404.
func (l *ManifestLoader) Load(ctx context.Context) (domain.Manifest, error) {
	out, err := l.s3.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(l.bucket),
		Key:    aws.String(l.key),
	})
	if isNotFound(err) {
		return domain.Manifest{}, usecase.ErrManifestNotFound
	}
	if err != nil {
		return domain.Manifest{}, fmt.Errorf("s3 get manifest %s/%s: %w", l.bucket, l.key, err)
	}
	defer out.Body.Close()

	body, err := io.ReadAll(out.Body)
	if err != nil {
		return domain.Manifest{}, fmt.Errorf("read manifest body: %w", err)
	}

	var m domain.Manifest
	if err := json.Unmarshal(body, &m); err != nil {
		return domain.Manifest{}, fmt.Errorf("decode manifest: %w", err)
	}
	return m, nil
}

func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	var nsk *s3types.NoSuchKey
	if errors.As(err, &nsk) {
		return true
	}
	return false
}
