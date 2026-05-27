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

variable "env" {
  description = "環境名（API Gateway ステージ名に使用）"
  type        = string
}

variable "bedrock_model_id" {
  description = "使用する Bedrock モデル ID"
  type        = string
}

variable "enable_guardrails" {
  description = "Guardrails を有効化しているか"
  type        = bool
}

variable "guardrail_id" {
  description = "Guardrail ID（enable_guardrails=true の場合に bedrock モジュールから渡す）"
  type        = string
  default     = ""
}

variable "enable_knowledge_base" {
  description = "Knowledge Base を有効化しているか"
  type        = bool
}

variable "knowledge_base_id" {
  description = "Knowledge Base ID（enable_knowledge_base=true の場合に bedrock モジュールから渡す）"
  type        = string
  default     = ""
}

variable "enable_agent" {
  description = "Bedrock Agent を有効化しているか"
  type        = bool
}

variable "agent_id" {
  description = "Bedrock Agent ID（enable_agent=true の場合に bedrock モジュールから渡す）"
  type        = string
  default     = ""
}

variable "agent_arn" {
  description = "Bedrock Agent ARN（enable_agent=true の場合に bedrock モジュールから渡す）"
  type        = string
  default     = ""
}

variable "conversation_table_name" {
  description = "会話履歴 DynamoDB テーブル名"
  type        = string
}

variable "conversation_table_arn" {
  description = "会話履歴 DynamoDB テーブル ARN"
  type        = string
}

variable "documents_bucket_arn" {
  description = "ドキュメント S3 バケット ARN"
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda タイムアウト秒数"
  type        = number
}

variable "lambda_memory" {
  description = "Lambda メモリサイズ (MB)"
  type        = number
}

variable "log_retention_days" {
  description = "CloudWatch Logs 保持日数"
  type        = number
}
