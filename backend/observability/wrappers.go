package observability

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
)

func WrapAPIGateway(service string, handler func(context.Context, events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error)) func(context.Context, events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	return func(ctx context.Context, req events.APIGatewayProxyRequest) (resp events.APIGatewayProxyResponse, err error) {
		defer recoverPanic(&err)

		if limitedResp, limited := CheckAPIGatewayRateLimit(req); limited {
			return limitedResp, nil
		}

		return handler(ctx, req)
	}
}

func WrapAPIGatewayV2(service string, handler func(context.Context, events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error)) func(context.Context, events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	return func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (resp events.APIGatewayV2HTTPResponse, err error) {
		defer recoverPanic(&err)

		if limitedResp, limited := CheckAPIGatewayV2RateLimit(req); limited {
			return limitedResp, nil
		}

		return handler(ctx, req)
	}
}

func WrapEvent[T any](service string, handler func(context.Context, T) error) func(context.Context, T) error {
	return func(ctx context.Context, req T) (err error) {
		defer recoverPanic(&err)

		return handler(ctx, req)
	}
}

func WrapNoEvent(service string, handler func(context.Context) error) func(context.Context) error {
	return func(ctx context.Context) (err error) {
		defer recoverPanic(&err)

		return handler(ctx)
	}
}

func recoverPanic(err *error) {
	if recovered := recover(); recovered != nil {
		*err = fmt.Errorf("panic: %v", recovered)
	}
}
