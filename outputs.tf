# ── Outputs ───────────────────────────────────────────────────────
# terraform apply 後に表示される重要な情報

output "api_endpoint" {
  description = "API Gateway エンドポイント URL"
  value       = module.compute.api_endpoint
}

output "chat_endpoint" {
  description = "チャット API エンドポイント"
  value       = module.compute.chat_endpoint
}

output "rag_endpoint" {
  description = "RAG API エンドポイント（Knowledge Base が有効な場合のみ動作）"
  value       = module.compute.rag_endpoint
}

output "chat_lambda_arn" {
  description = "Chat Lambda 関数 ARN"
  value       = module.compute.chat_lambda_arn
}

output "rag_lambda_arn" {
  description = "RAG Lambda 関数 ARN"
  value       = module.compute.rag_lambda_arn
}

output "conversation_table_name" {
  description = "会話履歴 DynamoDB テーブル名"
  value       = module.storage.conversation_table_name
}

output "documents_bucket" {
  description = "Knowledge Base ドキュメント S3 バケット名"
  value       = module.storage.documents_bucket_name
}

output "bedrock_logs_bucket" {
  description = "Bedrock 呼び出しログ S3 バケット名"
  value       = module.storage.bedrock_logs_bucket_name
}

output "guardrail_id" {
  description = "Guardrail ID（enable_guardrails=true の場合）"
  value       = module.bedrock.guardrail_id != "" ? module.bedrock.guardrail_id : "not enabled"
}

output "knowledge_base_id" {
  description = "Knowledge Base ID（enable_knowledge_base=true の場合）"
  value       = module.bedrock.knowledge_base_id != "" ? module.bedrock.knowledge_base_id : "not enabled (costs ~$350/month)"
}

output "agent_id" {
  description = "Bedrock Agent ID（enable_agent=true の場合）"
  value       = module.bedrock.agent_id != "" ? module.bedrock.agent_id : "not enabled"
}

output "agent_alias_id" {
  description = "Bedrock Agent Alias ID（enable_agent=true の場合）"
  value       = module.bedrock.agent_alias_id != "" ? module.bedrock.agent_alias_id : "not enabled"
}

output "dashboard_url" {
  description = "CloudWatch ダッシュボード URL"
  value       = module.observability.dashboard_url
}

output "curl_chat_example" {
  description = "Chat API のテスト用 curl コマンド"
  value       = <<-EOT
    curl -X POST ${module.compute.chat_endpoint} \
      -H "Content-Type: application/json" \
      -d '{"message": "Amazon Bedrockとは何ですか？", "session_id": "test-001"}'
  EOT
}

output "curl_rag_example" {
  description = "RAG API のテスト用 curl コマンド（Knowledge Base が必要）"
  value       = <<-EOT
    curl -X POST ${module.compute.rag_endpoint} \
      -H "Content-Type: application/json" \
      -d '{"query": "Bedrockのガードレールとは？"}'
  EOT
}
