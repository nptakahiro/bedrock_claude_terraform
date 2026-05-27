variable "name_prefix" {
  description = "全リソース名に付与するプレフィックス"
  type        = string
}

variable "common_tags" {
  description = "全リソースに付与する共通タグ"
  type        = map(string)
}

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
}

variable "bedrock_logs_bucket_name" {
  description = "Bedrock ログ S3 バケット名"
  type        = string
}

variable "bedrock_logs_bucket_arn" {
  description = "Bedrock ログ S3 バケット ARN（IAM ポリシー用）"
  type        = string
}

variable "chat_lambda_name" {
  description = "Chat Lambda 関数名（CloudWatch メトリクス用）"
  type        = string
}

variable "rag_lambda_name" {
  description = "RAG Lambda 関数名（CloudWatch メトリクス用）"
  type        = string
}

variable "conversation_table_name" {
  description = "会話履歴 DynamoDB テーブル名（CloudWatch メトリクス用）"
  type        = string
}

variable "api_gateway_name" {
  description = "API Gateway 名（CloudWatch メトリクス用）"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs 保持日数"
  type        = number
}
