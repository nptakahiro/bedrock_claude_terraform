"""
Bedrock RAG Lambda — Knowledge Base を使った検索拡張生成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

カバー概念:
  - RAG (Retrieval-Augmented Generation) のアーキテクチャ
  - RetrieveAndGenerate API（検索 + 生成を一括）
  - Retrieve API（ベクトル検索のみ）
  - チャンク・埋め込み・ベクトル検索の仕組み
  - Citations（引用）の扱い方
  - プロンプトテンプレート（$search_results$ / $query$ 変数）

エンドポイント: POST /rag
リクエスト形式:
  {
    "query":         "検索・回答してほしい質問",   // 必須
    "retrieve_only": false                          // true で検索結果のみ返す
  }

レスポンス形式（retrieve_only=false）:
  {
    "query":     "質問テキスト",
    "answer":    "AIが生成した回答",
    "citations": [
      {
        "text":       "引用した回答の断片",
        "references": [{"ドキュメント情報"}]
      }
    ]
  }

レスポンス形式（retrieve_only=true）:
  {
    "query":   "質問テキスト",
    "results": [
      {
        "content":  "マッチしたチャンクのテキスト",
        "score":    0.95,      // コサイン類似度スコア（0〜1）
        "location": {...}      // S3 パス等のメタデータ
      }
    ]
  }

前提条件:
  - enable_knowledge_base=true で terraform apply 済み
  - Knowledge Base の Data Source Sync 完了済み
"""

import json
import os
import boto3

# ── クライアント初期化 ────────────────────────────────────────
# bedrock-agent-runtime: Knowledge Base の操作
#   - retrieve()              → ベクトル検索のみ
#   - retrieve_and_generate() → 検索 + 生成（RAG）
# bedrock-runtime（chat/handler.py）: モデル直接呼び出し
bedrock_agent_runtime = boto3.client(
    "bedrock-agent-runtime", region_name=os.environ["AWS_REGION"]
)

# ── 環境変数 ──────────────────────────────────────────────────
KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID", "")
MODEL_ARN = os.environ.get(
    "MODEL_ARN",
    # ポイント: Knowledge Base 用モデルは ARN 形式で指定
    # 通常の InvokeModel は modelId（短い文字列）で指定するが、
    # RetrieveAndGenerate は完全な ARN が必要
    "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-haiku-20241022-v1:0",
)


def lambda_handler(event, context):
    """
    API Gateway からのリクエストを処理するメインハンドラー。

    retrieve_only フラグで動作を切り替え:
      False (デフォルト): RetrieveAndGenerate → 回答 + 引用元
      True             : Retrieve のみ       → 検索結果（チャンク）一覧
    """
    body = json.loads(event.get("body", "{}"))
    query = body.get("query", "")
    retrieve_only = body.get("retrieve_only", False)  # 検索のみのモード

    if not query:
        return _response(400, {"error": "query is required"})

    if not KNOWLEDGE_BASE_ID:
        # Knowledge Base が無効の場合（enable_knowledge_base=false）
        return _response(503, {"error": "Knowledge Base not configured. Set enable_knowledge_base=true in Terraform."})

    try:
        if retrieve_only:
            # ── Retrieve のみ（引用元ドキュメントの検索） ─────────
            # ポイント: Retrieve API
            #   - クエリをベクトル化 → OpenSearch でコサイン類似検索
            #   - numberOfResults: 上位 N 件を返す（精度 vs レスポンス速度のトレードオフ）
            #   - score: 0〜1 のコサイン類似度（高いほど関連性が高い）
            result = bedrock_agent_runtime.retrieve(
                knowledgeBaseId=KNOWLEDGE_BASE_ID,
                retrievalQuery={"text": query},
                retrievalConfiguration={
                    "vectorSearchConfiguration": {
                        "numberOfResults": 5,  # 上位5件を返す
                        # "filter": {...}  # メタデータフィルタも可能
                    }
                },
            )
            return _response(200, {
                "query": query,
                "results": [
                    {
                        "content": r["content"]["text"],
                        "score": r["score"],           # コサイン類似度（0〜1）
                        "location": r.get("location", {}),  # S3 パス等
                    }
                    for r in result["retrievalResults"]
                ],
            })
        else:
            # ── RetrieveAndGenerate（検索 + 生成） ────────────────
            # ポイント: RetrieveAndGenerate API
            #   フロー: Query → Retrieve（ベクトル検索） → Generate（LLM生成）
            #
            #   promptTemplate の特殊変数:
            #     $search_results$ → 検索で取得したチャンクを自動挿入
            #     $query$          → ユーザーのクエリを自動挿入
            #
            #   citations（引用）:
            #     - どのチャンクから生成したかを追跡
            #     - 回答の信頼性評価・ハルシネーション検出に活用
            result = bedrock_agent_runtime.retrieve_and_generate(
                input={"text": query},
                retrieveAndGenerateConfiguration={
                    "type": "KNOWLEDGE_BASE",
                    "knowledgeBaseConfiguration": {
                        "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                        "modelArn": MODEL_ARN,
                        "retrievalConfiguration": {
                            "vectorSearchConfiguration": {
                                "numberOfResults": 3,  # 生成に使うチャンク数
                                # 少なすぎると情報不足、多すぎるとコンテキスト肥大化
                            }
                        },
                        "generationConfiguration": {
                            "promptTemplate": {
                                # カスタムプロンプトで回答品質をコントロール
                                # $search_results$ と $query$ は必須変数
                                "textPromptTemplate": (
                                    "以下の文書を参考に質問に答えてください。"
                                    "文書にない情報は「わかりません」と答えてください。\n\n"
                                    "$search_results$\n\n"
                                    "質問: $query$"
                                )
                            }
                        },
                    },
                },
            )

            # ── Citations（引用）の解析 ───────────────────────────
            # ポイント: citations で回答の根拠を示す
            #   generatedResponsePart.textResponsePart.text → 回答の断片
            #   retrievedReferences → その断片が参照したチャンク情報
            return _response(200, {
                "query": query,
                "answer": result["output"]["text"],
                "citations": [
                    {
                        "text": c["generatedResponsePart"]["textResponsePart"]["text"],
                        # references: 参照元ドキュメントの情報（S3パス等）
                        "references": [
                            r["retrievedReferences"]
                            for r in c.get("retrievedReferences", [])
                        ],
                    }
                    for c in result.get("citations", [])
                ],
            })

    except Exception as e:
        return _response(500, {"error": str(e)})


def _response(status: int, body: dict) -> dict:
    """API Gateway Lambda Proxy Integration 形式のレスポンスを生成する。"""
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }
