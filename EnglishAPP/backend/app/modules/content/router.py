from __future__ import annotations

import math
import wave
from datetime import UTC, datetime
from io import BytesIO

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.config import settings
from app.core.response import success
from app.db.models import Article, ArticleParagraph, User, UserArticleFavorite
from app.db.session import get_db

router = APIRouter()


def _serialize_article(article: Article) -> dict:
    return {
        'id': article.id,
        'slug': article.slug,
        'title': article.title,
        'stage': article.stage_tag,
        'level': article.level,
        'topic': article.topic,
        'summary': article.summary,
        'reading_minutes': article.reading_minutes,
        'is_completed': article.is_completed,
        'audio_status': article.audio_status,
        'source_url': article.source_url,
        'published_at': article.published_at.isoformat(),
    }


def _get_article_or_404(article_id: int, db: Session) -> Article:
    article = db.get(Article, article_id)
    if article is None or not article.is_published:
        raise HTTPException(status_code=404, detail='article not found')
    return article


def _build_mock_wav_bytes(article_id: int) -> bytes:
    sample_rate = 8000
    duration_seconds = 1
    frequency = 440 + (article_id % 5) * 30
    amplitude = 8000
    frame_count = sample_rate * duration_seconds
    buffer = BytesIO()
    with wave.open(buffer, 'wb') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        for index in range(frame_count):
            value = int(amplitude * math.sin(2 * math.pi * frequency * index / sample_rate))
            wav_file.writeframesraw(value.to_bytes(2, byteorder='little', signed=True))
    return buffer.getvalue()


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
    if level is not None:
        query = query.where(Article.level == level)
    if topic:
        query = query.where(Article.topic == topic)

    if sort == 'latest':
        query = query.order_by(Article.published_at.desc(), Article.id.desc())
    elif sort == 'hot':
        query = query.order_by(Article.reading_minutes.asc(), Article.level.asc(), Article.id.desc())
    else:
        query = query.order_by(Article.level.asc(), Article.published_at.desc(), Article.id.desc())

    total = db.scalar(select(func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * size
    articles = db.scalars(query.offset(offset).limit(size)).all()

    return success(
        {
            'items': [_serialize_article(article) for article in articles],
            'page': page,
            'size': size,
            'total': total,
            'has_next': offset + len(articles) < total,
        }
    )


@router.get('/{article_id}')
def get_article(article_id: int, db: Session = Depends(get_db)) -> dict:
    article = _get_article_or_404(article_id, db)
    paragraphs = db.scalars(
        select(ArticleParagraph)
        .where(ArticleParagraph.article_id == article_id)
        .order_by(ArticleParagraph.paragraph_index.asc(), ArticleParagraph.id.asc())
    ).all()

    return success(
        {
            **_serialize_article(article),
            'paragraphs': [{'index': paragraph.paragraph_index, 'text': paragraph.text} for paragraph in paragraphs],
        }
    )


@router.get('/{article_id}/audio')
def get_article_audio(article_id: int, db: Session = Depends(get_db)) -> dict:
    article = _get_article_or_404(article_id, db)
    paragraphs = db.scalars(
        select(ArticleParagraph)
        .where(ArticleParagraph.article_id == article_id)
        .order_by(ArticleParagraph.paragraph_index.asc(), ArticleParagraph.id.asc())
    ).all()

    paragraph_timestamps: list[dict] = []
    if article.audio_status == 'ready':
        current_start = 0.0
        for paragraph in paragraphs:
            duration = max(4.0, round(len(paragraph.text.split()) * 0.45, 2))
            paragraph_timestamps.append(
                {
                    'index': paragraph.paragraph_index,
                    'start': round(current_start, 2),
                    'end': round(current_start + duration, 2),
                }
            )
            current_start += duration

    return success(
        {
            'status': article.audio_status,
            'article_audio_url': article.article_audio_url if article.audio_status == 'ready' else None,
            'paragraph_timestamps': paragraph_timestamps,
            'retry_hint': '稍后重试' if article.audio_status == 'failed' else None,
        }
    )


@router.get('/{article_id}/audio/file')
def get_article_audio_file(article_id: int, db: Session = Depends(get_db)) -> Response:
    article = _get_article_or_404(article_id, db)
    if article.audio_status != 'ready':
        raise HTTPException(status_code=404, detail='audio not ready')
    return Response(content=_build_mock_wav_bytes(article_id), media_type='audio/wav')


@router.get('/{article_id}/favorite-status')
def favorite_status(
    article_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    _get_article_or_404(article_id, db)
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
    _get_article_or_404(article_id, db)
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
        favorite.favorited_at = datetime.now(UTC).replace(tzinfo=None)
        favorite.unfavorited_at = None

    db.commit()
    return success({'article_id': article_id, 'favorite': True, 'idempotent': True})


@router.delete('/{article_id}/favorite')
def unfavorite_article(
    article_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    _get_article_or_404(article_id, db)
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
            unfavorited_at=datetime.now(UTC).replace(tzinfo=None),
        )
        db.add(favorite)
    else:
        favorite.is_favorited = False
        favorite.unfavorited_at = datetime.now(UTC).replace(tzinfo=None)

    db.commit()
    return success({'article_id': article_id, 'favorite': False, 'idempotent': True})
