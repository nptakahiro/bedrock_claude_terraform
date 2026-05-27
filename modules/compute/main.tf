# ════════════════════════════════════════════════════════════════
# compute モジュール
#   IAM（Lambda 実行ロール）+ Lambda + API Gateway
#   + Bedrock Agent Action Group（Agent との接続）
#
# 依存: storage / bedrock モジュールの出力
# ════════════════════════════════════════════════════════════════

# ── IAM: Lambda 実行ロール ────────────────────────────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "${var.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${var.name_prefix}-lambda-bedrock"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        Sid    = "BedrockKnowledgeBase"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
        ]
        Resource = "*"
      },
      {
        Sid      = "BedrockAgent"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeAgent"]
        Resource = "*"
      },
      {
        Sid      = "BedrockGuardrails"
        Effect   = "Allow"
        Action   = ["bedrock:ApplyGuardrail"]
        Resource = "*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = [
          var.conversation_table_arn,
          "${var.conversation_table_arn}/index/*",
        ]
      },
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.documents_bucket_arn,
          "${var.documents_bucket_arn}/*",
        ]
      },
    ]
  })
}

# ── Lambda: ZIP パッケージ ────────────────────────────────────────
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

# ── Lambda: Chat 関数（InvokeModel + 会話履歴）────────────────────
resource "aws_lambda_function" "chat" {
  function_name    = "${var.name_prefix}-chat"
  filename         = data.archive_file.chat.output_path
  source_code_hash = data.archive_file.chat.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      CONVERSATION_TABLE = var.conversation_table_name
      MODEL_ID           = var.bedrock_model_id
      GUARDRAIL_ID       = var.guardrail_id
      GUARDRAIL_VERSION  = "DRAFT"
    }
  }
}

resource "aws_cloudwatch_log_group" "chat" {
  name              = "/aws/lambda/${aws_lambda_function.chat.function_name}"
  retention_in_days = var.log_retention_days
}

# ── Lambda: RAG 関数（Knowledge Base 経由）───────────────────────
resource "aws_lambda_function" "rag" {
  function_name    = "${var.name_prefix}-rag"
  filename         = data.archive_file.rag.output_path
  source_code_hash = data.archive_file.rag.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = var.knowledge_base_id
      MODEL_ARN         = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"
    }
  }
}

resource "aws_cloudwatch_log_group" "rag" {
  name              = "/aws/lambda/${aws_lambda_function.rag.function_name}"
  retention_in_days = var.log_retention_days
}

# ── Bedrock Agent: Action Group + Lambda 権限付与 ─────────────────
# Action Group は compute に置くことで bedrock ↔ compute の循環依存を回避
resource "aws_bedrockagent_agent_action_group" "chat" {
  count = var.enable_agent ? 1 : 0

  agent_id          = var.agent_id
  agent_version     = "DRAFT"
  action_group_name = "chat-tool"
  description       = "会話・質問応答ツール"

  action_group_executor {
    lambda = aws_lambda_function.chat.arn
  }

  api_schema {
    payload = jsonencode({
      openapi = "3.0.0"
      info    = { title = "Chat Tool", version = "1.0.0" }
      paths = {
        "/chat" = {
          post = {
            summary     = "チャットメッセージを送信して応答を得る"
            operationId = "sendChatMessage"
            requestBody = {
              required = true
              content  = {
                "application/json" = {
                  schema = {
                    type       = "object"
                    required   = ["message"]
                    properties = {
                      message    = { type = "string", description = "ユーザーからのメッセージ" }
                      session_id = { type = "string", description = "会話セッション ID（省略時は自動生成）" }
                    }
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "成功"
                content     = {
                  "application/json" = {
                    schema = {
                      type       = "object"
                      properties = {
                        response   = { type = "string", description = "AI の応答テキスト" }
                        session_id = { type = "string", description = "セッション ID" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })
  }
}

resource "aws_lambda_permission" "bedrock_agent" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = var.agent_arn
}

# ── API Gateway ───────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.name_prefix}-api"
  description = "Bedrock デモ API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "chat"
}

resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "chat" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.chat.id
  http_method             = aws_api_gateway_method.chat_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat.invoke_arn
}

resource "aws_lambda_permission" "apigw_chat" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_api_gateway_resource" "rag" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "rag"
}

resource "aws_api_gateway_method" "rag_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.rag.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "rag" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.rag.id
  http_method             = aws_api_gateway_method.rag_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.rag.invoke_arn
}

resource "aws_lambda_permission" "apigw_rag" {
  statement_id  = "AllowAPIGatewayRAG"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rag.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# CORS (OPTIONS メソッド)
resource "aws_api_gateway_method" "chat_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "chat_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "chat_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "chat_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.chat,
    aws_api_gateway_integration.rag,
    aws_api_gateway_integration.chat_options,
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.chat,
      aws_api_gateway_resource.rag,
      aws_api_gateway_method.chat_post,
      aws_api_gateway_method.rag_post,
      aws_api_gateway_integration.chat,
      aws_api_gateway_integration.rag,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.env

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId    = "$context.requestId"
      ip           = "$context.identity.sourceIp"
      method       = "$context.httpMethod"
      path         = "$context.path"
      status       = "$context.status"
      responseTime = "$context.responseLatency"
    })
  }

  depends_on = [aws_cloudwatch_log_group.api_gateway]
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.name_prefix}"
  retention_in_days = var.log_retention_days
}
