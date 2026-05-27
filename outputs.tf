# ── Outputs ───────────────────────────────────────────────────
# terraform apply 後に表示される重要な情報

output "api_endpoint" {
  description = "API Gateway エンドポイント URL"
  value       = "${aws_api_gateway_stage.main.invoke_url}"
}

output "chat_endpoint" {
  description = "チャット API エンドポイント"
  value       = "${aws_api_gateway_stage.main.invoke_url}/chat"
}

output "rag_endpoint" {
  description = "RAG API エンドポイント (Knowledge Base が有効な場合のみ動作)"
  value       = "${aws_api_gateway_stage.main.invoke_url}/rag"
}

output "chat_lambda_arn" {
  description = "Chat Lambda 関数 ARN"
  value       = aws_lambda_function.chat.arn
}

output "rag_lambda_arn" {
  description = "RAG Lambda 関数 ARN"
  value       = aws_lambda_function.rag.arn
}

output "conversation_table_name" {
  description = "会話履歴 DynamoDB テーブル名"
  value       = aws_dynamodb_table.conversation_history.name
}

output "documents_bucket" {
  description = "Knowledge Base ドキュメント S3 バケット名"
  value       = aws_s3_bucket.documents.bucket
}

output "bedrock_logs_bucket" {
  description = "Bedrock 呼び出しログ S3 バケット名"
  value       = aws_s3_bucket.bedrock_logs.bucket
}

output "guardrail_id" {
  description = "Guardrail ID (enable_guardrails=true の場合)"
  value       = var.enable_guardrails ? aws_bedrock_guardrail.main[0].guardrail_id : "not enabled"
}

output "guardrail_arn" {
  description = "Guardrail ARN (enable_guardrails=true の場合)"
  value       = var.enable_guardrails ? aws_bedrock_guardrail.main[0].guardrail_arn : "not enabled"
}

output "knowledge_base_id" {
  description = "Knowledge Base ID (enable_knowledge_base=true の場合)"
  value       = var.enable_knowledge_base ? aws_bedrockagent_knowledge_base.main[0].id : "not enabled (costs ~$350/month)"
}

output "agent_id" {
  description = "Bedrock Agent ID (enable_agent=true の場合)"
  value       = var.enable_agent ? aws_bedrockagent_agent.main[0].agent_id : "not enabled"
}

output "agent_alias_id" {
  description = "Bedrock Agent Alias ID (enable_agent=true の場合)"
  value       = var.enable_agent ? aws_bedrockagent_agent_alias.main[0].agent_alias_id : "not enabled"
}

output "dashboard_url" {
  description = "CloudWatch ダッシュボード URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${local.name_prefix}-dashboard"
}

output "curl_chat_example" {
  description = "Chat API のテスト用 curl コマンド"
  value       = <<-EOT
    curl -X POST ${aws_api_gateway_stage.main.invoke_url}/chat \
      -H "Content-Type: application/json" \
      -d '{"message": "AWSのBedrockとは何ですか？", "session_id": "test-001"}'
  EOT
}

output "curl_rag_example" {
  description = "RAG API のテスト用 curl コマンド (Knowledge Base が必要)"
  value       = <<-EOT
    curl -X POST ${aws_api_gateway_stage.main.invoke_url}/rag \
      -H "Content-Type: application/json" \
      -d '{"query": "Bedrockのガードレールとは？"}'
  EOT
}
