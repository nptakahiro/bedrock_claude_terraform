# ── ローカル変数 ───────────────────────────────────────────────
# locals = 複数箇所で使い回す式をまとめた定数的な値
# variable との違い: 外部から上書きできない（内部計算専用）

locals {
  # リソース名プレフィックス
  # 例: project="bedrock-demo", env="dev" → "bedrock-demo-dev"
  # すべてのリソース名にこれを付けることで:
  #   - 同一 AWS アカウント内での衝突を防ぐ
  #   - Cost Explorer でプロジェクト別コストを集計しやすくなる
  #   - terraform destroy 時に削除対象を特定しやすい
  name_prefix = "${var.project}-${var.env}"

  # 共通タグ
  # ポイント: AWS Well-Architected Framework の運用面では
  # タグ付け戦略が重要。以下のタグが特に有効:
  #
  #   Project     → AWS Cost Explorer でプロジェクト単位のコスト把握
  #   Environment → 本番/開発の誤操作を防ぐ視覚的な識別子
  #   ManagedBy   → 手動変更を抑止する（"terraform" なら Terraform で管理）
  #
  # 追加で検討するタグ例（本番環境）:
  #   Owner       = "takahiro@example.com"  # 担当者の連絡先
  #   CostCenter  = "engineering"            # コスト配分コード
  #   Compliance  = "internal"              # コンプライアンス区分
  common_tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }
}
