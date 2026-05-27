"""
Bedrock Chat Lambda — Claude 直接呼び出し + 会話履歴管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

カバー概念:
  - InvokeModel API (bedrock-runtime)
  - InvokeModelWithResponseStream（ストリーミング SSE）
  - Anthropic Messages API 形式（anthropic_version / messages / system）
  - Guardrails の適用（guardrailIdentifier / guardrailVersion）
  - DynamoDB による会話履歴の永続化と TTL 管理
  - コンテキストウィンドウ管理（直近 N 往復に制限）

エンドポイント: POST /chat
リクエスト形式:
  {
    "message":    "ユーザーのメッセージ",    // 必須
    "session_id": "任意のセッションID",       // 省略時: タイムスタンプから自動生成
    "stream":     false                       // true でストリーミングレスポンス
  }

レスポンス形式:
  {
    "session_id": "session-1234567890",
    "response":   "AIの回答テキスト",
    "model":      "anthropic.claude-3-5-haiku-20241022-v1:0",
    "usage":      {"input_tokens": 50, "output_tokens": 200}  // stream=false のみ
  }
"""

import json
import os
import time
import boto3
from datetime import datetime, timezone

# ── クライアント初期化 ────────────────────────────────────────
# bedrock-runtime: モデル直接呼び出し（InvokeModel / ストリーミング）
# bedrock-agent-runtime: Knowledge Base / Agent 呼び出し（rag/handler.py で使用）
bedrock = boto3.client("bedrock-runtime", region_name=os.environ["AWS_REGION"])

# DynamoDB リソース（テーブル操作）
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["CONVERSATION_TABLE"])

# ── 環境変数 ──────────────────────────────────────────────────
# Lambda の環境変数は lambda.tf の environment ブロックで定義されている
MODEL_ID = os.environ.get("MODEL_ID", "anthropic.claude-3-5-haiku-20241022-v1:0")
GUARDRAIL_ID = os.environ.get("GUARDRAIL_ID", "")       # 空文字 = Guardrails 無効
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "DRAFT")
# ポイント: DRAFT = 最新の未公開バージョン。本番では番号を固定すること


def lambda_handler(event, context):
    """
    API Gateway からのリクエストを処理するメインハンドラー。

    event 構造 (API Gateway Lambda Proxy Integration):
      event["body"]       → JSON 文字列（リクエストボディ）
      event["headers"]    → リクエストヘッダー
      event["pathParameters"] → パスパラメータ
    """
    # リクエストボディの解析
    body = json.loads(event.get("body", "{}"))
    session_id = body.get("session_id", f"session-{int(time.time())}")
    user_message = body.get("message", "")
    stream = body.get("stream", False)

    if not user_message:
        return _response(400, {"error": "message is required"})

    # ── 会話履歴の取得 ─────────────────────────────────────────
    # DynamoDB から直近のやり取りを取得し、プロンプトに組み込む
    # ポイント: コンテキストウィンドウ管理
    #   - 全履歴を送ると max_tokens を超えてエラーになる
    #   - 直近 N 往復に制限してトークン数をコントロール
    history = _get_history(session_id)
    history.append({"role": "user", "content": user_message})

    # ── Bedrock リクエスト構築 ─────────────────────────────────
    # Anthropic Messages API 形式
    # ポイント:
    #   - "anthropic_version": "bedrock-2023-05-31" は必須（Bedrock固有のバージョン）
    #   - "system" プロンプト: モデルの役割・制約を定義（messages の外に書く）
    #   - "messages": user/assistant の交互ターン（必ず user から始まる）
    #   - "max_tokens": 出力トークン上限（コスト・タイムアウト管理）
    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1000,
        "messages": history,
        "system": "You are a helpful AI assistant. Answer questions clearly and concisely.",
    }

    # ── Guardrails の適用 ─────────────────────────────────────
    # ポイント: Guardrails は2通りの使い方がある
    #   1. InvokeModel 時に埋め込む（この実装）: リクエスト単位で自動適用
    #   2. ApplyGuardrail API で事後検証: 生成後に別途チェック（柔軟だがコード複雑）
    invoke_kwargs = {
        "modelId": MODEL_ID,
        "body": json.dumps(request_body),
        "contentType": "application/json",
        "accept": "application/json",
    }
    if GUARDRAIL_ID:
        invoke_kwargs["guardrailIdentifier"] = GUARDRAIL_ID
        invoke_kwargs["guardrailVersion"] = GUARDRAIL_VERSION

    try:
        if stream:
            # ── ストリーミングレスポンス ────────────────────────
            # ポイント: InvokeModelWithResponseStream
            #   - レスポンスを chunk ごとに逐次受信（SSE: Server-Sent Events）
            #   - チャンクの type:
            #       "content_block_start"  → ブロック開始
            #       "content_block_delta"  → テキストの増分（ここで文字を取得）
            #       "content_block_stop"   → ブロック終了
            #       "message_delta"        → stop_reason / usage が含まれる
            response = bedrock.invoke_model_with_response_stream(**invoke_kwargs)
            assistant_text = ""
            for event in response["body"]:
                chunk = json.loads(event["chunk"]["bytes"])
                if chunk.get("type") == "content_block_delta":
                    assistant_text += chunk["delta"].get("text", "")
        else:
            # ── 同期レスポンス ──────────────────────────────────
            # ポイント: InvokeModel は完全な応答が生成されるまで待機
            #   - response["body"] は StreamingBody（.read() で取得）
            #   - result["content"][0]["text"] が生成されたテキスト
            #   - result["usage"] にトークン使用量（input/output_tokens）
            response = bedrock.invoke_model(**invoke_kwargs)
            result = json.loads(response["body"].read())
            assistant_text = result["content"][0]["text"]

        # ── 会話履歴を DynamoDB に保存 ─────────────────────────
        # ユーザーの入力と AI の回答をセットで保存
        _save_message(session_id, "user", user_message)
        _save_message(session_id, "assistant", assistant_text)

        return _response(200, {
            "session_id": session_id,
            "response": assistant_text,
            "model": MODEL_ID,
            # usage はストリーミング時は空（取得が複雑なため省略）
            "usage": result.get("usage", {}) if not stream else {},
        })

    except bedrock.exceptions.ThrottlingException:
        # ポイント: Bedrock のレート制限（Service Quota）
        #   - TPS / 分あたりの呼び出し数が制限される
        #   - 本番では指数バックオフ + ジッターで自動リトライ実装が必要
        #   - 急いで上限を引き上げたい場合: AWS コンソール → Service Quotas
        return _response(429, {"error": "Rate limit exceeded. Try again later."})
    except Exception as e:
        return _response(500, {"error": str(e)})


