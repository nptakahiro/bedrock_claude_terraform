# ── API Gateway ───────────────────────────────────────────────
# 実装ポイント:
#   - API Gateway = Lambda の HTTP エンドポイント
#   - REST API vs HTTP API: REST API は細かい制御可能、HTTP API は安価
#   - サーバーレス = リクエストがなければ課金ゼロ

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.name_prefix}-api"
  description = "デモ用 Bedrock デモ API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ── /chat エンドポイント ───────────────────────────────────────
resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "chat"
}

resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "POST"
  authorization = "NONE"  # 本番では AWS_IAM や Cognito を使う
}

resource "aws_api_gateway_integration" "chat" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.chat.id
  http_method             = aws_api_gateway_method.chat_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"  # Lambda Proxy Integration
  uri                     = aws_lambda_function.chat.invoke_arn
}

resource "aws_lambda_permission" "apigw_chat" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ── /rag エンドポイント ────────────────────────────────────────
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

# ── CORS (OPTIONS メソッド) ────────────────────────────────────
# ブラウザからの直接アクセス用（学習・デモ目的）
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

# ── デプロイ ──────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.chat,
    aws_api_gateway_integration.rag,
    aws_api_gateway_integration.chat_options,
  ]

  # 設定変更時に再デプロイするためのトリガー
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

  # アクセスログ
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

  # APIキャッシュ（0.5GB = $0.02/時 = オフ推奨）
  # cache_cluster_enabled = false

  depends_on = [aws_cloudwatch_log_group.api_gateway]
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}
