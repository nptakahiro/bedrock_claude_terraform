# ── Bedrock Knowledge Base ────────────────────────────────────
# 実装ポイント:
#   - Knowledge Base = RAG の管理型実装
#   - ベクトルDB: OpenSearch Serverless（高機能だが ~$350/月）or Aurora/Pinecone等
#   - Data Source: S3, Web Crawler, Confluence, Salesforce, SharePoint
#   - Embedding model: Titan Embeddings V2 (推奨)
#
# ⚠️  コスト警告:
#   enable_knowledge_base = true にすると OpenSearch Serverless が起動し
#   最低 ~$350/月 のコストが発生します（アイドル時も課金）
#   学習目的では false のまま、コードを読んで概念を理解してください

# ── OpenSearch Serverless ──────────────────────────────────────
# ポイント: AOSS = Bedrock Knowledge Baseのデフォルトベクトルストア
resource "aws_opensearchserverless_security_policy" "encryption" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "${local.name_prefix}-enc"
  type   = "encryption"
  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.name_prefix}-kb"]
    }]
    AWSOwnedKey = true  # AWS管理キー（コスト削減）
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "${local.name_prefix}-net"
  type   = "network"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.name_prefix}-kb"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${local.name_prefix}-kb"]
      }
    ]
    AllowFromPublic = false  # VPCエンドポイント経由のみ（本番推奨）
    # 学習環境では true でも可（パブリックアクセス許可）
  }])
}

resource "aws_opensearchserverless_access_policy" "main" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "${local.name_prefix}-access"
  type   = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "index"
        Resource     = ["index/${local.name_prefix}-kb/*"]
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
        Resource     = ["collection/${local.name_prefix}-kb"]
        Permission   = ["aoss:CreateCollectionItems"]
      }
    ]
    Principal = [
      aws_iam_role.knowledge_base[0].arn,
      data.aws_caller_identity.current.arn,  # デプロイユーザーも管理可能に
    ]
  }])
}

resource "aws_opensearchserverless_collection" "main" {
  count = var.enable_knowledge_base ? 1 : 0

  name = "${local.name_prefix}-kb"
  type = "VECTORSEARCH"  # SEARCH / TIMESERIES / VECTORSEARCH

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.main,
  ]
}

# ── Knowledge Base 本体 ────────────────────────────────────────
resource "aws_bedrockagent_knowledge_base" "main" {
  count = var.enable_knowledge_base ? 1 : 0

  name     = "${local.name_prefix}-kb"
  role_arn = aws_iam_role.knowledge_base[0].arn
  description = "デモ用 RAG Knowledge Base（Bedrock概要ドキュメント）"

  # 埋め込みモデルの設定
  # ポイント: Titan Embeddings V2 = 1536次元, 多言語対応
  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  # ベクトルDBの設定
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

# ── Data Source (S3) ───────────────────────────────────────────
# ポイント: S3, Web Crawler, Confluence, Salesforce, SharePoint をサポート
resource "aws_bedrockagent_data_source" "s3" {
  count = var.enable_knowledge_base ? 1 : 0

  knowledge_base_id = aws_bedrockagent_knowledge_base.main[0].id
  name              = "${local.name_prefix}-s3-datasource"
  description       = "S3からドキュメントをIngestion"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn              = aws_s3_bucket.documents.arn
      inclusion_prefixes      = ["sample/"]  # sample/フォルダのみ対象
    }
  }

  # チャンキング設定
  # ポイント: チャンクサイズ vs 検索精度のトレードオフ
  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"  # FIXED_SIZE / HIERARCHICAL / SEMANTIC / NONE
      fixed_size_chunking_configuration {
        max_tokens         = 300   # 1チャンク最大300トークン
        overlap_percentage = 20    # 前チャンクとの重複20%（コンテキスト保持）
      }
    }
  }
}
