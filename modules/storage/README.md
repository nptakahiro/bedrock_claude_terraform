# storage モジュール

S3 バケットと DynamoDB テーブルを管理します。  
他の全モジュールが依存する**基盤レイヤー**です。

---

## 作成リソース

| リソース | 用途 | アイドルコスト |
|---|---|---|
| `aws_s3_bucket.documents` | Knowledge Base のデータソース（ドキュメント格納） | ~$0.023/GB/月 |
| `aws_s3_bucket.bedrock_logs` | Bedrock モデル呼び出しログの長期保存 | ~$0.023/GB/月 |
| `aws_dynamodb_table.conversation_history` | チャット会話履歴（TTL=7日で自動削除） | $0（PAY_PER_REQUEST）|
| `aws_dynamodb_table.agent_sessions` | Bedrock Agent セッションキャッシュ | $0（PAY_PER_REQUEST）|

### S3 セキュリティ設定（両バケット共通）

- **SSE-S3 (AES256)**: サーバー側暗号化（AWS 管理キー）
- **パブリックアクセスブロック**: 4重ガードで意図しない公開を防止
- **バージョニング**: `documents` バケットで有効（Ingestion 履歴の管理）
- **ライフサイクル**: `bedrock_logs` バケットは 30日後 IA 移行 → 90日後削除

### DynamoDB 設計

```
conversation_history
  PK: session_id (S)   ← セッション単位で会話を管理
  SK: timestamp   (S)  ← 時系列ソート
  TTL: expires_at      ← 7日後に自動削除（コスト削減 + プライバシー）

agent_sessions          ← enable_agent=true 時のみ作成
  PK: session_id (S)
  TTL: expires_at
```

---

## 変数

| 変数名 | 型 | 説明 |
|---|---|---|
| `name_prefix` | string | リソース名プレフィックス（例: `bedrock-demo-dev`） |
| `common_tags` | map(string) | 全リソースに付与する共通タグ |
| `enable_agent` | bool | `true` の場合 `agent_sessions` テーブルを作成 |

---

## 出力

| 出力名 | 説明 |
|---|---|
| `documents_bucket_id` | ドキュメントバケット ID |
| `documents_bucket_arn` | ドキュメントバケット ARN（IAM ポリシー用） |
| `documents_bucket_name` | ドキュメントバケット名 |
| `bedrock_logs_bucket_arn` | ログバケット ARN（IAM ポリシー用） |
| `bedrock_logs_bucket_name` | ログバケット名 |
| `conversation_table_name` | 会話履歴テーブル名 |
| `conversation_table_arn` | 会話履歴テーブル ARN（IAM ポリシー用） |
| `account_id` | AWS アカウント ID（バケット名一意化・IAM 条件に使用） |
| `caller_arn` | デプロイ実行ユーザー ARN（OpenSearch アクセスポリシー用） |

---

## 依存関係

```
storage（依存なし）
  ↓ outputs を提供
  bedrock / compute / observability
```

このモジュールは外部モジュールに依存しません。
