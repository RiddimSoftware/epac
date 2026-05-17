package manifest

import (
	"bytes"
	"context"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	manifestKey          = "manifest.json"
	manifestContentType  = "application/json"
	manifestCacheControl = "public, max-age=60"

	// sha256MetaKey is the S3 user-metadata key written by artifact publishers.
	// S3 stores it as x-amz-meta-content-hash-sha256; the SDK returns it
	// lowercased without the x-amz-meta- prefix.
	sha256MetaKey = "content-hash-sha256"
)

// S3ArtifactStore implements ArtifactStore using AWS S3.
type S3ArtifactStore struct {
	client *s3.Client
}

// NewS3ArtifactStore creates a store using the default AWS credential chain.
func NewS3ArtifactStore(ctx context.Context) (*S3ArtifactStore, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return &S3ArtifactStore{client: s3.NewFromConfig(cfg)}, nil
}

// ListObjects pages through the bucket and returns all objects except manifest.json.
func (s *S3ArtifactStore) ListObjects(ctx context.Context, bucket string) ([]ObjectInfo, error) {
	var objects []ObjectInfo
	paginator := s3.NewListObjectsV2Paginator(s.client, &s3.ListObjectsV2Input{
		Bucket: aws.String(bucket),
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("list objects page: %w", err)
		}
		for _, obj := range page.Contents {
			key := aws.ToString(obj.Key)
			if key == manifestKey {
				continue
			}
			objects = append(objects, ObjectInfo{
				Key:          key,
				SizeBytes:    aws.ToInt64(obj.Size),
				ETag:         aws.ToString(obj.ETag),
				LastModified: aws.ToTime(obj.LastModified),
			})
		}
	}
	return objects, nil
}

// HeadObject fetches the content-hash-sha256 user metadata for a single key.
func (s *S3ArtifactStore) HeadObject(ctx context.Context, bucket, key string) (ObjectMeta, error) {
	out, err := s.client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return ObjectMeta{}, fmt.Errorf("head object %q: %w", key, err)
	}
	return ObjectMeta{
		ContentHashSHA256: strings.TrimSpace(out.Metadata[sha256MetaKey]),
	}, nil
}

// PutManifest writes manifest.json to the bucket root with a short cache TTL.
func (s *S3ArtifactStore) PutManifest(ctx context.Context, bucket string, data []byte) error {
	_, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:       aws.String(bucket),
		Key:          aws.String(manifestKey),
		Body:         bytes.NewReader(data),
		ContentType:  aws.String(manifestContentType),
		CacheControl: aws.String(manifestCacheControl),
	})
	if err != nil {
		return fmt.Errorf("put manifest.json: %w", err)
	}
	return nil
}
