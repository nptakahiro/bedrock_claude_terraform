# compute モジュール

Lambda 関数と API Gateway を管理します。  
Bedrock モデルへの実際の呼び出しロジックはここに集約されています。

また、`bedrock` モジュールで作成した Agent の Action Group もこのモジュールで定義します  
（循環依存の回避のため）。

---

## ファイル構成

```
compute/
├── main.tf         # IAM / Lambda / API Gateway / Action Group
├── variables.tf
├── outputs.tf
└── lambda/
    ├── chat/
    │   └── handler.py   # InvokeModel + 会話履歴管理
    └── rag/
        └── handler.py   # RetrieveAndGenerate / Retrieve
```

---

## 作成リソース

### IAM

| リソース | 用途 |
|---|---|
| `aws_iam_role.lambda_exec` | Lambda 実行ロール |
| `aws_iam_role_policy.lambda_bedrock` | Bedrock / DynamoDB / S3 へのアクセス権限 |

Lambda に付与される Bedrock 権限:

```
bedrock:InvokeModel / InvokeModelWithResponseStream  → モデル直接呼び出し
bedrock:Retrieve / RetrieveAndGenerate               → Knowledge Base 検索
bedrock:InvokeAgent                                  → Agent 実行
bedrock:ApplyGuardrail                               → Guardrails 事後適用
```

### Lambda 関数

#### `chat` 関数（`/chat` エンドポイント）

```
リクエスト
  → DynamoDB から会話履歴を取得（直近10往復）
  → Guardrails でフィルタリング（enable_guardrails=true 時）
  → InvokeModel / InvokeModelWithResponseStream
  → DynamoDB に会話を保存（TTL 付き）
  → レスポンス
```

環境変数:
| 変数名 | 内容 |
|---|---|
| `CONVERSATION_TABLE` | 会話履歴 DynamoDB テーブル名 |
| `MODEL_ID` | 使用するモデル ID |
| `GUARDRAIL_ID` | Guardrail ID（空文字の場合は無効） |
| `GUARDRAIL_VERSION` | `DRAFT`（固定） |

#### `rag` 関数（`/rag` エンドポイント）

```
リクエスト
  → RetrieveAndGenerate API（Knowledge Base 有効時）
     または Retrieve API（検索のみモード）
  → 引用付き回答を返す
```

環境変数:
| 変数名 | 内容 |
|---|---|
| `KNOWLEDGE_BASE_ID` | Knowledge Base ID（空文字の場合はエラーを返す） |
| `MODEL_ARN` | モデルの完全 ARN |

### API Gateway（REST API）

| エンドポイント | メソッド | 説明 |
|---|---|---|
| `/chat` | POST | チャット API |
| `/rag` | POST | RAG API（Knowledge Base 必須） |
| `/chat` | OPTIONS | CORS プリフライト |

### Bedrock Agent 連携（`enable_agent=true` 時）

| リソース | 説明 |
|---|---|
| `aws_bedrockagent_agent_action_group.chat` | Agent から `chat` Lambda を呼び出す定義 |
| `aws_lambda_permission.bedrock_agent` | Bedrock Agent に Lambda 呼び出し権限を付与 |

> **設計上のポイント**: Action Group を `bedrock` ではなく `compute` に置くことで、  
> `compute → bedrock` の一方向依存を維持し、循環を回避しています。

---

## 変数

| 変数名 | 型 | デフォルト | 説明 |
|---|---|---|---|
| `name_prefix` | string | - | リソース名プレフィックス |
| `common_tags` | map(string) | - | 共通タグ |
| `aws_region` | string | - | AWSリージョン |
| `env` | string | - | 環境名（API Gateway ステージ名） |
| `bedrock_model_id` | string | - | 使用するモデル ID |
| `enable_guardrails` | bool | - | Guardrails を有効化しているか |
| `guardrail_id` | string | `""` | Guardrail ID |
| `enable_knowledge_base` | bool | - | Knowledge Base を有効化しているか |
| `knowledge_base_id` | string | `""` | Knowledge Base ID |
| `enable_agent` | bool | - | Agent を有効化しているか |
| `agent_id` | string | `""` | Agent ID |
| `agent_arn` | string | `""` | Agent ARN |
| `conversation_table_name` | string | - | 会話履歴テーブル名 |
| `conversation_table_arn` | string | - | 会話履歴テーブル ARN |
| `documents_bucket_arn` | string | - | ドキュメント S3 バケット ARN |
| `lambda_timeout` | number | - | Lambda タイムアウト（秒） |
| `lambda_memory` | number | - | Lambda メモリ (MB) |
| `log_retention_days` | number | - | CloudWatch Logs 保持日数 |

---

## 出力

| 出力名 | 説明 |
|---|---|
| `chat_lambda_arn` | Chat Lambda ARN |
| `chat_lambda_name` | Chat Lambda 関数名 |
| `rag_lambda_arn` | RAG Lambda ARN |
| `rag_lambda_name` | RAG Lambda 関数名 |
| `api_endpoint` | API Gateway ベース URL |
| `chat_endpoint` | `/chat` エンドポイント URL |
| `rag_endpoint` | `/rag` エンドポイント URL |
| `api_gateway_name` | API Gateway 名（CloudWatch メトリクス用） |

---

## 依存関係

```
storage  →  conversation_table_name / conversation_table_arn / documents_bucket_arn
bedrock  →  guardrail_id / knowledge_base_id / agent_id / agent_arn
  ↓
compute
  ↓ chat_lambda_name / rag_lambda_name / api_gateway_name
observability
```
