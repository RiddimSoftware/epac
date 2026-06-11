package main

import (
	"context"
	"net/http"
	"os"
	"time"

	"epac/backend/live-vote-poller/internal/adapter/artifacts"
	"epac/backend/live-vote-poller/internal/adapter/ourcommons"
	"epac/backend/live-vote-poller/internal/adapter/push"
	"epac/backend/live-vote-poller/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

const pipelineName = "live-vote-poller"

func main() {
	lambda.Start(observability.WrapNoEvent(pipelineName, HandleRequest))
}

var clock = time.Now

type funcClock func() time.Time

func (f funcClock) Now() time.Time {
	return f()
}

func HandleRequest(ctx context.Context) error {
	parliamentURL := os.Getenv("EPAC_PARLIAMENT_DIVISIONS_URL")
	if parliamentURL == "" {
		parliamentURL = "https://www.ourcommons.ca/members/en/votes/api/divisions"
	}

	dispatcherURL := os.Getenv("EPAC_PUSH_DISPATCHER_URL")
	artifactsDir := os.Getenv("EPAC_ARTIFACTS_DIR")
	bucket := os.Getenv("EPAC_ARTIFACT_BUCKET")
	prefix := os.Getenv("EPAC_ARTIFACT_PREFIX")

	var s3Client *s3.Client
	if bucket != "" {
		cfg, err := config.LoadDefaultConfig(ctx)
		if err != nil {
			return err
		}
		s3Client = s3.NewFromConfig(cfg)
	}

	uc := &usecase.PollLiveDivisions{
		Fetcher: &ourcommons.DivisionsClient{
			URL:    parliamentURL,
			Client: http.DefaultClient,
		},
		Repository: &artifacts.Repository{
			Dir:    artifactsDir,
			Bucket: bucket,
			Prefix: prefix,
			Client: s3Client,
		},
		Dispatcher: &push.Dispatcher{
			URL:    dispatcherURL,
			Client: http.DefaultClient,
		},
		Clock: funcClock(clock),
	}

	return uc.Execute(ctx)
}
