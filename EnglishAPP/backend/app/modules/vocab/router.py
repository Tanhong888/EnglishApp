from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.response import success
from app.db.models import Article, User, UserVocabEntry, Word
from app.db.session import get_db

router = APIRouter()


class AddVocabRequest(BaseModel):
    word_id: int
    source_article_id: int


class UpdateVocabRequest(BaseModel):
    mastered: bool


@router.post('')
def add_vocab(
    payload: AddVocabRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    word = db.get(Word, payload.word_id)
    if word is None:
        raise HTTPException(status_code=404, detail='word not found')

    article = db.get(Article, payload.source_article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='source article not found')

    entry = db.scalar(
        select(UserVocabEntry).where(
            UserVocabEntry.user_id == current_user.id,
            UserVocabEntry.word_id == payload.word_id,
            UserVocabEntry.source_article_id == payload.source_article_id,
        )
    )

    created = False
    if entry is None:
        created = True
        entry = UserVocabEntry(
            user_id=current_user.id,
            word_id=payload.word_id,
            source_article_id=payload.source_article_id,
            mastered=False,
        )
        db.add(entry)
        db.commit()
        db.refresh(entry)

    return success(
        {
            'entry_id': entry.id,
            'word_id': entry.word_id,
            'source_article_id': entry.source_article_id,
            'dedup_key': f"{current_user.id}:{entry.word_id}:{entry.source_article_id}",
            'created': created,
        }
    )


@router.patch('/{entry_id}')
def update_vocab(
    entry_id: int,
    payload: UpdateVocabRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    entry = db.scalar(select(UserVocabEntry).where(UserVocabEntry.id == entry_id, UserVocabEntry.user_id == current_user.id))
    if entry is None:
        raise HTTPException(status_code=404, detail='vocab entry not found')

    entry.mastered = payload.mastered
    entry.updated_at = datetime.now(timezone.utc)
    db.commit()

    return success({'entry_id': entry_id, 'mastered': payload.mastered})
