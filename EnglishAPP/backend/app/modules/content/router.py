from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.response import success
from app.db.models import Article, ArticleParagraph, User, UserArticleFavorite
from app.db.session import get_db

router = APIRouter()


def serialize_article(article: Article) -> dict:
    return {
        'id': article.id,
        'title': article.title,
        'stage': article.stage_tag,
        'level': article.level,
        'topic': article.topic,
        'reading_minutes': article.reading_minutes,
        'is_completed': article.is_completed,
        'published_at': article.published_at.isoformat(),
    }


@router.get('')
def list_articles(
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    stage: str | None = None,
    level: int | None = Query(default=None, ge=1, le=4),
    topic: str | None = None,
    sort: str = Query(default='recommended'),
    db: Session = Depends(get_db),
) -> dict:
    if sort not in {'recommended', 'latest', 'hot'}:
        raise HTTPException(status_code=400, detail='sort must be one of recommended/latest/hot')

    query = select(Article).where(Article.is_published.is_(True))

    if stage:
        query = query.where(Article.stage_tag == stage)
    if level:
        query = query.where(Article.level == level)
    if topic:
        query = query.where(Article.topic == topic)

    if sort == 'latest':
        query = query.order_by(Article.published_at.desc())
    elif sort == 'hot':
        query = query.order_by(Article.reading_minutes.asc(), Article.published_at.desc())
    else:
        query = query.order_by(Article.level.asc(), Article.published_at.desc())

    total = db.scalar(select(func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * size
    articles = db.scalars(query.offset(offset).limit(size)).all()

    data = {
        'items': [serialize_article(article) for article in articles],
        'page': page,
        'size': size,
        'total': total,
        'has_next': offset + len(articles) < total,
    }
    return success(data)


@router.get('/{article_id}')
def get_article(article_id: int, db: Session = Depends(get_db)) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    paragraphs = db.scalars(
        select(ArticleParagraph)
        .where(ArticleParagraph.article_id == article_id)
        .order_by(ArticleParagraph.paragraph_index.asc())
    ).all()

    detail = {
        **serialize_article(article),
        'paragraphs': [{'index': p.paragraph_index, 'text': p.text} for p in paragraphs],
    }
    return success(detail)


@router.get('/{article_id}/audio')
def get_article_audio(article_id: int, db: Session = Depends(get_db)) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    data = {
        'status': article.audio_status,
        'article_audio_url': article.article_audio_url if article.audio_status == 'ready' else None,
        'paragraph_timestamps': [] if article.audio_status != 'ready' else [{'index': 1, 'start': 0.0, 'end': 2.3}],
        'retry_hint': '稍后重试' if article.audio_status == 'failed' else None,
    }
    return success(data)


@router.get('/{article_id}/favorite-status')
def favorite_status(
    article_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == current_user.id,
            UserArticleFavorite.article_id == article_id,
        )
    )

    return success({'article_id': article_id, 'favorite': favorite.is_favorited if favorite is not None else False})


@router.post('/{article_id}/favorite')
def favorite_article(
    article_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == current_user.id,
            UserArticleFavorite.article_id == article_id,
        )
    )

    if favorite is None:
        favorite = UserArticleFavorite(user_id=current_user.id, article_id=article_id, is_favorited=True)
        db.add(favorite)
    else:
        favorite.is_favorited = True
        favorite.favorited_at = datetime.now(timezone.utc)
        favorite.unfavorited_at = None

    db.commit()
    return success({'article_id': article_id, 'favorite': True, 'idempotent': True})


@router.delete('/{article_id}/favorite')
def unfavorite_article(
    article_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == current_user.id,
            UserArticleFavorite.article_id == article_id,
        )
    )

    if favorite is None:
        favorite = UserArticleFavorite(
            user_id=current_user.id,
            article_id=article_id,
            is_favorited=False,
            unfavorited_at=datetime.now(timezone.utc),
        )
        db.add(favorite)
    else:
        favorite.is_favorited = False
        favorite.unfavorited_at = datetime.now(timezone.utc)

    db.commit()
    return success({'article_id': article_id, 'favorite': False, 'idempotent': True})
