#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-riddim-agent}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EXPECTED_ACCOUNT_ID="${EXPECTED_ACCOUNT_ID:-227530433709}"

CLUSTER_ID="${CLUSTER_ID:-epac-db}"
INSTANCE_ID="${INSTANCE_ID:-epac-db-writer}"
DB_NAME="${DB_NAME:-epac}"
MASTER_USERNAME="${MASTER_USERNAME:-epac}"
ENGINE_VERSION="${ENGINE_VERSION:-15.17}"
MIN_ACU="${MIN_ACU:-0.5}"
MAX_ACU="${MAX_ACU:-4}"

SUBNET_GROUP_NAME="${SUBNET_GROUP_NAME:-epac-db-subnet-group}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-epac-db-postgres-public}"
SECURITY_GROUP_DESCRIPTION="${SECURITY_GROUP_DESCRIPTION:-Public PostgreSQL access for epac Aurora}"
SECRET_ID="${SECRET_ID:-epac/database-url}"
IAM_POLICY_NAME="${IAM_POLICY_NAME:-EpacDatabaseUrlSecretRead}"
LAMBDA_FUNCTIONS_CSV="${LAMBDA_FUNCTIONS_CSV:-search,member-speeches,daily-fetch}"

CREATE_DEFAULT_VPC="${CREATE_DEFAULT_VPC:-0}"
SMOKE_TEST="${SMOKE_TEST:-0}"
PSQL_BIN="${PSQL_BIN:-psql}"

aws_cmd() {
  aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
}

log() {
  printf '%s\n' "$*" >&2
}

require_account() {
  local account_id
  account_id="$(aws_cmd sts get-caller-identity --query Account --output text)"
  if [[ "$account_id" != "$EXPECTED_ACCOUNT_ID" ]]; then
    log "Expected AWS account $EXPECTED_ACCOUNT_ID, got $account_id."
    exit 1
  fi
}

default_vpc_id() {
  aws_cmd ec2 describe-vpcs \
    --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' \
    --output text | sed 's/^None$//'
}

ensure_default_vpc() {
  local vpc_id
  vpc_id="$(default_vpc_id)"
  if [[ -n "$vpc_id" ]]; then
    printf '%s\n' "$vpc_id"
    return
  fi

  if [[ "$CREATE_DEFAULT_VPC" != "1" ]]; then
    log "No default VPC exists in $AWS_REGION."
    log "RDS requires subnets in at least two AZs. Re-run with CREATE_DEFAULT_VPC=1 to create AWS's default VPC/subnets."
    exit 1
  fi

  log "Creating AWS default VPC in $AWS_REGION because none exists."
  aws_cmd ec2 create-default-vpc --query 'Vpc.VpcId' --output text
}

subnets_for_vpc() {
  local vpc_id="$1"
  aws_cmd ec2 describe-subnets \
    --filters Name=vpc-id,Values="$vpc_id" \
    --query 'sort_by(Subnets,&AvailabilityZone)[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone}' \
    --output text
}

select_subnets() {
  local vpc_id="$1"
  local selected=()
  local seen_azs=""
  local subnet_id az

  while read -r az subnet_id; do
    [[ -z "${az:-}" || -z "${subnet_id:-}" ]] && continue
    if [[ "$seen_azs" != *"|$az|"* ]]; then
      selected+=("$subnet_id")
      seen_azs="${seen_azs}|${az}|"
    fi
    [[ "${#selected[@]}" -ge 2 ]] && break
  done < <(subnets_for_vpc "$vpc_id")

  if [[ "${#selected[@]}" -lt 2 ]]; then
    log "VPC $vpc_id does not have subnets in at least two AZs."
    exit 1
  fi

  printf '%s\n' "${selected[@]}"
}

ensure_subnet_group() {
  local subnet_ids=("$@")
  if aws_cmd rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP_NAME" >/dev/null 2>&1; then
    log "DB subnet group $SUBNET_GROUP_NAME already exists."
    return
  fi

  log "Creating DB subnet group $SUBNET_GROUP_NAME."
  aws_cmd rds create-db-subnet-group \
    --db-subnet-group-name "$SUBNET_GROUP_NAME" \
    --db-subnet-group-description "Subnet group for epac Aurora Serverless v2" \
    --subnet-ids "${subnet_ids[@]}" \
    --tags Key=Project,Value=epac Key=Ticket,Value=EPAC-1831 Key=ManagedBy,Value=infra/rds/provision-epac-db.sh >/dev/null
}

