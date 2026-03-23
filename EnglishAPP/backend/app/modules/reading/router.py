from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.response import success
from app.db.article_content_sync import compute_progress_fields
from app.db.models import Article, ArticleParagraph, User, UserReadingProgress
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
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    paragraph_count = db.scalar(
        select(func.count(ArticleParagraph.id)).where(ArticleParagraph.article_id == payload.article_id)
    ) or 0
    normalized_index, progress_percent, completed = compute_progress_fields(payload.paragraph_index, paragraph_count)
    now = datetime.now(timezone.utc)

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
            paragraph_index=normalized_index,
            progress_percent=progress_percent,
            completed_at=now if completed else None,
            last_read_at=now,
        )
        db.add(progress)
    else:
        progress.paragraph_index = normalized_index
        progress.progress_percent = progress_percent
        progress.completed_at = now if completed else None
        progress.last_read_at = now

    db.commit()

    return success(
        {
            'article_id': payload.article_id,
            'paragraph_index': normalized_index,
            'progress_percent': progress_percent,
            'completed': completed,
            'saved': True,
        }
    )


@router.get('/recent')
def recent_reading(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    rows = db.execute(
        select(UserReadingProgress, Article)
        .join(Article, Article.id == UserReadingProgress.article_id)
        .where(UserReadingProgress.user_id == current_user.id)
        .order_by(UserReadingProgress.last_read_at.desc())
        .limit(10)
    ).all()

    data = [
        {
            'article_id': article.id,
            'title': article.title,
            'last_read_at': progress.last_read_at.isoformat(),
        }
        for progress, article in rows
    ]

    return success(data)
