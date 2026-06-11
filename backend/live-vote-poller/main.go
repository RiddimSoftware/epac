package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"

	"epac/observability"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

const pipelineName = "live-vote-poller"

func main() {
	lambda.Start(observability.WrapNoEvent(pipelineName, HandleRequest))
}

func HandleRequest(ctx context.Context) error {
	parliamentURL := os.Getenv("EPAC_PARLIAMENT_DIVISIONS_URL")
	if parliamentURL == "" {
		parliamentURL = "https://www.ourcommons.ca/members/en/votes/api/divisions"
	}

	resp, err := http.Get(parliamentURL)
	if err != nil {
		return fmt.Errorf("fetch parliament divisions: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("parliament API returned %d", resp.StatusCode)
	}

	var data struct {
		Divisions []map[string]any `json:"divisions"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return fmt.Errorf("decode parliament response: %w", err)
	}

	for _, div := range data.Divisions {
		status, _ := div["status"].(string)
		if status != "concluded" {
			continue
		}

		divID, _ := div["division_id"].(float64)
		parl, _ := div["parliament"].(float64)
		sess, _ := div["session"].(float64)

		if divID == 0 || parl == 0 || sess == 0 {
			// Skip malformed division
			continue
		}

		if err := processConcludedDivision(ctx, div, int(parl), int(sess), int(divID)); err != nil {
			return fmt.Errorf("process division %d: %w", int(divID), err)
		}
	}

	return nil
}

func processConcludedDivision(ctx context.Context, div map[string]any, parl, sess, divID int) error {
	key := fmt.Sprintf("votes/live/%d-%d-%d.json", parl, sess, divID)
	
	exists, err := artifactExists(ctx, key)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}

	payload, err := json.Marshal(div)
	if err != nil {
		return err
	}
	if err := writeArtifact(ctx, key, payload); err != nil {
		return err
	}

	dispatcherURL := os.Getenv("EPAC_PUSH_DISPATCHER_URL")
	if dispatcherURL != "" {
		req, err := http.NewRequestWithContext(ctx, "POST", dispatcherURL, bytes.NewReader(payload))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			return err
		}
		defer res.Body.Close()
		if res.StatusCode != http.StatusAccepted && res.StatusCode != http.StatusOK {
			return fmt.Errorf("dispatcher returned %d", res.StatusCode)
		}
	}

	return nil
}

func artifactExists(ctx context.Context, key string) (bool, error) {
	artifactsDir := os.Getenv("EPAC_ARTIFACTS_DIR")
	if artifactsDir != "" {
		path := filepath.Join(artifactsDir, filepath.FromSlash(key))
		_, err := os.Stat(path)
		if err == nil {
			return true, nil
		}
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}

	bucket := os.Getenv("EPAC_ARTIFACT_BUCKET")
	if bucket == "" {
		return false, nil 
	}

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return false, err
	}
	client := s3.NewFromConfig(cfg)
	
	prefix := os.Getenv("EPAC_ARTIFACT_PREFIX")
	s3Key := key
	if prefix != "" {
		s3Key = prefix + "/" + key
	}

	_, err = client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(s3Key),
	})
	if err != nil {
		return false, nil 
	}
	return true, nil
}

func writeArtifact(ctx context.Context, key string, payload []byte) error {
	artifactsDir := os.Getenv("EPAC_ARTIFACTS_DIR")
	if artifactsDir != "" {
		path := filepath.Join(artifactsDir, filepath.FromSlash(key))
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		return os.WriteFile(path, payload, 0644)
	}

	bucket := os.Getenv("EPAC_ARTIFACT_BUCKET")
	if bucket == "" {
		return nil
	}

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return err
	}
	client := s3.NewFromConfig(cfg)
	
	prefix := os.Getenv("EPAC_ARTIFACT_PREFIX")
	s3Key := key
	if prefix != "" {
		s3Key = prefix + "/" + key
	}

	_, err = client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(s3Key),
		Body:   bytes.NewReader(payload),
		ContentType: aws.String("application/json"),
	})
	return err
}