ensure_security_group() {
  local vpc_id="$1"
  local security_group_id
  security_group_id="$(aws_cmd ec2 describe-security-groups \
    --filters Name=vpc-id,Values="$vpc_id" Name=group-name,Values="$SECURITY_GROUP_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text | sed 's/^None$//')"

  if [[ -z "$security_group_id" ]]; then
    log "Creating security group $SECURITY_GROUP_NAME."
    security_group_id="$(aws_cmd ec2 create-security-group \
      --group-name "$SECURITY_GROUP_NAME" \
      --description "$SECURITY_GROUP_DESCRIPTION" \
      --vpc-id "$vpc_id" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=epac},{Key=Ticket,Value=EPAC-1831},{Key=ManagedBy,Value=infra/rds/provision-epac-db.sh}]" \
      --query GroupId \
      --output text)"
  else
    log "Security group $SECURITY_GROUP_NAME already exists."
  fi

  aws_cmd ec2 authorize-security-group-ingress \
    --group-id "$security_group_id" \
    --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges=[{CidrIp=0.0.0.0/0,Description=Temporary public PostgreSQL access for EPAC-1831}]" >/dev/null 2>&1 || true

  printf '%s\n' "$security_group_id"
}

cluster_exists() {
  aws_cmd rds describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" >/dev/null 2>&1
}

instance_exists() {
  aws_cmd rds describe-db-instances --db-instance-identifier "$INSTANCE_ID" >/dev/null 2>&1
}

random_password() {
  aws_cmd secretsmanager get-random-password \
    --password-length 32 \
    --exclude-punctuation \
    --query RandomPassword \
    --output text
}

ensure_cluster() {
  local security_group_id="$1"
  local password="$2"

  if cluster_exists; then
    log "DB cluster $CLUSTER_ID already exists."
    return
  fi

  log "Creating Aurora PostgreSQL Serverless v2 cluster $CLUSTER_ID."
  aws_cmd rds create-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --engine aurora-postgresql \
    --engine-version "$ENGINE_VERSION" \
    --engine-mode provisioned \
    --serverless-v2-scaling-configuration "MinCapacity=$MIN_ACU,MaxCapacity=$MAX_ACU" \
    --master-username "$MASTER_USERNAME" \
    --master-user-password "$password" \
    --database-name "$DB_NAME" \
    --db-subnet-group-name "$SUBNET_GROUP_NAME" \
    --vpc-security-group-ids "$security_group_id" \
    --backup-retention-period 7 \
    --copy-tags-to-snapshot \
    --deletion-protection \
    --tags Key=Project,Value=epac Key=Ticket,Value=EPAC-1831 Key=ManagedBy,Value=infra/rds/provision-epac-db.sh >/dev/null
}

ensure_instance() {
  if instance_exists; then
    log "DB writer instance $INSTANCE_ID already exists."
    return
  fi

  log "Creating public writer instance $INSTANCE_ID."
  aws_cmd rds create-db-instance \
    --db-instance-identifier "$INSTANCE_ID" \
    --db-cluster-identifier "$CLUSTER_ID" \
    --engine aurora-postgresql \
    --db-instance-class db.serverless \
    --publicly-accessible \
    --tags Key=Project,Value=epac Key=Ticket,Value=EPAC-1831 Key=ManagedBy,Value=infra/rds/provision-epac-db.sh >/dev/null
}

cluster_endpoint() {
  aws_cmd rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'DBClusters[0].Endpoint' \
    --output text
}

secret_arn() {
  aws_cmd secretsmanager describe-secret \
    --secret-id "$SECRET_ID" \
    --query ARN \
    --output text
}

secret_exists() {
  aws_cmd secretsmanager describe-secret --secret-id "$SECRET_ID" >/dev/null 2>&1
}

database_url_secret() {
  aws_cmd secretsmanager get-secret-value \
    --secret-id "$SECRET_ID" \
    --query SecretString \
    --output text
}

