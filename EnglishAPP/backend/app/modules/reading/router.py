from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.response import success
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
    if article is None:
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
            last_read_at=datetime.now(timezone.utc),
        )
        db.add(progress)
    else:
        progress.paragraph_index = payload.paragraph_index
        progress.last_read_at = datetime.now(timezone.utc)

    db.commit()

    return success(
        {
            'article_id': payload.article_id,
            'paragraph_index': payload.paragraph_index,
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
