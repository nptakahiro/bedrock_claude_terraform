# ── CloudWatch & Bedrock Logging ──────────────────────────────
# 実装ポイント:
#   - Bedrock モデル呼び出しログ = 監査・コスト分析の基盤
#   - CloudWatch Logs Insights でトークン使用量を分析
#   - CloudWatch Alarms でコスト超過を早期検知

# ── Bedrock モデル呼び出しログ ─────────────────────────────────
# ポイント: すべてのモデル呼び出しをS3/CWLogsに記録できる
resource "aws_bedrock_model_invocation_logging_configuration" "main" {
  logging_config {
    embedding_data_delivery_enabled = true
    image_data_delivery_enabled     = true
    text_data_delivery_enabled      = true

    # CloudWatch Logs への書き込み
    cloud_watch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations.name
      role_arn       = aws_iam_role.bedrock_logging.arn

      large_data_delivery_s3_config {
        bucket_name = aws_s3_bucket.bedrock_logs.bucket
        key_prefix  = "large-payloads/"  # 大きなペイロードはS3に
      }
    }

    # S3 への書き込み（分析・長期保存用）
    s3_config {
      bucket_name = aws_s3_bucket.bedrock_logs.bucket
      key_prefix  = "invocations/"
    }
  }
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/aws/bedrock/model-invocations"
  retention_in_days = var.log_retention_days
}

# ── CloudWatch ダッシュボード ──────────────────────────────────
# ポイント: トークン使用量・レイテンシ・エラー率を可視化
resource "aws_cloudwatch_dashboard" "bedrock" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title  = "Lambda 実行回数"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.chat.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.rag.function_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "Lambda エラー率"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.chat.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.rag.function_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "Lambda レイテンシ (ms)"
          period = 300
          stat   = "p95"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.chat.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.rag.function_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "DynamoDB 読み書き容量"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.conversation_history.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.conversation_history.name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "API Gateway リクエスト数"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.main.name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "API Gateway 4xx/5xx エラー"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "4XXError", "ApiName", aws_api_gateway_rest_api.main.name],
            ["AWS/ApiGateway", "5XXError", "ApiName", aws_api_gateway_rest_api.main.name],
          ]
        }
      },
    ]
  })
}

# ── CloudWatch Alarms ─────────────────────────────────────────
# ポイント: コスト上限アラームで予期せぬ高額請求を防ぐ

# Lambda エラー率アラーム
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name_prefix}-lambda-errors"
  alarm_description   = "Lambda 関数のエラーが発生しています"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.chat.function_name
  }
}

# Bedrock スロットリングアラーム
# ポイント: Throttling = レート制限超過 → 指数バックオフで対処
resource "aws_cloudwatch_metric_alarm" "bedrock_throttle" {
  alarm_name          = "${local.name_prefix}-bedrock-throttle"
  alarm_description   = "Bedrock モデル呼び出しがスロットリングされています"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"  # Lambda レベルで検知
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.chat.function_name
  }
}

# ── CloudWatch Logs Insights クエリ例 ─────────────────────────
# ポイント: このクエリでトークン使用量を分析できる
# (実際のクエリはコンソールで実行)
#
# fields @timestamp, @message
# | filter @message like /tokenUsage/
# | parse @message '"inputTokens":*,' as inputTokens
# | parse @message '"outputTokens":*,' as outputTokens
# | stats sum(inputTokens) as totalInput, sum(outputTokens) as totalOutput by bin(1h)
# | sort @timestamp desc
