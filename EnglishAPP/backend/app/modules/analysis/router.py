from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.response import success
from app.db.models import Article, SentenceAnalysis
from app.db.session import get_db

router = APIRouter()


@router.get("/{article_id}/sentence-analyses")
def sentence_analyses(article_id: int, db: Session = Depends(get_db)) -> dict:
    article = db.get(Article, article_id)
    if article is None or not article.is_published:
        raise HTTPException(status_code=404, detail="article not found")

    rows = db.scalars(
        select(SentenceAnalysis)
        .where(SentenceAnalysis.article_id == article_id)
        .order_by(SentenceAnalysis.sentence_index.asc(), SentenceAnalysis.id.asc())
    ).all()

    return success(
        {
            "article_id": article_id,
            "items": [
                {
                    "sentence_id": row.id,
                    "sentence": row.sentence,
                    "translation": row.translation,
                    "structure": row.structure,
                }
                for row in rows
            ],
        }
    )
