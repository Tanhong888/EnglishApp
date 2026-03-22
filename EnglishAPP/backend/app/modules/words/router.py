from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.response import success
from app.db.models import Word
from app.db.session import get_db

router = APIRouter()


def _get_word_or_404(word: str, db: Session) -> Word:
    normalized = word.strip().lower()
    if not normalized:
        raise HTTPException(status_code=400, detail='word must not be empty')

    entry = db.scalar(select(Word).where(func.lower(Word.lemma) == normalized))
    if entry is None:
        raise HTTPException(status_code=404, detail='word not found')

    return entry


@router.get('/{word}')
def lookup_word(word: str, db: Session = Depends(get_db)) -> dict:
    entry = _get_word_or_404(word, db)
    return success(
        {
            'id': entry.id,
            'lemma': entry.lemma,
            'phonetic': entry.phonetic,
            'pos': entry.pos,
            'meaning_cn': entry.meaning_cn,
        }
    )


@router.get('/{word}/pronunciation')
def word_pronunciation(word: str, db: Session = Depends(get_db)) -> dict:
    entry = _get_word_or_404(word, db)
    encoded = quote(entry.lemma)
    audio_url = f'https://dict.youdao.com/dictvoice?type=2&audio={encoded}'
    return success(
        {
            'lemma': entry.lemma,
            'audio_url': audio_url,
            'provider': 'youdao',
        }
    )
