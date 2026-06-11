module epac/push-notification-dispatcher

go 1.25.3

require (
	epac/observability v0.0.0
	github.com/aws/aws-lambda-go v1.54.0
	github.com/jackc/pgx/v5 v5.10.0
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	golang.org/x/text v0.29.0 // indirect
)

replace epac/observability => ../observability
