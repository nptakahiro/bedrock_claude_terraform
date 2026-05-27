# ════════════════════════════════════════════════════════════════
# AWS Bedrock × Claude — Terraform クイックスタート
#
# モジュール構成:
#   storage      → S3 + DynamoDB
#   bedrock      → Guardrails / Knowledge Base / Agent + IAM
#   compute      → Lambda + API Gateway + IAM
#   observability→ CloudWatch ログ・ダッシュボード・アラーム
#
# 依存方向: storage → bedrock → compute → observability
# ════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # ステートバックエンド（本番化時は S3 + DynamoDB ロックに変更）
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "bedrock-demo/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "tf-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ── 1. storage ────────────────────────────────────────────────────
module "storage" {
  source = "./modules/storage"

  name_prefix  = local.name_prefix
  common_tags  = local.common_tags
  enable_agent = var.enable_agent
}

# ── 2. bedrock ────────────────────────────────────────────────────
module "bedrock" {
  source = "./modules/bedrock"

  name_prefix           = local.name_prefix
  common_tags           = local.common_tags
  aws_region            = var.aws_region
  bedrock_model_id      = var.bedrock_model_id
  enable_guardrails     = var.enable_guardrails
  enable_knowledge_base = var.enable_knowledge_base
  enable_agent          = var.enable_agent
  documents_bucket_arn  = module.storage.documents_bucket_arn
  documents_bucket_id   = module.storage.documents_bucket_id
  account_id            = module.storage.account_id
  caller_arn            = module.storage.caller_arn
}

# ── 3. compute ────────────────────────────────────────────────────
module "compute" {
  source = "./modules/compute"

  name_prefix             = local.name_prefix
  common_tags             = local.common_tags
  aws_region              = var.aws_region
  env                     = var.env
  bedrock_model_id        = var.bedrock_model_id
  enable_guardrails       = var.enable_guardrails
  guardrail_id            = module.bedrock.guardrail_id
  enable_knowledge_base   = var.enable_knowledge_base
  knowledge_base_id       = module.bedrock.knowledge_base_id
  enable_agent            = var.enable_agent
  agent_id                = module.bedrock.agent_id
  agent_arn               = module.bedrock.agent_arn
  conversation_table_name = module.storage.conversation_table_name
  conversation_table_arn  = module.storage.conversation_table_arn
  documents_bucket_arn    = module.storage.documents_bucket_arn
  lambda_timeout          = var.lambda_timeout
  lambda_memory           = var.lambda_memory
  log_retention_days      = var.log_retention_days
}

# ── 4. observability ──────────────────────────────────────────────
module "observability" {
  source = "./modules/observability"

  name_prefix              = local.name_prefix
  common_tags              = local.common_tags
  aws_region               = var.aws_region
  bedrock_logs_bucket_name = module.storage.bedrock_logs_bucket_name
  bedrock_logs_bucket_arn  = module.storage.bedrock_logs_bucket_arn
  chat_lambda_name         = module.compute.chat_lambda_name
  rag_lambda_name          = module.compute.rag_lambda_name
  conversation_table_name  = module.storage.conversation_table_name
  api_gateway_name         = module.compute.api_gateway_name
  log_retention_days       = var.log_retention_days
}
