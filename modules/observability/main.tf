# ════════════════════════════════════════════════════════════════
# observability モジュール
#   IAM（Bedrock ロギング用）+ CloudWatch（ログ・ダッシュボード・アラーム）
#
# 依存: storage / compute モジュールの出力
# ════════════════════════════════════════════════════════════════

# ── IAM: Bedrock モデル呼び出しログ用ロール ───────────────────────
resource "aws_iam_role" "bedrock_logging" {
  name = "${var.name_prefix}-bedrock-logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_logging" {
  name = "${var.name_prefix}-bedrock-logging"
  role = aws_iam_role.bedrock_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${var.bedrock_logs_bucket_arn}/*"
    }]
  })
}

# ── Bedrock モデル呼び出しログ設定 ────────────────────────────────
resource "aws_bedrock_model_invocation_logging_configuration" "main" {
  logging_config {
    embedding_data_delivery_enabled = true
    image_data_delivery_enabled     = true
    text_data_delivery_enabled      = true

    cloud_watch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations.name
      role_arn       = aws_iam_role.bedrock_logging.arn

      large_data_delivery_s3_config {
        bucket_name = var.bedrock_logs_bucket_name
        key_prefix  = "large-payloads/"
      }
    }

    s3_config {
      bucket_name = var.bedrock_logs_bucket_name
      key_prefix  = "invocations/"
    }
  }
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/aws/bedrock/model-invocations"
  retention_in_days = var.log_retention_days
}

# ── CloudWatch ダッシュボード ─────────────────────────────────────
resource "aws_cloudwatch_dashboard" "bedrock" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title   = "Lambda 実行回数"
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.chat_lambda_name],
            ["AWS/Lambda", "Invocations", "FunctionName", var.rag_lambda_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "Lambda エラー率"
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.chat_lambda_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.rag_lambda_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "Lambda レイテンシ (ms)"
          period  = 300
          stat    = "p95"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.chat_lambda_name],
            ["AWS/Lambda", "Duration", "FunctionName", var.rag_lambda_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "DynamoDB 読み書き容量"
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.conversation_table_name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.conversation_table_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "API Gateway リクエスト数"
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "API Gateway 4xx/5xx エラー"
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/ApiGateway", "4XXError", "ApiName", var.api_gateway_name],
            ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_name],
          ]
        }
      },
    ]
  })
}

# ── CloudWatch アラーム ───────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
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
    FunctionName = var.chat_lambda_name
  }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_throttle" {
  alarm_name          = "${var.name_prefix}-bedrock-throttle"
  alarm_description   = "Bedrock モデル呼び出しがスロットリングされています"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.chat_lambda_name
  }
}