put_database_url_secret() {
  local database_url="$1"
  local tmpfile
  tmpfile="$(mktemp)"
  chmod 600 "$tmpfile"
  printf '%s' "$database_url" > "$tmpfile"

  if secret_exists; then
    log "Updating Secrets Manager secret $SECRET_ID."
    aws_cmd secretsmanager update-secret --secret-id "$SECRET_ID" --secret-string "file://$tmpfile" >/dev/null
  else
    log "Creating Secrets Manager secret $SECRET_ID."
    aws_cmd secretsmanager create-secret \
      --name "$SECRET_ID" \
      --description "PostgreSQL connection string for epac Aurora cluster" \
      --secret-string "file://$tmpfile" \
      --tags Key=Project,Value=epac Key=Ticket,Value=EPAC-1831 Key=ManagedBy,Value=infra/rds/provision-epac-db.sh >/dev/null
  fi

  rm -f "$tmpfile"
}

lambda_role_names() {
  local functions=()
  local function_name role_arn
  IFS=, read -r -a functions <<< "$LAMBDA_FUNCTIONS_CSV"
  for function_name in "${functions[@]}"; do
    role_arn="$(aws_cmd lambda get-function-configuration \
      --function-name "$function_name" \
      --query Role \
      --output text)"
    basename "$role_arn"
  done | sort -u
}

grant_lambda_secret_access() {
  local arn="$1"
  local role_name
  local policy_file
  policy_file="$(mktemp)"
  chmod 600 "$policy_file"
  printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"secretsmanager:GetSecretValue","Resource":"%s"}]}\n' "$arn" > "$policy_file"

  while read -r role_name; do
    [[ -z "$role_name" ]] && continue
    log "Granting $role_name access to $SECRET_ID."
    aws_cmd iam put-role-policy \
      --role-name "$role_name" \
      --policy-name "$IAM_POLICY_NAME" \
      --policy-document "file://$policy_file" >/dev/null
  done < <(lambda_role_names)

  rm -f "$policy_file"
}

run_smoke_test() {
  local database_url="$1"

  if [[ "$SMOKE_TEST" != "1" ]]; then
    return
  fi

  if ! command -v "$PSQL_BIN" >/dev/null 2>&1; then
    log "SMOKE_TEST=1 requested, but $PSQL_BIN is not installed or not on PATH."
    exit 1
  fi

  log "Running psql smoke test against $CLUSTER_ID."
  "$PSQL_BIN" \
    "${database_url}?sslmode=require" \
    --no-password \
    --tuples-only \
    --command 'select current_database();' >/dev/null
}

main() {
  require_account

  local vpc_id
  vpc_id="$(ensure_default_vpc)"

  local subnet_ids=()
  while read -r subnet_id; do
    subnet_ids+=("$subnet_id")
  done < <(select_subnets "$vpc_id")

  ensure_subnet_group "${subnet_ids[@]}"

  local security_group_id
  security_group_id="$(ensure_security_group "$vpc_id")"

  local password=""
  if ! cluster_exists; then
    password="$(random_password)"
  fi

  ensure_cluster "$security_group_id" "$password"
  ensure_instance

  log "Waiting for writer instance $INSTANCE_ID to become available."
  aws_cmd rds wait db-instance-available --db-instance-identifier "$INSTANCE_ID"

  local endpoint database_url arn
  endpoint="$(cluster_endpoint)"

  if [[ -n "$password" ]]; then
    database_url="postgresql://$MASTER_USERNAME:$password@$endpoint:5432/$DB_NAME"
    put_database_url_secret "$database_url"
  elif secret_exists; then
    log "Cluster already existed; preserving current master password and secret value."
    database_url="$(database_url_secret)"
  else
    log "Cluster already exists, but $SECRET_ID is missing. Cannot reconstruct the master password."
    exit 1
  fi

  arn="$(secret_arn)"
  grant_lambda_secret_access "$arn"
  run_smoke_test "$database_url"

  log "Provisioning complete."
  log "Cluster: $CLUSTER_ID"
  log "Instance: $INSTANCE_ID"
  log "Secret: $SECRET_ID"
  log "Endpoint: $(cluster_endpoint)"
}

main "$@"
