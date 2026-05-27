# ── IAM ──────────────────────────────────────────────────────
# 実装ポイント:
#   - 最小権限の原則（Principle of Least Privilege）
#   - Bedrock呼び出しには bedrock:InvokeModel が必要
#   - Knowledge Baseには bedrock:Retrieve も必要
#   - Agentには bedrock:InvokeAgent が必要

# ── Lambda 実行ロール ─────────────────────────────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

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
  name = "${local.name_prefix}-lambda-bedrock"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # モデル直接呼び出し
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        # Knowledge Base 検索（enable_knowledge_base=true時のみ利用）
        Sid    = "BedrockKnowledgeBase"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
        ]
        Resource = "*"
      },
      {
        # Agent呼び出し
        Sid    = "BedrockAgent"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
        ]
        Resource = "*"
      },
      {
        # Guardrails適用
        Sid    = "BedrockGuardrails"
        Effect = "Allow"
        Action = [
          "bedrock:ApplyGuardrail",
        ]
        Resource = "*"
      },
      {
        # DynamoDB 読み書き
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
          aws_dynamodb_table.conversation_history.arn,
          "${aws_dynamodb_table.conversation_history.arn}/index/*",
        ]
      },
      {
        # S3 ドキュメント読み取り
        Sid    = "S3Read"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*",
        ]
      },
    ]
  })
}

# ── Bedrock Knowledge Base ロール ─────────────────────────────
resource "aws_iam_role" "knowledge_base" {
  count = var.enable_knowledge_base ? 1 : 0

  name = "${local.name_prefix}-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "knowledge_base" {
  count = var.enable_knowledge_base ? 1 : 0

  name = "${local.name_prefix}-kb-policy"
  role = aws_iam_role.knowledge_base[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:ListFoundationModels",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = "*"
      },
    ]
  })
}

# ── Bedrock Agent ロール ──────────────────────────────────────
resource "aws_iam_role" "bedrock_agent" {
  count = var.enable_agent ? 1 : 0

  name = "${local.name_prefix}-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent" {
  count = var.enable_agent ? 1 : 0

  name = "${local.name_prefix}-agent-policy"
  role = aws_iam_role.bedrock_agent[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.chat.arn
      },
    ]
  })
}

# ── Bedrock モデル呼び出しログ設定 ────────────────────────────
# 実装ポイント: モデル呼び出しのロギングは監査・コスト管理の要
resource "aws_iam_role" "bedrock_logging" {
  name = "${local.name_prefix}-bedrock-logging"

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
  name = "${local.name_prefix}-bedrock-logging"
  role = aws_iam_role.bedrock_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.bedrock_logs.arn}/*"
    }]
  })
}
