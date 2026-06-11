module epac/push-notification-dispatcher

go 1.25.3

require (
	epac/observability v0.0.0
	github.com/aws/aws-lambda-go v1.54.0
	github.com/jackc/pgx/v5 v5.8.0
)

require github.com/stretchr/testify v1.11.1 // indirect

replace epac/observability => ../observability
