# epac Aurora PostgreSQL

`provision-epac-db.sh` provisions the production Aurora Serverless v2 database required by EPAC-1831:

- Aurora PostgreSQL cluster `epac-db` in `us-east-1`
- Serverless v2 capacity range `0.5` to `4` ACU
- public writer instance `epac-db-writer`
- database `epac` with master user `epac`
- public PostgreSQL security group on TCP `5432`
- Secrets Manager secret `epac/database-url`
- Lambda execution role access to read that secret

Run from the repository root with the agent AWS profile:

```bash
CREATE_DEFAULT_VPC=1 ./infra/rds/provision-epac-db.sh
```

`CREATE_DEFAULT_VPC=1` is required only when `us-east-1` does not already have a default VPC with subnets in at least two Availability Zones. The EPAC AWS account had no default VPC before EPAC-1831, so the first run creates AWS's default VPC/subnets and then uses them for the RDS subnet group.

Optional smoke test, when `psql` is installed locally:

```bash
CREATE_DEFAULT_VPC=1 SMOKE_TEST=1 ./infra/rds/provision-epac-db.sh
```

If `psql` is installed through Homebrew's keg-only `libpq`, pass the binary path:

```bash
CREATE_DEFAULT_VPC=1 SMOKE_TEST=1 PSQL_BIN=/opt/homebrew/opt/libpq/bin/psql ./infra/rds/provision-epac-db.sh
```

The script does not print the generated database password or full connection string. Read the connection string from Secrets Manager when needed:

```bash
aws secretsmanager get-secret-value --profile riddim-agent --region us-east-1 --secret-id epac/database-url --query SecretString --output text
```
