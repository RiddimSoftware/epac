// live-vote-poller Lambda — checks Parliament's live division status during
// sitting hours and emits push-dispatcher events when a vote concludes.
//
// The composition root wires HandleRequest through observability.WrapNoEvent
// so EventBridge cron invocations and acceptance tests share the same path.
//
// Implementation pending — see EPAC-2261.
package main

import (
	"context"

	"epac/observability"

	"github.com/aws/aws-lambda-go/lambda"
)

const pipelineName = "live-vote-poller"

func main() {
	lambda.Start(observability.WrapNoEvent(pipelineName, HandleRequest))
}

func HandleRequest(_ context.Context) error {
	return nil
}
