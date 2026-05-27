# ── DynamoDB ──────────────────────────────────────────────────
# 実装ポイント:
#   - 会話履歴の永続化にはDynamoDBが定番
#   - PAY_PER_REQUEST (オンデマンド) = アイドル時の課金ゼロ
#   - TTLで古いセッションを自動削除 → コスト削減

# 会話履歴テーブル
resource "aws_dynamodb_table" "conversation_history" {
  name         = "${local.name_prefix}-conversations"
  billing_mode = "PAY_PER_REQUEST"  # サーバーレス課金（idle時$0）
  hash_key     = "session_id"
  range_key    = "timestamp"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  # TTL: 7日後に自動削除（コスト削減 + プライバシー）
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  # ポイントインタイムリカバリ（本番は true 推奨、学習用はfalse）
  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }
}

# Bedrock Agent セッションキャッシュ用テーブル
resource "aws_dynamodb_table" "agent_sessions" {
  count = var.enable_agent ? 1 : 0

  name         = "${local.name_prefix}-agent-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }
}
