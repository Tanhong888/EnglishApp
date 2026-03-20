from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.response import success
from app.db.models import Article
from app.db.session import get_db

router = APIRouter()


@router.get('/recommendations')
def recommendations(db: Session = Depends(get_db)) -> dict:
    articles = db.scalars(select(Article).where(Article.is_published.is_(True)).order_by(Article.published_at.desc()).limit(3)).all()
    today = [
        {
            "id": article.id,
            "title": article.title,
            "stage": article.stage_tag,
            "level": article.level,
            "topic": article.topic,
            "reading_minutes": article.reading_minutes,
            "is_completed": article.is_completed,
            "published_at": article.published_at.isoformat(),
        }
        for article in articles
    ]

    return success({"today": today, "quick_entries": ["cet4", "cet6", "kaoyan"]})
