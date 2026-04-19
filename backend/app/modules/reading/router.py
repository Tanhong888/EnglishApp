from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.response import success
from app.db.article_content_sync import sync_reading_progress_completion
from app.db.models import Article, User, UserReadingProgress
from app.db.session import get_db

router = APIRouter()


class ReadingProgressRequest(BaseModel):
    article_id: int
    paragraph_index: int


@router.post('/progress')
def save_progress(
    payload: ReadingProgressRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    article = db.get(Article, payload.article_id)
    if article is None or not article.is_published:
        raise HTTPException(status_code=404, detail='article not found')

    progress = db.scalar(
        select(UserReadingProgress).where(
            and_(
                UserReadingProgress.user_id == current_user.id,
                UserReadingProgress.article_id == payload.article_id,
            )
        )
    )

    if progress is None:
        progress = UserReadingProgress(
            user_id=current_user.id,
            article_id=payload.article_id,
            paragraph_index=payload.paragraph_index,
            last_read_at=datetime.now(UTC).replace(tzinfo=None),
        )
        db.add(progress)
    else:
        progress.paragraph_index = payload.paragraph_index
        progress.last_read_at = datetime.now(UTC).replace(tzinfo=None)

    sync_reading_progress_completion(db, progress=progress, article=article, completed_at_fallback=progress.last_read_at)
    db.commit()
    db.refresh(progress)

    return success(
        {
            'article_id': payload.article_id,
            'paragraph_index': progress.paragraph_index,
            'progress_percent': progress.progress_percent,
            'completed': progress.completed_at is not None,
            'saved': True,
        }
    )


@router.get('/recent')
def recent_reading(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    rows = db.execute(
        select(UserReadingProgress, Article)
        .join(Article, Article.id == UserReadingProgress.article_id)
        .where(UserReadingProgress.user_id == current_user.id)
        .order_by(UserReadingProgress.last_read_at.desc(), UserReadingProgress.id.desc())
        .limit(10)
    ).all()

    return success(
        [
            {
                'article_id': article.id,
                'title': article.title,
                'stage': article.stage_tag,
                'level': article.level,
                'topic': article.topic,
                'reading_minutes': article.reading_minutes,
                'progress_percent': progress.progress_percent,
                'paragraph_index': progress.paragraph_index,
                'last_read_at': progress.last_read_at.isoformat(),
            }
            for progress, article in rows
        ]
    )
