package artifacts

import (
	"bytes"
	"context"
	"os"
	"path/filepath"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type Repository struct {
	Dir    string
	Bucket string
	Prefix string
	Client *s3.Client
}

func (r *Repository) Exists(ctx context.Context, key string) (bool, error) {
	if r.Dir != "" {
		path := filepath.Join(r.Dir, filepath.FromSlash(key))
		_, err := os.Stat(path)
		if err == nil {
			return true, nil
		}
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}

	if r.Bucket == "" || r.Client == nil {
		return false, nil
	}

	s3Key := key
	if r.Prefix != "" {
		s3Key = r.Prefix + "/" + key
	}

	_, err := r.Client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(r.Bucket),
		Key:    aws.String(s3Key),
	})
	if err != nil {
		return false, nil
	}
	return true, nil
}

func (r *Repository) Write(ctx context.Context, key string, payload []byte) error {
	if r.Dir != "" {
		path := filepath.Join(r.Dir, filepath.FromSlash(key))
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		return os.WriteFile(path, payload, 0644)
	}

	if r.Bucket == "" || r.Client == nil {
		return nil
	}

	s3Key := key
	if r.Prefix != "" {
		s3Key = r.Prefix + "/" + key
	}

	_, err := r.Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(r.Bucket),
		Key:    aws.String(s3Key),
		Body:   bytes.NewReader(payload),
		ContentType: aws.String("application/json"),
	})
	return err
}
