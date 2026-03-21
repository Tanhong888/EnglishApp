from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.response import success
from app.db.models import Word
from app.db.session import get_db

router = APIRouter()


@router.get('/{word}')
def lookup_word(word: str, db: Session = Depends(get_db)) -> dict:
    normalized = word.strip().lower()
    if not normalized:
        raise HTTPException(status_code=400, detail='word must not be empty')

    entry = db.scalar(select(Word).where(func.lower(Word.lemma) == normalized))
    if entry is None:
        raise HTTPException(status_code=404, detail='word not found')

    return success(
        {
            'id': entry.id,
            'lemma': entry.lemma,
            'phonetic': entry.phonetic,
            'pos': entry.pos,
            'meaning_cn': entry.meaning_cn,
        }
    )
