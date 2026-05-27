variable "name_prefix" {
  description = "全リソース名に付与するプレフィックス（例: bedrock-demo-dev）"
  type        = string
}

variable "common_tags" {
  description = "全リソースに付与する共通タグ"
  type        = map(string)
}

variable "enable_agent" {
  description = "Bedrock Agent を有効化するか（true の場合 agent_sessions テーブルを作成）"
  type        = bool
}
