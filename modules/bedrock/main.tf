# ════════════════════════════════════════════════════════════════
# bedrock モジュール
#   IAM（KB・Agent 用）+ Guardrails + Knowledge Base + Agent
#
# 依存: storage モジュールの出力（documents_bucket_arn 等）
# ════════════════════════════════════════════════════════════════

# ── IAM: Knowledge Base ロール ────────────────────────────────────
resource "aws_iam_role" "knowledge_base" {
  count = var.enable_knowledge_base ? 1 : 0

  name = "${var.name_prefix}-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "knowledge_base" {
  count = var.enable_knowledge_base ? 1 : 0

  name = "${var.name_prefix}-kb-policy"
  role = aws_iam_role.knowledge_base[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:ListFoundationModels"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.documents_bucket_arn,
          "${var.documents_bucket_arn}/*",
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

# ── IAM: Bedrock Agent ロール ────────────────────────────────────
# ポイント: Agent が Lambda を呼び出すために必要
# Lambda ARN は命名規則から構築（循環依存を回避）
resource "aws_iam_role" "bedrock_agent" {
  count = var.enable_agent ? 1 : 0

  name = "${var.name_prefix}-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent" {
  count = var.enable_agent ? 1 : 0

  name = "${var.name_prefix}-agent-policy"
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
        # 命名規則から ARN を構築（compute モジュールとの循環依存を回避）
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.name_prefix}-chat"
      },
    ]
  })
}

# ── Bedrock Guardrails ────────────────────────────────────────────
resource "aws_bedrock_guardrail" "main" {
  count = var.enable_guardrails ? 1 : 0

  name                      = "${var.name_prefix}-guardrail"
  blocked_input_messaging   = "申し訳ありませんが、このリクエストはポリシーに違反するため処理できません。"
  blocked_outputs_messaging = "申し訳ありませんが、この回答は安全ポリシーにより表示できません。"
  description               = "デモ用 Guardrail"

  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "NAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "ADDRESS"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_ACCESS_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "BLOCK"
    }
  }

  topic_policy_config {
    topics_config {
      name       = "investment-advice"
      type       = "DENY"
      definition = "具体的な株式・投資商品の購入・売却を推奨する投資アドバイス"
      examples = [
        "この株は買いですか？",
        "今すぐビットコインを買うべきですか？",
      ]
    }
    topics_config {
      name       = "medical-diagnosis"
      type       = "DENY"
      definition = "医師による診断を代替するような疾病診断や治療法の指示"
      examples = [
        "私の症状は何の病気ですか？",
        "この薬を飲めば治りますか？",
      ]
    }
  }

  word_policy_config {
    words_config {
      text = "競合他社名A"
    }
    words_config {
      text = "機密プロジェクト名"
    }
    managed_word_lists_config {
      type = "PROFANITY"
    }
  }
}

# Guardrails バージョン管理: DRAFT → 番号付きバージョンに昇格
resource "aws_bedrock_guardrail_version" "main" {
  count = var.enable_guardrails ? 1 : 0

  guardrail_arn = aws_bedrock_guardrail.main[0].guardrail_arn
  description   = "Initial version for demo"
}

# ── OpenSearch Serverless (Knowledge Base バックエンド) ────────────
resource "aws_opensearchserverless_security_policy" "encryption" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "${var.name_prefix}-enc"
  type   = "encryption"
  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${var.name_prefix}-kb"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "${var.name_prefix}-net"
  type   = "network"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.name_prefix}-kb"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${var.name_prefix}-kb"]
      }
    ]
    AllowFromPublic = false
  }])
}

resource "aws_opensearchserverless_access_policy" "main" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "${var.name_prefix}-access"
  type   = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "index"
        Resource     = ["index/${var.name_prefix}-kb/*"]
        Permission   = [
          "aoss:CreateIndex",
          "aoss:DeleteIndex",
          "aoss:UpdateIndex",
          "aoss:DescribeIndex",
          "aoss:ReadDocument",
          "aoss:WriteDocument",
        ]
      },
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.name_prefix}-kb"]
        Permission   = ["aoss:CreateCollectionItems"]
      }
    ]
    Principal = [
      aws_iam_role.knowledge_base[0].arn,
      var.caller_arn,
    ]
  }])
}

resource "aws_opensearchserverless_collection" "main" {
  count = var.enable_knowledge_base ? 1 : 0

  name = "${var.name_prefix}-kb"
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.main,
  ]
}

# ── Knowledge Base 本体 ────────────────────────────────────────────
resource "aws_bedrockagent_knowledge_base" "main" {
  count = var.enable_knowledge_base ? 1 : 0

  name        = "${var.name_prefix}-kb"
  role_arn    = aws_iam_role.knowledge_base[0].arn
  description = "デモ用 RAG Knowledge Base"

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.main[0].arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
}

# ── Knowledge Base データソース (S3) ─────────────────────────────
resource "aws_bedrockagent_data_source" "s3" {
  count = var.enable_knowledge_base ? 1 : 0

  knowledge_base_id = aws_bedrockagent_knowledge_base.main[0].id
  name              = "${var.name_prefix}-s3-datasource"
  description       = "S3 からドキュメントを Ingestion"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = var.documents_bucket_arn
      # inclusion_prefixes を省略 → バケット全体を対象
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}

# ── Bedrock Agent ─────────────────────────────────────────────────
resource "aws_bedrockagent_agent" "main" {
  count = var.enable_agent ? 1 : 0

  agent_name              = "${var.name_prefix}-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent[0].arn
  foundation_model        = var.bedrock_model_id
  description             = "デモ用エージェント（マルチステップタスク実行）"

  instruction = <<-EOT
    あなたはAWSクラウドアーキテクチャの専門家AIアシスタントです。
    ユーザーの質問に対して以下のツールを使って回答してください:

    1. chat_tool: 一般的な会話・質問応答に使用
    2. ドキュメント検索が必要な場合はKnowledge Baseを参照

    回答は日本語で、簡潔かつ技術的に正確に行ってください。
    不明な点は「わかりません」と答え、推測で回答しないでください。
  EOT

  idle_session_ttl_in_seconds = 600

  memory_configuration {
    enabled_memory_types = ["SUMMARIZATION"]
    storage_days         = 30
  }
}

# Agent Alias: DRAFT → バージョン → Alias でデプロイ管理
resource "aws_bedrockagent_agent_alias" "main" {
  count = var.enable_agent ? 1 : 0

  agent_id         = aws_bedrockagent_agent.main[0].agent_id
  agent_alias_name = "dev"
  description      = "開発用エイリアス（DRAFT バージョン）"
}
