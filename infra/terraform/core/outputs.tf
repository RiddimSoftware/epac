output "terraform_state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "terraform_locks_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}
