output "guardrail_id" {
  description = "Guardrail ID（enable_guardrails=true の場合）"
  value       = var.enable_guardrails ? aws_bedrock_guardrail.main[0].guardrail_id : ""
}

output "guardrail_arn" {
  description = "Guardrail ARN（enable_guardrails=true の場合）"
  value       = var.enable_guardrails ? aws_bedrock_guardrail.main[0].guardrail_arn : ""
}

output "knowledge_base_id" {
  description = "Knowledge Base ID（enable_knowledge_base=true の場合）"
  value       = var.enable_knowledge_base ? aws_bedrockagent_knowledge_base.main[0].id : ""
}

output "agent_id" {
  description = "Bedrock Agent ID（enable_agent=true の場合）"
  value       = var.enable_agent ? aws_bedrockagent_agent.main[0].agent_id : ""
}

output "agent_arn" {
  description = "Bedrock Agent ARN（enable_agent=true の場合）"
  value       = var.enable_agent ? aws_bedrockagent_agent.main[0].agent_arn : ""
}

output "agent_alias_id" {
  description = "Bedrock Agent Alias ID（enable_agent=true の場合）"
  value       = var.enable_agent ? aws_bedrockagent_agent_alias.main[0].agent_alias_id : ""
}
