# ── S3 バケット ────────────────────────────────────────────────
# 実装ポイント:
#   - Knowledge Base のデータソースは S3 が基本（Web/Confluence/SharePoint も可）
#   - バケット名はグローバル一意 → アカウントIDをサフィックスに付与
#   - セキュリティ3点セット: SSE（暗号化）・バージョニング・パブリックアクセスブロック
#   - ライフサイクルポリシーでコスト最適化（Standard → IA → 削除）

# ── ドキュメント格納バケット ────────────────────────────────────
# Knowledge Base のデータソース（ingestion 対象のドキュメントを格納）
resource "aws_s3_bucket" "documents" {
  # バケット名の末尾にアカウントIDを付与してグローバル一意性を確保
  bucket = "${local.name_prefix}-documents-${data.aws_caller_identity.current.account_id}"

  # force_destroy = true: バケット内にオブジェクトがあっても terraform destroy で削除可能
  # ⚠️ 本番環境では必ず false に変更すること（誤削除防止）
  force_destroy = true
}

# バージョニング: オブジェクトの変更履歴を保持
# ポイント: Knowledge Base の再 Ingestion 時に以前のバージョンと比較可能
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
    # Disabled  → バージョニング無効（デフォルト）
    # Enabled   → バージョニング有効（各上書きで新バージョン作成）
    # Suspended → 既存バージョンは保持、新規バージョンは作成しない
  }
}

# サーバー側暗号化 (SSE)
# ポイント: データ保護の基本。SSE-S3(AES256) か SSE-KMS を選択
#   SSE-S3 (AES256): AWS管理キー、追加コストなし → 学習環境に適切
#   SSE-KMS        : CMK使用可能、監査ログあり  → 本番環境に適切
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # SSE-S3（AWS管理キー）
      # KMS を使う場合:
      # sse_algorithm     = "aws:kms"
      # kms_master_key_id = aws_kms_key.s3.arn
    }
    # bucket_key_enabled = true  # KMS使用時のコスト削減オプション
  }
}

# パブリックアクセスブロック
# ポイント: S3 データの意図しない公開を防ぐ4重ガード
#   block_public_acls       → 新規 ACL によるパブリック付与を拒否
#   block_public_policy     → バケットポリシーによるパブリック付与を拒否
#   ignore_public_acls      → 既存の ACL のパブリック設定を無効化
#   restrict_public_buckets → パブリックポリシーのアクセスを制限
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Bedrock モデル呼び出しログバケット ─────────────────────────
# CloudWatch Logs に加え、S3 にも保存することで長期分析・コスト追跡が可能
resource "aws_s3_bucket" "bedrock_logs" {
  bucket        = "${local.name_prefix}-bedrock-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bedrock_logs" {
  bucket                  = aws_s3_bucket.bedrock_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ライフサイクルポリシー: 自動でストレージクラスを降格 → コスト最適化
# ポイント: S3 ストレージクラスの使い分け
#   STANDARD     : 頻繁アクセス    $0.023/GB/月
#   STANDARD_IA  : 低頻度アクセス  $0.0125/GB/月（取り出し料金あり）
#   GLACIER      : アーカイブ      $0.004/GB/月（取り出しに時間）
#   DEEP_ARCHIVE : 長期保管        $0.00099/GB/月（最安、12時間以上）
resource "aws_s3_bucket_lifecycle_configuration" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    # 30日後: STANDARD → STANDARD_IA（低頻度アクセスに移行）
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # 90日後: 削除（長期保管が必要な場合は GLACIER に変更）
    expiration {
      days = 90
    }
  }
}

# ── サンプルドキュメント ────────────────────────────────────────
# Knowledge Base の Ingestion 動作確認用テキスト
# enable_knowledge_base=true 後、AWS コンソールから「Sync」を実行すると
# このファイルがチャンキング → 埋め込み → OpenSearch に保存される
resource "aws_s3_object" "sample_doc" {
  bucket  = aws_s3_bucket.documents.id
  key     = "sample/bedrock_overview.txt"   # Knowledge Base の inclusion_prefix: "sample/" と一致
  content = <<-EOT
    Amazon Bedrock Overview

    Amazon Bedrock is a fully managed service that makes foundation models (FMs)
    from leading AI companies available through an API. It provides:

    - Access to models from Anthropic (Claude), AI21, Cohere, Meta, Stability AI, and Amazon
    - Serverless inference with pay-per-token pricing
    - Knowledge Bases for RAG (Retrieval-Augmented Generation)
    - Agents for multi-step task execution
    - Guardrails for responsible AI
    - Model Evaluation for benchmarking

    Claude models available on Bedrock:
    - Claude 3 Haiku     : Fastest, most cost-effective ($0.0008/1K input)
    - Claude 3.5 Sonnet  : Best balance of performance and cost
    - Claude 3 Opus      : Most capable for complex tasks

    Key Bedrock APIs:
    - InvokeModel                : 同期テキスト生成
    - InvokeModelWithResponseStream : ストリーミング生成（SSE）
    - RetrieveAndGenerate        : RAG（検索＋生成）
    - Retrieve                   : ベクトル検索のみ
    - InvokeAgent                : エージェント実行
    - ApplyGuardrail             : ガードレール適用
  EOT

  content_type = "text/plain"
}

# AWS アカウント情報の取得（バケット名の一意化に使用）
data "aws_caller_identity" "current" {}
