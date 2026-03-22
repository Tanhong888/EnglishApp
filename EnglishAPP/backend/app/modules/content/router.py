from datetime import datetime, timezone
from functools import lru_cache
from io import BytesIO
import re
import wave

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.response import success
from app.db.models import Article, ArticleParagraph, User, UserArticleFavorite
from app.db.session import get_db

router = APIRouter()


_SAMPLE_RATE = 8000
_SAMPLE_WIDTH_BYTES = 2
_CHANNELS = 1


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



def _get_public_article_or_404(db: Session, article_id: int) -> Article:
    article = db.get(Article, article_id)
    if article is None or not article.is_published:
        raise HTTPException(status_code=404, detail='article not found')
    return article



def _word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z]+", text or ""))



def _build_paragraph_timestamps(article: Article, paragraphs: list[ArticleParagraph]) -> list[dict]:
    if not paragraphs:
        return []

    base_ms = 3000
    paragraph_count = len(paragraphs)
    target_total_ms = max(article.reading_minutes * 60 * 1000, paragraph_count * base_ms)

    weights = [max(_word_count(p.text), 1) for p in paragraphs]
    total_weight = sum(weights) or paragraph_count
    remaining_ms = max(target_total_ms - paragraph_count * base_ms, 0)

    durations = [base_ms + int(remaining_ms * weight / total_weight) for weight in weights]
    drift = target_total_ms - sum(durations)
    durations[-1] += drift

    cursor_ms = 0
    timestamps: list[dict] = []
    for paragraph, duration_ms in zip(paragraphs, durations):
        start_ms = cursor_ms
        end_ms = max(start_ms + 1000, start_ms + duration_ms)
        cursor_ms = end_ms

        timestamps.append(
            {
                'index': paragraph.paragraph_index,
                'start': round(start_ms / 1000, 3),
                'end': round(end_ms / 1000, 3),
            }
        )

    return timestamps


@lru_cache(maxsize=16)
def _build_silent_wav(seconds: int) -> bytes:
    clamped_seconds = max(1, min(seconds, 15 * 60))
    frame_count = _SAMPLE_RATE * clamped_seconds
    silence = b'\x00' * frame_count * _SAMPLE_WIDTH_BYTES * _CHANNELS
    buffer = BytesIO()
    with wave.open(buffer, 'wb') as wav_file:
        wav_file.setnchannels(_CHANNELS)
        wav_file.setsampwidth(_SAMPLE_WIDTH_BYTES)
        wav_file.setframerate(_SAMPLE_RATE)
        wav_file.writeframes(silence)
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
    article = _get_public_article_or_404(db, article_id)

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


@router.get('/{article_id}/audio/file')
def get_article_audio_file(article_id: int, db: Session = Depends(get_db)) -> Response:
    article = _get_public_article_or_404(db, article_id)
    if article.audio_status != 'ready' or not article.article_audio_url:
        raise HTTPException(status_code=404, detail='article audio not ready')

    wav_bytes = _build_silent_wav(article.reading_minutes * 60)
    return Response(
        content=wav_bytes,
        media_type='audio/wav',
        headers={'Cache-Control': 'public, max-age=3600'},
    )


@router.get('/{article_id}/audio')
def get_article_audio(article_id: int, db: Session = Depends(get_db)) -> dict:
    article = _get_public_article_or_404(db, article_id)

    paragraph_timestamps: list[dict] = []
    if article.audio_status == 'ready':
        paragraphs = db.scalars(
            select(ArticleParagraph)
            .where(ArticleParagraph.article_id == article_id)
            .order_by(ArticleParagraph.paragraph_index.asc())
        ).all()
        paragraph_timestamps = _build_paragraph_timestamps(article, paragraphs)

    data = {
        'status': article.audio_status,
        'article_audio_url': article.article_audio_url if article.audio_status == 'ready' else None,
        'paragraph_timestamps': paragraph_timestamps,
        'retry_hint': '稍后重试' if article.audio_status == 'failed' else None,
    }
    return success(data)


@router.get('/{article_id}/favorite-status')
def favorite_status(
    article_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    article = _get_public_article_or_404(db, article_id)

    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == current_user.id,
            UserArticleFavorite.article_id == article.id,
        )
    )

    return success({'article_id': article_id, 'favorite': favorite.is_favorited if favorite is not None else False})


@router.post('/{article_id}/favorite')
def favorite_article(
    article_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    article = _get_public_article_or_404(db, article_id)

    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == current_user.id,
            UserArticleFavorite.article_id == article.id,
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
    article = _get_public_article_or_404(db, article_id)

    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == current_user.id,
            UserArticleFavorite.article_id == article.id,
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
