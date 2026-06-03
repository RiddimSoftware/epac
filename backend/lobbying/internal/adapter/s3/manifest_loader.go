// Package s3 implements lobbying-index artifact loading from Amazon S3.
package s3

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"epac/lobbying/domain"
	"epac/lobbying/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type getter interface {
	GetObject(ctx context.Context, params *s3.GetObjectInput, optFns ...func(*s3.Options)) (*s3.GetObjectOutput, error)
}

type ManifestLoader struct {
	s3     getter
	bucket string
	key    string
}

func NewManifestLoaderFromEnv(ctx context.Context) (*ManifestLoader, error) {
	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return nil, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	prefix := strings.TrimSpace(os.Getenv("LOBBYING_INDEX_PREFIX"))
	if prefix == "" {
		return nil, fmt.Errorf("LOBBYING_INDEX_PREFIX is required")
	}
	key := strings.TrimSuffix(prefix, "/") + "/manifest.json"

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return NewManifestLoader(s3.NewFromConfig(cfg), bucket, key), nil
}

func NewManifestLoader(s3Client getter, bucket, key string) *ManifestLoader {
	return &ManifestLoader{s3: s3Client, bucket: bucket, key: key}
}

func (l *ManifestLoader) Load(ctx context.Context) (domain.LobbyingIndexManifest, error) {
	out, err := l.s3.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(l.bucket),
		Key:    aws.String(l.key),
	})
	if isNotFound(err) {
		return domain.LobbyingIndexManifest{}, usecase.ErrManifestNotFound
	}
	if err != nil {
		return domain.LobbyingIndexManifest{}, fmt.Errorf("s3 get manifest %s/%s: %w", l.bucket, l.key, err)
	}
	defer out.Body.Close()

	body, err := io.ReadAll(out.Body)
	if err != nil {
		return domain.LobbyingIndexManifest{}, fmt.Errorf("read manifest body: %w", err)
	}

	var manifest domain.LobbyingIndexManifest
	if err := json.Unmarshal(body, &manifest); err != nil {
		return domain.LobbyingIndexManifest{}, fmt.Errorf("decode manifest: %w", err)
	}
	return manifest, nil
}

func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	var noSuchKey *s3types.NoSuchKey
	return errors.As(err, &noSuchKey)
}
