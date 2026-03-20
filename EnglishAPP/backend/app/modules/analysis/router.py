from fastapi import APIRouter

from app.core.response import success

router = APIRouter()


@router.get("/{article_id}/sentence-analyses")
def sentence_analyses(article_id: int) -> dict:
    return success(
        {
            "article_id": article_id,
            "items": [
                {
                    "sentence_id": 301,
                    "sentence": "Sleep plays a major role in memory consolidation.",
                    "translation": "睡眠在记忆巩固中起重要作用。",
                    "structure": "主语 + 谓语 + 介词短语",
                }
            ],
        }
    )
