# observability モジュール

Bedrock モデル呼び出しのロギングと CloudWatch による監視を管理します。  
他のモジュールの出力を受け取り、**横断的な可観測性**を提供します。

---

## 作成リソース

### IAM

| リソース | 用途 |
|---|---|
| `aws_iam_role.bedrock_logging` | Bedrock が S3 へログを書き込むロール |

### Bedrock モデル呼び出しログ

```
全モデル呼び出し
  → CloudWatch Logs（/aws/bedrock/model-invocations）  ← リアルタイム分析
  → S3（invocations/）                                  ← 長期保存・コスト分析
  → S3（large-payloads/）                               ← 大きなペイロード専用
```

`aws_bedrock_model_invocation_logging_configuration` で、テキスト・埋め込み・画像の全データを記録します。

### CloudWatch ダッシュボード

| ウィジェット | メトリクス |
|---|---|
| Lambda 実行回数 | chat / rag 関数の Invocations |
| Lambda エラー率 | chat / rag 関数の Errors |
| Lambda レイテンシ | chat / rag 関数の Duration (p95) |
| DynamoDB 読み書き | 会話履歴テーブルの消費 RCU/WCU |
| API Gateway リクエスト数 | Count |
| API Gateway エラー | 4XXError / 5XXError |

### CloudWatch アラーム

| アラーム名 | 条件 | 目的 |
|---|---|---|
| `{prefix}-lambda-errors` | Lambda エラーが 5分で 10件超 | 異常検知 |
| `{prefix}-bedrock-throttle` | Lambda スロットリングが 1分で 5件超 | レート制限超過の検知 |

> **スロットリング対策**: `handler.py` に指数バックオフ付きリトライが実装されています。  
> クォータ引き上げが必要な場合は `aws service-quotas` コマンドで確認してください。

---

## CloudWatch Logs Insights 活用例

デプロイ後、以下のクエリでトークン使用量を分析できます：

```sql
fields @timestamp, @message
| filter @message like /tokenUsage/
| parse @message '"inputTokens":*,' as inputTokens
| parse @message '"outputTokens":*,' as outputTokens
| stats sum(inputTokens) as totalInput,
        sum(outputTokens) as totalOutput
    by bin(1h)
| sort @timestamp desc
```

---

## 変数

| 変数名 | 型 | 説明 |
|---|---|---|
| `name_prefix` | string | リソース名プレフィックス |
| `common_tags` | map(string) | 共通タグ |
| `aws_region` | string | AWSリージョン |
| `bedrock_logs_bucket_name` | string | Bedrock ログ S3 バケット名 |
| `bedrock_logs_bucket_arn` | string | Bedrock ログ S3 バケット ARN（IAM ポリシー用） |
| `chat_lambda_name` | string | Chat Lambda 関数名（メトリクス・アラーム用） |
| `rag_lambda_name` | string | RAG Lambda 関数名（メトリクス用） |
| `conversation_table_name` | string | 会話履歴テーブル名（メトリクス用） |
| `api_gateway_name` | string | API Gateway 名（メトリクス用） |
| `log_retention_days` | number | CloudWatch Logs 保持日数 |

---

## 出力

| 出力名 | 説明 |
|---|---|
| `dashboard_url` | CloudWatch ダッシュボードへの直接リンク |

---

## 依存関係

```
storage      →  bedrock_logs_bucket_name / bedrock_logs_bucket_arn
              →  conversation_table_name
compute      →  chat_lambda_name / rag_lambda_name / api_gateway_name
  ↓
observability（末端。他モジュールへの出力依存なし）
```
