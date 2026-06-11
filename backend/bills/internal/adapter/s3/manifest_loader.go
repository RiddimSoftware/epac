package s3

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"epac/bills/internal/domain"
	"epac/bills/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
)

const defaultBillsPrefix = "bills/v1"

type getter interface {
	GetObject(ctx context.Context, params *s3.GetObjectInput, optFns ...func(*s3.Options)) (*s3.GetObjectOutput, error)
}

type ManifestLoader struct {
	s3     getter
	bucket string
	key    string
}

type LocalManifestLoader struct {
	path string
}

func NewManifestLoaderFromEnv(ctx context.Context) (usecase.ManifestLoader, error) {
	prefix := billsPrefixFromEnv()
	key := strings.TrimSuffix(prefix, "/") + "/manifest.json"
	if dir := strings.TrimSpace(os.Getenv("EPAC_ARTIFACTS_DIR")); dir != "" {
		return NewLocalManifestLoader(filepath.Join(dir, filepath.FromSlash(key))), nil
	}

	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return nil, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return NewManifestLoader(s3.NewFromConfig(cfg), bucket, key), nil
}

func NewManifestLoader(s3Client getter, bucket, key string) *ManifestLoader {
	return &ManifestLoader{s3: s3Client, bucket: bucket, key: key}
}

func NewLocalManifestLoader(path string) *LocalManifestLoader {
	return &LocalManifestLoader{path: path}
}

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
	return decodeManifest(out.Body)
}

func (l *LocalManifestLoader) Load(ctx context.Context) (domain.Manifest, error) {
	file, err := os.Open(l.path)
	if errors.Is(err, os.ErrNotExist) {
		return domain.Manifest{}, usecase.ErrManifestNotFound
	}
	if err != nil {
		return domain.Manifest{}, fmt.Errorf("open local manifest %s: %w", l.path, err)
	}
	defer file.Close()
	return decodeManifest(file)
}

func decodeManifest(r io.Reader) (domain.Manifest, error) {
	body, err := io.ReadAll(r)
	if err != nil {
		return domain.Manifest{}, fmt.Errorf("read manifest body: %w", err)
	}
	var manifest domain.Manifest
	if err := json.Unmarshal(body, &manifest); err != nil {
		return domain.Manifest{}, fmt.Errorf("decode manifest: %w", err)
	}
	return manifest, nil
}

func billsPrefixFromEnv() string {
	for _, key := range []string{"BILLS_INDEX_PREFIX", "EPAC_BILLS_INDEX_PREFIX"} {
		if value := strings.TrimSpace(os.Getenv(key)); value != "" {
			return strings.Trim(value, "/")
		}
	}
	return defaultBillsPrefix
}

func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	var noSuchKey *s3types.NoSuchKey
	return errors.As(err, &noSuchKey)
}
