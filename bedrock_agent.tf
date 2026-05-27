# ── Bedrock Agent ─────────────────────────────────────────────
# 実装ポイント:
#   - Agent = ReAct ループ（Reasoning → Action → Observation）
#   - Action Group: Lambda関数をツールとして登録
#   - Knowledge Base: RAGをエージェントに統合
#   - Memory: 会話を跨いだ記憶（DynamoDB連携）
#   - Alias + Version: デプロイ管理

resource "aws_bedrockagent_agent" "main" {
  count = var.enable_agent ? 1 : 0

  agent_name              = "${local.name_prefix}-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent[0].arn
  foundation_model        = var.bedrock_model_id
  description             = "デモ用デモエージェント（マルチステップタスク実行）"

  # エージェントへの指示（System Prompt相当）
  # ポイント: 明確なペルソナ定義がエージェントの品質を決定する
  instruction = <<-EOT
    あなたはAWSクラウドアーキテクチャの専門家AIアシスタントです。
    ユーザーの質問に対して以下のツールを使って回答してください:

    1. chat_tool: 一般的な会話・質問応答に使用
    2. ドキュメント検索が必要な場合はKnowledge Baseを参照

    回答は日本語で、簡潔かつ技術的に正確に行ってください。
    不明な点は「わかりません」と答え、推測で回答しないでください。
  EOT

  # アイドルタイムアウト（秒）
  idle_session_ttl_in_seconds = 600  # 10分

  # エージェントのメモリ設定
  # ポイント: SUMMARIZATION = 会話サマリーをセッション間で保持
  memory_configuration {
    enabled_memory_types = ["SUMMARIZATION"]
    storage_days         = 30
  }
}

# ── Action Group ───────────────────────────────────────────────
# ポイント: Lambda関数をエージェントのツールとして登録
# OpenAPI スキーマでツールのI/Oを定義
resource "aws_bedrockagent_agent_action_group" "chat" {
  count = var.enable_agent ? 1 : 0

  agent_id          = aws_bedrockagent_agent.main[0].agent_id
  agent_version     = "DRAFT"
  action_group_name = "chat-tool"
  description       = "会話・質問応答ツール"

  action_group_executor {
    lambda = aws_lambda_function.chat.arn
  }

  # OpenAPI スキーマ（インライン定義）
  # ポイント: エージェントはこのスキーマを見てツールの使い方を判断する
  api_schema {
    payload = jsonencode({
      openapi = "3.0.0"
      info = {
        title   = "Chat Tool"
        version = "1.0.0"
      }
      paths = {
        "/chat" = {
          post = {
            summary     = "チャットメッセージを送信して応答を得る"
            operationId = "sendChatMessage"
            requestBody = {
              required = true
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      message = {
                        type        = "string"
                        description = "ユーザーからのメッセージ"
                      }
                      session_id = {
                        type        = "string"
                        description = "会話セッションID（省略時は自動生成）"
                      }
                    }
                    required = ["message"]
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "成功"
                content = {
                  "application/json" = {
                    schema = {
                      type = "object"
                      properties = {
                        response = {
                          type        = "string"
                          description = "AIの応答テキスト"
                        }
                        session_id = {
                          type        = "string"
                          description = "セッションID"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })
  }
}

# Lambda に Bedrock Agent からの実行権限を付与
resource "aws_lambda_permission" "bedrock_agent" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.main[0].agent_arn
}

# ── Agent Alias ────────────────────────────────────────────────
# ポイント: DRAFT → バージョン → Alias でデプロイ管理
# Alias を使うと「prod」「staging」で異なるバージョンを指せる
resource "aws_bedrockagent_agent_alias" "main" {
  count = var.enable_agent ? 1 : 0

  agent_id         = aws_bedrockagent_agent.main[0].agent_id
  agent_alias_name = "dev"
  description      = "開発用エイリアス（DRAFTバージョン）"

  # routing_configuration を省略すると DRAFT バージョンにルーティング
}
