# Makefile for deploying Go Lambda functions

.PHONY: create-lambda update-lambda build test package clean create-api delete-api add-endpoint schedule-lambda schedule-rate-lambda

# AWS Role ARN for the Lambda function. Can be overridden on the command line or set as an environment variable.
ROLE_ARN ?= arn:aws:iam::227530433709:role/epac-lambda-role

# Run tests for a service
# Usage: make test SERVICE=health
test:
	@if [ -z "$(SERVICE)" ]; then echo "Error: SERVICE parameter is required. Example: make test SERVICE=health"; exit 1; fi
	cd $(SERVICE) && go test ./...

# Build the Lambda binary for Linux ARM64 (recommended for AL2023)
# Usage: make build SERVICE=health
build:
	@if [ -z "$(SERVICE)" ]; then echo "Error: SERVICE parameter is required. Example: make build SERVICE=health"; exit 1; fi
	@echo "Building binary for $(SERVICE)..."
	cd $(SERVICE) && GOOS=linux GOARCH=arm64 go build -tags lambda.norpc -o bootstrap .

# Package the binary into a zip file
# Usage: make package SERVICE=health
package: build
	@echo "Packaging $(SERVICE)..."
	cd $(SERVICE) && zip -q function.zip bootstrap

# Create a new Lambda function on AWS
# Usage: make create-lambda SERVICE=health ROLE_ARN=arn:aws:iam::...
create-lambda: package
	@if [ -z "$(ROLE_ARN)" ]; then echo "Error: ROLE_ARN is not set. Provide it as ROLE_ARN=... or set AWS_ROLE_ARN environment variable"; exit 1; fi
	@echo "Creating Lambda function $(SERVICE)..."
	aws lambda create-function \
		--function-name $(SERVICE) \
		--runtime provided.al2023 \
		--architecture arm64 \
		--handler bootstrap \
		--role $(ROLE_ARN) \
		--zip-file fileb://$(SERVICE)/function.zip

# Update an existing Lambda function's code
# Usage: make update-lambda SERVICE=health
update-lambda: package
	@echo "Updating Lambda function $(SERVICE)..."
	aws lambda update-function-code \
		--function-name $(SERVICE) \
		--zip-file fileb://$(SERVICE)/function.zip

# Create an HTTP API Gateway for the Lambda function
# Usage: make create-api SERVICE=health
create-api:
	@if [ -z "$(SERVICE)" ]; then echo "Error: SERVICE parameter is required."; exit 1; fi
	@echo "Creating API Gateway for $(SERVICE)..."
	@API_ID=$$(aws apigatewayv2 create-api --name $(SERVICE)-api --protocol-type HTTP --query 'ApiId' --output text); \
	echo "API ID: $$API_ID"; \
	aws apigatewayv2 create-stage --api-id $$API_ID --stage-name staging --auto-deploy > /dev/null; \
	aws apigatewayv2 create-stage --api-id $$API_ID --stage-name production --no-auto-deploy > /dev/null; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	REGION=$$(aws configure get region); \
	REGION=$${REGION:-us-east-1}; \
	echo "API Gateway created successfully."; \
	echo "Staging URL: https://$$API_ID.execute-api.$$REGION.amazonaws.com/staging"; \
	echo "Production URL: https://$$API_ID.execute-api.$$REGION.amazonaws.com/production"

# Add an endpoint to the API Gateway that calls a Lambda function
# Usage: make add-endpoint ENDPOINT_NAME=health LAMBDA_ARN=arn:aws:lambda:... [SERVICE=health] [API_ID=...]
add-endpoint:
	@if [ -z "$(ENDPOINT_NAME)" ]; then echo "Error: ENDPOINT_NAME is required."; exit 1; fi
	@if [ -z "$(LAMBDA_ARN)" ]; then echo "Error: LAMBDA_ARN is required."; exit 1; fi
	@API_ID_VAL=$(API_ID); \
	if [ -z "$$API_ID_VAL" ]; then \
		SERVICE_NAME=$(SERVICE); if [ -z "$$SERVICE_NAME" ]; then SERVICE_NAME=$(ENDPOINT_NAME); fi; \
		API_ID_VAL=$$(aws apigatewayv2 get-apis --query "Items[?Name=='$$SERVICE_NAME-api'].ApiId" --output text); \
	fi; \
	if [ "$$API_ID_VAL" = "None" ] || [ -z "$$API_ID_VAL" ]; then echo "Error: API Gateway ID not found."; exit 1; fi; \
	echo "Adding endpoint /$(ENDPOINT_NAME) to API $$API_ID_VAL..."; \
	INTEGRATION_ID=$$(aws apigatewayv2 create-integration \
		--api-id $$API_ID_VAL \
		--integration-type AWS_PROXY \
		--integration-uri $(LAMBDA_ARN) \
		--payload-format-version 2.0 \
		--query 'IntegrationId' --output text); \
	aws apigatewayv2 create-route \
		--api-id $$API_ID_VAL \
		--route-key "ANY /$(ENDPOINT_NAME)" \
		--target integrations/$$INTEGRATION_ID > /dev/null; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	REGION=$$(aws configure get region); \
	REGION=$${REGION:-us-east-1}; \
	aws lambda add-permission \
		--function-name $(LAMBDA_ARN) \
		--statement-id apigateway-$(ENDPOINT_NAME) \
		--action lambda:InvokeFunction \
		--principal apigateway.amazonaws.com \
		--source-arn "arn:aws:execute-api:$$REGION:$$ACCOUNT_ID:$$API_ID_VAL/*/*/$(ENDPOINT_NAME)" > /dev/null 2>&1 || true; \
	echo "Endpoint /$(ENDPOINT_NAME) added successfully."

