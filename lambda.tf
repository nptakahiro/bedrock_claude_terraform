# ── Lambda ────────────────────────────────────────────────────
# 実装ポイント:
#   - Lambda は Bedrock との統合で最もよく使われるコンピュート
#   - サーバーレス = アイドル時の課金ゼロ

data "archive_file" "chat" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/chat"
  output_path = "${path.module}/.terraform/chat.zip"
}

data "archive_file" "rag" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/rag"
  output_path = "${path.module}/.terraform/rag.zip"
}

# Chat Lambda（モデル直接呼び出し）
resource "aws_lambda_function" "chat" {
  function_name    = "${local.name_prefix}-chat"
  filename         = data.archive_file.chat.output_path
  source_code_hash = data.archive_file.chat.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      CONVERSATION_TABLE = aws_dynamodb_table.conversation_history.name
      MODEL_ID           = var.bedrock_model_id
      GUARDRAIL_ID       = var.enable_guardrails ? aws_bedrock_guardrail.main[0].guardrail_id : ""
      GUARDRAIL_VERSION  = "DRAFT"
    }
  }
}

resource "aws_cloudwatch_log_group" "chat" {
  name              = "/aws/lambda/${aws_lambda_function.chat.function_name}"
  retention_in_days = var.log_retention_days
}

# RAG Lambda（Knowledge Base経由）
resource "aws_lambda_function" "rag" {
  function_name    = "${local.name_prefix}-rag"
  filename         = data.archive_file.rag.output_path
  source_code_hash = data.archive_file.rag.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = var.enable_knowledge_base ? aws_bedrockagent_knowledge_base.main[0].id : ""
      MODEL_ARN         = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"
    }
  }
}

resource "aws_cloudwatch_log_group" "rag" {
  name              = "/aws/lambda/${aws_lambda_function.rag.function_name}"
  retention_in_days = var.log_retention_days
}
