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

variable "bedrock_model_id" {
  description = "使用する Bedrock モデル ID"
  type        = string
}

variable "enable_guardrails" {
  description = "Bedrock Guardrails を有効化するか"
  type        = bool
}

variable "enable_knowledge_base" {
  description = "Bedrock Knowledge Base (RAG) を有効化するか"
  type        = bool
}

variable "enable_agent" {
  description = "Bedrock Agent を有効化するか"
  type        = bool
}

variable "documents_bucket_arn" {
  description = "Knowledge Base のデータソースとなる S3 バケット ARN"
  type        = string
}

variable "documents_bucket_id" {
  description = "Knowledge Base のデータソースとなる S3 バケット ID"
  type        = string
}

variable "account_id" {
  description = "AWS アカウント ID"
  type        = string
}

variable "caller_arn" {
  description = "デプロイ実行ユーザーの ARN（OpenSearch アクセスポリシー用）"
  type        = string
}