# Delete the HTTP API Gateway for the Lambda function
# Usage: make delete-api SERVICE=health
delete-api:
	@if [ -z "$(SERVICE)" ]; then echo "Error: SERVICE parameter is required."; exit 1; fi
	@echo "Deleting API Gateway for $(SERVICE)..."
	@API_ID=$$(aws apigatewayv2 get-apis --query "Items[?Name=='$(SERVICE)-api'].ApiId" --output text); \
	if [ "$$API_ID" != "None" ] && [ -n "$$API_ID" ]; then \
		aws apigatewayv2 delete-api --api-id $$API_ID; \
		echo "API Gateway $$API_ID deleted."; \
	else \
		echo "API Gateway $(SERVICE)-api not found."; \
	fi
	@echo "Removing Lambda permission..."
	@aws lambda remove-permission --function-name $(SERVICE) --statement-id apigateway-$(SERVICE) 2>/dev/null || echo "Permission not found or already removed."

# Clean up build artifacts
# Usage: make clean SERVICE=health
clean:
	@if [ -n "$(SERVICE)" ]; then \
		rm -f $(SERVICE)/bootstrap $(SERVICE)/$(SERVICE).zip; \
	fi

# Schedule a Lambda function to run daily at a specific time
# Usage: make schedule-lambda SERVICE=daily-fetch TIME=0800
schedule-lambda:
	@if [ -z "$(SERVICE)" ]; then echo "Error: SERVICE parameter is required."; exit 1; fi
	@if [ -z "$(TIME)" ]; then echo "Error: TIME parameter is required (e.g., 0800)."; exit 1; fi
	@HOUR=$$(echo $(TIME) | cut -c1-2); \
	MINUTE=$$(echo $(TIME) | cut -c3-4); \
	RULE_NAME="$(SERVICE)-daily-schedule"; \
	echo "Scheduling $(SERVICE) to run daily at $$HOUR:$$MINUTE UTC..."; \
	aws events put-rule \
		--name "$$RULE_NAME" \
		--schedule-expression "cron($$MINUTE $$HOUR * * ? *)" \
		--state ENABLED \
		--description "Daily schedule for $(SERVICE) at $$HOUR:$$MINUTE UTC"; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	REGION=$$(aws configure get region); \
	REGION=$${REGION:-us-east-1}; \
	LAMBDA_ARN="arn:aws:lambda:$$REGION:$$ACCOUNT_ID:function:$(SERVICE)"; \
	aws lambda add-permission \
		--function-name "$(SERVICE)" \
		--statement-id "eventbridge-$$RULE_NAME" \
		--action "lambda:InvokeFunction" \
		--principal events.amazonaws.com \
		--source-arn "arn:aws:events:$$REGION:$$ACCOUNT_ID:rule/$$RULE_NAME" > /dev/null 2>&1 || true; \
	aws events put-targets \
		--rule "$$RULE_NAME" \
		--targets "ID=1,Arn=$$LAMBDA_ARN"; \
	echo "Successfully scheduled $(SERVICE)."

# Schedule a Lambda function at an EventBridge rate expression
# Usage: make schedule-rate-lambda SERVICE=health FUNCTION_NAME=epac-health-staging RATE="rate(5 minutes)"
schedule-rate-lambda:
	@if [ -z "$(SERVICE)" ]; then echo "Error: SERVICE parameter is required."; exit 1; fi
	@if [ -z "$(RATE)" ]; then echo "Error: RATE parameter is required (e.g., rate(2 minutes))."; exit 1; fi
	@FUNCTION_NAME_VAL="$(FUNCTION_NAME)"; \
	if [ -z "$$FUNCTION_NAME_VAL" ]; then FUNCTION_NAME_VAL="$(SERVICE)"; fi; \
	RULE_NAME="$$FUNCTION_NAME_VAL-rate-schedule"; \
	echo "Scheduling $(SERVICE) with $(RATE)..."; \
	aws events put-rule \
		--name "$$RULE_NAME" \
		--schedule-expression "$(RATE)" \
		--state ENABLED \
		--description "Rate schedule for $(SERVICE): $(RATE)"; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	REGION=$$(aws configure get region); \
	REGION=$${REGION:-us-east-1}; \
	LAMBDA_ARN="arn:aws:lambda:$$REGION:$$ACCOUNT_ID:function:$$FUNCTION_NAME_VAL"; \
	aws lambda add-permission \
		--function-name "$$FUNCTION_NAME_VAL" \
		--statement-id "eventbridge-$$RULE_NAME" \
		--action "lambda:InvokeFunction" \
		--principal events.amazonaws.com \
		--source-arn "arn:aws:events:$$REGION:$$ACCOUNT_ID:rule/$$RULE_NAME" > /dev/null 2>&1 || true; \
	aws events put-targets \
		--rule "$$RULE_NAME" \
		--targets "ID=1,Arn=$$LAMBDA_ARN"; \
	echo "Successfully scheduled $(SERVICE)."

# Run integration tests across all backend services
# Usage: make test-integration
test-integration:
	@echo "Starting Postgres for integration tests..."
	cd .. && docker compose -f docker-compose.test.yml up -d
	@echo "Waiting for Postgres to be ready..."
	@sleep 3
	@echo "Running integration tests..."
	@awk '/\.\// {print $$1}' go.work | while read -r d; do \
		echo "Testing $$d..."; \
		(cd "$$d" && DATABASE_URL="postgresql://epac:epac@localhost:5432/epac_test?sslmode=disable" go test -tags=integration ./...) || exit 1; \
	done
