# ════════════════════════════════════════════════════════════════
# 変数定義
#
# 使い方:
#   - デフォルト値のまま使う: そのまま terraform apply
#   - 一時変更:              terraform apply -var="enable_knowledge_base=true"
#   - ファイルで管理:        terraform.tfvars を作成して値を記述
#
# terraform.tfvars の例:
#   aws_region            = "ap-northeast-1"
#   bedrock_model_id      = "anthropic.claude-3-5-sonnet-20241022-v2:0"
#   enable_knowledge_base = true
# ════════════════════════════════════════════════════════════════

# ── AWS 基本設定 ──────────────────────────────────────────────
variable "aws_region" {
  description = "AWSリージョン（Bedrockモデルが最も多いus-east-1を推奨）"
  type        = string
  default     = "us-east-1"

  # ポイント: Bedrock のモデル提供状況はリージョンによって異なる
  # us-east-1 が最も多くのモデルを提供（2024年時点）
  # ap-northeast-1 (東京) は利用可能モデルが限定的
  #
  # モデル提供状況確認:
  #   aws bedrock list-foundation-models --region us-east-1 \
  #     --query 'modelSummaries[].modelId'
}

variable "project" {
  description = "プロジェクト名（全リソース名のプレフィックスに使用）"
  type        = string
  default     = "bedrock-demo"

  validation {
    # リソース名に使える文字を制限（S3バケット命名規則に合わせる）
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "project は小文字英数字とハイフンのみ使用可能です。"
  }
}

variable "env" {
  description = "環境名 (dev / stg / prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prod"], var.env)
    error_message = "env は dev / stg / prod のいずれかを指定してください。"
  }
}

# ── Bedrock モデル設定 ────────────────────────────────────────
# ポイント: モデルIDの形式
#   {provider}.{model-name}:{version}
#   例: anthropic.claude-3-5-haiku-20241022-v1:0
#
# コスト比較（2024年12月時点 / 1K tokens）:
# ┌─────────────────────────────────────────┬──────────┬──────────┐
# │ モデル                                   │ Input    │ Output   │
# ├─────────────────────────────────────────┼──────────┼──────────┤
# │ anthropic.claude-3-haiku-20240307-v1:0  │ $0.00025 │ $0.00125 │
# │ anthropic.claude-3-5-haiku-20241022-v1:0│ $0.0008  │ $0.004   │← 推奨
# │ anthropic.claude-3-5-sonnet-20241022-v2 │ $0.003   │ $0.015   │
# │ anthropic.claude-3-opus-20240229-v1:0   │ $0.015   │ $0.075   │
# └─────────────────────────────────────────┴──────────┴──────────┘
#
# Titan / Mistral など他社モデルも利用可能（マルチモデル比較に活用）
variable "bedrock_model_id" {
  description = "デフォルトで使用するBedrockモデルID（Claude 3.5 Haiku推奨）"
  type        = string
  default     = "anthropic.claude-3-5-haiku-20241022-v1:0"
}

# ── 機能フラグ（コスト管理） ──────────────────────────────────
# ポイント: IaC でのコスト制御パターン
#   count = var.enable_xxx ? 1 : 0 でリソースを条件付き作成

# ⚠️  Knowledge Base の費用構造:
#   OpenSearch Serverless = OCU (OpenSearch Compute Unit) 単位で課金
#   最小構成（2 OCU）= $0.24/OCU/時 × 2 × 24時間 × 30日 ≈ $346/月
#   → アイドル状態でも課金が止まらないため学習後は destroy 必須
variable "enable_knowledge_base" {
  description = <<-EOT
    Bedrock Knowledge Base (RAG) を有効化するか。
    true にすると OpenSearch Serverless が起動し最低 ~$350/月 の費用が発生します。
    学習時のみ true にして terraform apply → destroy のサイクルで使用してください。
  EOT
  type    = bool
  default = false
}

# Bedrock Agent: Lambda をツールとして呼び出すマルチステップ実行基盤
# アイドルコスト = $0（呼び出し時のみ課金）
variable "enable_agent" {
  description = "Bedrock Agent（マルチステップタスク実行）を有効化するか"
  type        = bool
  default     = true
}

# Guardrails: テキスト処理リクエストあたり $0.75/1K テキストユニット
# アイドルコスト = $0
variable "enable_guardrails" {
  description = "Bedrock Guardrails（コンテンツフィルタ・PII・トピック拒否）を有効化するか"
  type        = bool
  default     = true
}

# ── Lambda 設定 ───────────────────────────────────────────────
# ポイント: Bedrock API のタイムアウト考慮
#   - 通常のテキスト生成: 数秒〜30秒
#   - 長文生成・RAG: 最大60秒
#   - Agent のマルチステップ: 最大120秒（複数の ReAct ループ）
variable "lambda_timeout" {
  description = "Lambda タイムアウト秒数（最大900秒。Bedrock呼び出しは60秒以上推奨）"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "lambda_timeout は 30〜900 の範囲で指定してください。"
  }
}

# メモリ: コストとパフォーマンスのトレードオフ
# Lambda の料金 = リクエスト数 + (メモリ × 実行時間) で決まる
# Bedrock 呼び出しは IO バウンドなのでメモリ増加の効果は小さい
variable "lambda_memory" {
  description = "Lambda メモリサイズ (MB)。128〜10240の範囲。Bedrock呼び出しは256MBで十分"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory >= 128 && var.lambda_memory <= 10240
    error_message = "lambda_memory は 128〜10240 (MB) の範囲で指定してください。"
  }
}

# ── ログ保持期間 ──────────────────────────────────────────────
# ポイント: CloudWatch Logs 料金
#   保存コスト: $0.03/GB/月
#   取り込みコスト: $0.50/GB
#
# 保持期間の選択指針:
#   開発環境: 7日（コスト最小）
#   本番環境: 30〜90日（監査・デバッグに十分な期間）
#   コンプライアンス要件がある場合: S3 に長期アーカイブを別途設定
variable "log_retention_days" {
  description = "CloudWatch Logs の保持日数。短いほどコスト削減（dev=7, prod=30〜90推奨）"
  type        = number
  default     = 7

  validation {
    # CloudWatch Logs が受け付ける有効な保持日数のみ許可
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days は CloudWatch が許可する値（1,3,5,7,14,30...）を指定してください。"
  }
}
