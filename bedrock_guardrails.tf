# ── Bedrock Guardrails ────────────────────────────────────────
# 実装ポイント:
#   - Guardrails = 入出力フィルタリングの安全ガード
#   - コンテンツフィルタ、PIIマスキング、トピック拒否、ワードブロック
#   - ApplyGuardrail API で事後検証も可能

resource "aws_bedrock_guardrail" "main" {
  count = var.enable_guardrails ? 1 : 0

  name                      = "${local.name_prefix}-guardrail"
  blocked_input_messaging   = "申し訳ありませんが、このリクエストはポリシーに違反するため処理できません。"
  blocked_outputs_messaging = "申し訳ありませんが、この回答は安全ポリシーにより表示できません。"
  description               = "デモ用デモ Guardrail"

  # ── コンテンツフィルタ ─────────────────────────────────────
  # ポイント: HATE/INSULTS/SEXUAL/VIOLENCE/MISCONDUCT/PROMPT_ATTACK
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
      # プロンプトインジェクション攻撃の検出
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"  # 出力にはPROMPT_ATTACKフィルタ不要
    }
  }

  # ── PIIマスキング ──────────────────────────────────────────
  # ポイント: 個人情報の自動検出・マスキング/ブロック
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"  # マスキング（ブロックの代わりに匿名化）
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
      action = "BLOCK"  # 住所は完全ブロック
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

  # ── トピック拒否 ───────────────────────────────────────────
  # ポイント: 特定トピックへの回答を拒否（例: 投資アドバイス）
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

  # ── ワードブロック ─────────────────────────────────────────
  # ポイント: カスタムワードリストによるフィルタリング
  word_policy_config {
    words_config {
      text = "競合他社名A"
    }
    words_config {
      text = "機密プロジェクト名"
    }
    # マネージドワードリスト（AWSToxicContent等）
    managed_word_lists_config {
      type = "PROFANITY"
    }
  }
}

# Guardrails のバージョン管理
# ポイント: DRAFT → バージョン番号 でプロダクション昇格
resource "aws_bedrock_guardrail_version" "main" {
  count = var.enable_guardrails ? 1 : 0

  guardrail_arn = aws_bedrock_guardrail.main[0].guardrail_arn
  description   = "Initial version for demo"
}
