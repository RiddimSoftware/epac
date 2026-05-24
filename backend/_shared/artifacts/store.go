package artifacts

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/smithy-go"
)

var ErrNotFound = errors.New("artifact not found")

type Store interface {
	Get(ctx context.Context, key string) ([]byte, error)
}

type S3Getter interface {
	GetObject(ctx context.Context, params *s3.GetObjectInput, optFns ...func(*s3.Options)) (*s3.GetObjectOutput, error)
}

type Config struct {
	Bucket   string
	Prefix   string
	LocalDir string
}

type ObjectStore struct {
	client   S3Getter
	bucket   string
	prefix   string
	localDir string
}

func NewFromEnv(ctx context.Context) (Store, error) {
	cfg := ConfigFromEnv()
	if strings.TrimSpace(cfg.LocalDir) != "" {
		return NewLocalStore(cfg.LocalDir), nil
	}
	if strings.TrimSpace(cfg.Bucket) == "" {
		return nil, fmt.Errorf("artifact bucket not configured; set EPAC_ARTIFACT_BUCKET or ARTIFACT_BUCKET")
	}
	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return NewS3Store(s3.NewFromConfig(awsCfg), cfg.Bucket, cfg.Prefix), nil
}

func ConfigFromEnv() Config {
	return Config{
		Bucket:   firstEnv("EPAC_ARTIFACT_BUCKET", "ARTIFACT_BUCKET"),
		Prefix:   firstEnv("EPAC_ARTIFACT_PREFIX", "ARTIFACT_PREFIX"),
		LocalDir: firstEnv("EPAC_ARTIFACTS_DIR", "ARTIFACTS_DIR"),
	}
}

func NewS3Store(client S3Getter, bucket, prefix string) *ObjectStore {
	return &ObjectStore{
		client: client,
		bucket: strings.TrimSpace(bucket),
		prefix: cleanPrefix(prefix),
	}
}

func NewLocalStore(localDir string) *ObjectStore {
	return &ObjectStore{localDir: strings.TrimSpace(localDir)}
}

func (s *ObjectStore) Get(ctx context.Context, key string) ([]byte, error) {
	cleanKey, err := CleanKey(key)
	if err != nil {
		return nil, err
	}
	if s.localDir != "" {
		return s.getLocal(cleanKey)
	}
	return s.getS3(ctx, cleanKey)
}

func CleanKey(key string) (string, error) {
	key = strings.TrimSpace(key)
	if key == "" {
		return "", fmt.Errorf("artifact key is empty")
	}
	cleaned := path.Clean("/" + key)
	cleaned = strings.TrimPrefix(cleaned, "/")
	if cleaned == "" || cleaned == "." {
		return "", fmt.Errorf("artifact key is empty")
	}
	return cleaned, nil
}

func IsNotFound(err error) bool {
	if errors.Is(err, ErrNotFound) || errors.Is(err, os.ErrNotExist) {
		return true
	}
	var apiErr smithy.APIError
	if errors.As(err, &apiErr) {
		switch apiErr.ErrorCode() {
		case "NoSuchKey", "NotFound", "NoSuchBucket":
			return true
		}
	}
	return false
}

func (s *ObjectStore) getLocal(key string) ([]byte, error) {
	base, err := filepath.Abs(s.localDir)
	if err != nil {
		return nil, fmt.Errorf("resolve artifact dir: %w", err)
	}
	fullPath, err := filepath.Abs(filepath.Join(base, filepath.FromSlash(key)))
	if err != nil {
		return nil, fmt.Errorf("resolve artifact path: %w", err)
	}
	if fullPath != base && !strings.HasPrefix(fullPath, base+string(os.PathSeparator)) {
		return nil, fmt.Errorf("artifact key escapes local dir")
	}
	data, err := os.ReadFile(fullPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("%w: %s", ErrNotFound, key)
		}
		return nil, err
	}
	return data, nil
}

func (s *ObjectStore) getS3(ctx context.Context, key string) ([]byte, error) {
	if s.client == nil {
		return nil, fmt.Errorf("s3 client not configured")
	}
	if s.bucket == "" {
		return nil, fmt.Errorf("s3 bucket not configured")
	}
	out, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(joinKey(s.prefix, key)),
	})
	if err != nil {
		if IsNotFound(err) {
			return nil, fmt.Errorf("%w: %s", ErrNotFound, key)
		}
		return nil, err
	}
	defer out.Body.Close()
	return io.ReadAll(out.Body)
}

func joinKey(prefix, key string) string {
	prefix = cleanPrefix(prefix)
	if prefix == "" {
		return key
	}
	return prefix + "/" + strings.TrimLeft(key, "/")
}

func cleanPrefix(prefix string) string {
	return strings.Trim(strings.TrimSpace(prefix), "/")
}

func firstEnv(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}
