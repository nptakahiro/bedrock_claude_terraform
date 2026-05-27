output "documents_bucket_id" {
  description = "ドキュメントバケット ID"
  value       = aws_s3_bucket.documents.id
}

output "documents_bucket_arn" {
  description = "ドキュメントバケット ARN"
  value       = aws_s3_bucket.documents.arn
}

output "documents_bucket_name" {
  description = "ドキュメントバケット名"
  value       = aws_s3_bucket.documents.bucket
}

output "bedrock_logs_bucket_arn" {
  description = "Bedrock ログバケット ARN"
  value       = aws_s3_bucket.bedrock_logs.arn
}

output "bedrock_logs_bucket_name" {
  description = "Bedrock ログバケット名"
  value       = aws_s3_bucket.bedrock_logs.bucket
}

output "conversation_table_name" {
  description = "会話履歴 DynamoDB テーブル名"
  value       = aws_dynamodb_table.conversation_history.name
}

output "conversation_table_arn" {
  description = "会話履歴 DynamoDB テーブル ARN"
  value       = aws_dynamodb_table.conversation_history.arn
}

output "account_id" {
  description = "AWS アカウント ID"
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "デプロイ実行ユーザーの ARN（OpenSearch アクセスポリシー用）"
  value       = data.aws_caller_identity.current.arn
}
