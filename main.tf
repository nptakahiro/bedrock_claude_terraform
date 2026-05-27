# ════════════════════════════════════════════════════════════════
# AWS Bedrock Demo — Terraform メインエントリーポイント
#
# 目的: Amazon Bedrock × Claude の主要機能を Terraform で素早くデプロイする学習用インフラ
#
# アーキテクチャ方針:
#   1. サーバーレス優先 — アイドル時の課金ゼロ（Lambda / API GW / DynamoDB）
#   2. 機能フラグ制御 — 高コストリソースはデフォルト無効
#   3. 最小権限 IAM — サービスごとに独立したロール
#   4. 全 Bedrock 機能カバー — 試験範囲を網羅
#
# コスト目標: アイドル時 $0.50〜$2 / 月
# ════════════════════════════════════════════════════════════════

terraform {
  # Terraform バージョン固定
  # 1.6.0 以上を要求: test コマンド対応、import ブロック安定化
  required_version = ">= 1.6.0"

  required_providers {
    # AWS プロバイダー
    # ~> 5.50 = 5.50 以上 6.0 未満（マイナーバージョンアップは自動適用）
    # Bedrock Agent の Terraform リソースは 5.x で追加されたため 5.50 以上を指定
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }

    # archive プロバイダー: Lambda コードを ZIP に圧縮するために使用
    # data "archive_file" リソースで Lambda ソースをパッケージング
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # ── ステートバックエンド ────────────────────────────────────
  # デフォルト: ローカルの terraform.tfstate（学習環境向け）
  # 本番化・チーム開発時は S3 + DynamoDB ロックに変更すること
  #
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "bedrock-demo/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true               # ステート暗号化
  #   dynamodb_table = "tf-state-lock"    # 並列 apply 防止ロック
  # }
}

# ── AWS プロバイダー設定 ────────────────────────────────────────
provider "aws" {
  region = var.aws_region

  # default_tags: すべてのリソースに自動でタグを付与
  # タグ戦略はコスト配分・ガバナンスの基盤
  #   - Project: コスト配分タグ（Cost Explorer でフィルタ可能）
  #   - Environment: dev / stg / prod の分離
  #   - ManagedBy: IaC 管理であることを明示（手動変更の抑止）
  default_tags {
    tags = local.common_tags
  }
}
