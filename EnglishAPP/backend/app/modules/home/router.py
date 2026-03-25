from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.response import success
from app.db.models import Article
from app.db.session import get_db

router = APIRouter()


def _serialize_article_card(article: Article) -> dict:
    return {
        'id': article.id,
        'title': article.title,
        'stage': article.stage_tag,
        'level': article.level,
        'topic': article.topic,
        'summary': article.summary,
        'reading_minutes': article.reading_minutes,
        'is_completed': article.is_completed,
        'published_at': article.published_at.isoformat(),
    }


@router.get('/recommendations')
def recommendations(db: Session = Depends(get_db)) -> dict:
    articles = db.scalars(
        select(Article)
        .where(Article.is_published.is_(True))
        .order_by(Article.level.asc(), Article.published_at.desc(), Article.id.desc())
        .limit(6)
    ).all()

    return success(
        {
            'today': [_serialize_article_card(article) for article in articles[:3]],
            'trending': [_serialize_article_card(article) for article in articles[3:6]],
            'quick_entries': ['cet4', 'cet6', 'kaoyan'],
        }
    )
