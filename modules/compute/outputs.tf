output "chat_lambda_arn" {
  description = "Chat Lambda 関数 ARN"
  value       = aws_lambda_function.chat.arn
}

output "chat_lambda_name" {
  description = "Chat Lambda 関数名"
  value       = aws_lambda_function.chat.function_name
}

output "rag_lambda_arn" {
  description = "RAG Lambda 関数 ARN"
  value       = aws_lambda_function.rag.arn
}

output "rag_lambda_name" {
  description = "RAG Lambda 関数名"
  value       = aws_lambda_function.rag.function_name
}

output "api_endpoint" {
  description = "API Gateway ベース URL"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "chat_endpoint" {
  description = "Chat API エンドポイント"
  value       = "${aws_api_gateway_stage.main.invoke_url}/chat"
}

output "rag_endpoint" {
  description = "RAG API エンドポイント"
  value       = "${aws_api_gateway_stage.main.invoke_url}/rag"
}

output "api_gateway_name" {
  description = "API Gateway 名（CloudWatch ダッシュボード用）"
  value       = aws_api_gateway_rest_api.main.name
}
