from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.core.constants import DEMO_USER_ID
from app.core.response import success
from app.db.models import Article, UserReadingProgress
from app.db.session import get_db

router = APIRouter()


class ReadingProgressRequest(BaseModel):
    article_id: int
    paragraph_index: int


@router.post("/progress")
def save_progress(payload: ReadingProgressRequest, db: Session = Depends(get_db)) -> dict:
    progress = db.scalar(
        select(UserReadingProgress).where(
            and_(
                UserReadingProgress.user_id == DEMO_USER_ID,
                UserReadingProgress.article_id == payload.article_id,
            )
        )
    )

    if progress is None:
        progress = UserReadingProgress(
            user_id=DEMO_USER_ID,
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
            "article_id": payload.article_id,
            "paragraph_index": payload.paragraph_index,
            "saved": True,
        }
    )


@router.get("/recent")
def recent_reading(db: Session = Depends(get_db)) -> dict:
    rows = db.execute(
        select(UserReadingProgress, Article)
        .join(Article, Article.id == UserReadingProgress.article_id)
        .where(UserReadingProgress.user_id == DEMO_USER_ID)
        .order_by(UserReadingProgress.last_read_at.desc())
        .limit(10)
    ).all()

    data = [
        {
            "article_id": article.id,
            "title": article.title,
            "last_read_at": progress.last_read_at.isoformat(),
        }
        for progress, article in rows
    ]

    return success(data)

