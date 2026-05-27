# bedrock モジュール

Amazon Bedrock の主要機能（Guardrails / Knowledge Base / Agent）と、  
それぞれに必要な IAM ロールを管理します。

各機能は**機能フラグ**（変数）で個別に有効化でき、デフォルト無効のリソースは  
コストが発生しません。

---

## 作成リソース

### IAM

| リソース | 有効条件 | 用途 |
|---|---|---|
| `aws_iam_role.knowledge_base` | `enable_knowledge_base=true` | Bedrock が S3/OpenSearch にアクセス |
| `aws_iam_role.bedrock_agent` | `enable_agent=true` | Agent が Lambda とモデルを呼び出す |

### Guardrails（`enable_guardrails=true` 時）

```
入力 → [コンテンツフィルタ] → [PII マスキング] → [トピック拒否] → [ワードブロック] → モデル
モデル → [コンテンツフィルタ] → [PII マスキング] → 出力
```

| フィルター種別 | 設定内容 |
|---|---|
| コンテンツフィルタ | HATE / INSULTS / SEXUAL / VIOLENCE / MISCONDUCT / PROMPT_ATTACK |
| PII マスキング | EMAIL・PHONE・NAME → ANONYMIZE / ADDRESS・CARD・PASSWORD → BLOCK |
| トピック拒否 | 投資アドバイス、医療診断 |
| ワードブロック | カスタムリスト + PROFANITY マネージドリスト |

バージョン管理: `DRAFT` → `aws_bedrock_guardrail_version` で番号付きバージョンに昇格。

### Knowledge Base（`enable_knowledge_base=true` 時）⚠️ 月額 ~$350

```
S3（ドキュメント）
  → Ingestion パイプライン（チャンキング → Titan Embeddings V2 → 1536次元ベクトル）
  → OpenSearch Serverless（ベクトルインデックス）
  → RetrieveAndGenerate API で RAG 回答生成
```

| リソース | 説明 |
|---|---|
| `aws_opensearchserverless_collection` | ベクトルDBコレクション（VECTORSEARCH タイプ） |
| `aws_bedrockagent_knowledge_base` | Titan Embeddings V2 使用、1536次元 |
| `aws_bedrockagent_data_source` | S3 → Knowledge Base へのデータソース定義 |

> **⚠️ コスト注意**: OpenSearch Serverless は最小 2 OCU × $0.24/時 = 常時 ~$350/月。  
> 学習目的では `terraform apply → destroy` のサイクルで使ってください。

### Agent（`enable_agent=true` 時）

```
ユーザー入力
  → [Reasoning] どのツールを使うか推論
  → [Acting]    Lambda (chat) を呼び出す
  → [Observation] 結果を観察
  → 十分な情報が得られるまでループ
  → 最終回答
```

| リソース | 説明 |
|---|---|
| `aws_bedrockagent_agent` | ReAct ループ、メモリ（SUMMARIZATION）付き |
| `aws_bedrockagent_agent_alias` | `dev` エイリアス（DRAFT バージョンへルーティング） |

> **Note**: Action Group（Lambda との接続）は `compute` モジュールで定義されます。  
> これにより `bedrock ↔ compute` 間の循環依存を回避しています。

---

## 変数

| 変数名 | 型 | 説明 |
|---|---|---|
| `name_prefix` | string | リソース名プレフィックス |
| `common_tags` | map(string) | 共通タグ |
| `aws_region` | string | AWSリージョン |
| `bedrock_model_id` | string | 使用するモデル ID |
| `enable_guardrails` | bool | Guardrails を有効化するか |
| `enable_knowledge_base` | bool | Knowledge Base を有効化するか |
| `enable_agent` | bool | Agent を有効化するか |
| `documents_bucket_arn` | string | Knowledge Base のデータソースとなる S3 バケット ARN |
| `documents_bucket_id` | string | S3 バケット ID |
| `account_id` | string | AWS アカウント ID（IAM 条件用） |
| `caller_arn` | string | デプロイ実行ユーザー ARN（OpenSearch アクセスポリシー用） |

---

## 出力

| 出力名 | 説明 |
|---|---|
| `guardrail_id` | Guardrail ID（無効時は空文字） |
| `guardrail_arn` | Guardrail ARN（無効時は空文字） |
| `knowledge_base_id` | Knowledge Base ID（無効時は空文字） |
| `agent_id` | Agent ID（無効時は空文字） |
| `agent_arn` | Agent ARN（無効時は空文字） |
| `agent_alias_id` | Agent Alias ID（無効時は空文字） |

---

## 依存関係

```
storage
  ↓ documents_bucket_arn / documents_bucket_id / account_id / caller_arn
bedrock
  ↓ guardrail_id / knowledge_base_id / agent_id / agent_arn
compute
```