def _get_history(session_id: str, limit: int = 10) -> list:
    """
    DynamoDB から直近の会話履歴を取得する。

    設計ポイント:
      - ScanIndexForward=False で新しい順にソート → Limit で直近 N 件取得
      - その後 sorted() で古い順に並び替え（Bedrock Messages API は時系列順が必要）
      - limit * 2: user と assistant がペアなので2倍の件数を取得

    Args:
        session_id: セッション識別子
        limit: 取得する往復数（デフォルト10往復 = 20メッセージ）

    Returns:
        [{"role": "user"|"assistant", "content": "..."}, ...]
    """
    try:
        resp = table.query(
            # ポイント: DynamoDB の Query vs Scan
            #   Query: パーティションキー指定 → 効率的（O(1)に近い）
            #   Scan : 全件取得 → 大量データで高コスト・低速
            KeyConditionExpression="session_id = :sid",
            ExpressionAttributeValues={":sid": session_id},
            ScanIndexForward=False,  # timestamp の降順（新しい順）
            Limit=limit * 2,         # user + assistant = 1往復 = 2件
        )
        # 取得後に古い順（昇順）でソート（Claude の Messages API は時系列順が必須）
        items = sorted(resp.get("Items", []), key=lambda x: x["timestamp"])
        return [{"role": item["role"], "content": item["content"]} for item in items]
    except Exception:
        # 履歴取得エラーは無視して空履歴で続行（セッション初回など）
        return []


def _save_message(session_id: str, role: str, content: str):
    """
    メッセージを DynamoDB に保存する。

    テーブル設計:
      PK (hash_key) : session_id  → 同一セッションをまとめる
      SK (range_key): timestamp   → 時系列ソートを可能に

    ポイント: DynamoDB TTL（Time to Live）
      - expires_at に epoch 秒を設定 → TTL 機能が自動削除
      - GDPR/個人情報保護: 古いデータを自動削除してプライバシーを保護
      - コスト削減: 不要データが積み上がるのを防ぐ
      - 削除タイミング: TTL 設定時刻の数分〜数十分後（厳密なリアルタイムではない）
    """
    now = datetime.now(timezone.utc)
    table.put_item(Item={
        "session_id": session_id,
        "timestamp": now.isoformat(),        # ISO 8601 形式（ソートキー）
        "role": role,                         # "user" or "assistant"
        "content": content,
        "expires_at": int(now.timestamp()) + 7 * 24 * 3600,  # 7日後に自動削除
    })


def _response(status: int, body: dict) -> dict:
    """
    API Gateway Lambda Proxy Integration 形式のレスポンスを生成する。

    必須フィールド:
      statusCode: HTTP ステータスコード（200 / 400 / 429 / 500）
      headers:    レスポンスヘッダー
      body:       JSON 文字列（dict ではなく文字列）

    ensure_ascii=False: 日本語がそのまま保存される（エスケープされない）
    Access-Control-Allow-Origin: ブラウザからの直接アクセスを許可（CORS設定）
    """
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",  # 本番では特定ドメインに制限
        },
        "body": json.dumps(body, ensure_ascii=False),
    }
