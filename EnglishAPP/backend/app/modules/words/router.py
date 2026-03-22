from collections import deque
from datetime import datetime, timedelta, timezone
from threading import Lock
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.response import success
from app.db.models import Word
from app.db.session import get_db

router = APIRouter()

WORD_LOOKUP_LIMIT_PER_MINUTE = 240
WORD_LOOKUP_WINDOW_SECONDS = 60
_word_lookup_rate_limit_lock = Lock()
_word_lookup_timestamps: dict[str, deque[datetime]] = {}


def reset_word_lookup_rate_limit_state_for_test() -> None:
    with _word_lookup_rate_limit_lock:
        _word_lookup_timestamps.clear()


def _word_lookup_rate_limit_keys(request: Request) -> list[str]:
    client_host = request.client.host if request.client else 'unknown'
    return [f'ip:{client_host}']


def _enforce_word_lookup_rate_limit(keys: list[str], now: datetime | None = None) -> None:
    current_time = now or datetime.now(timezone.utc)
    window_start = current_time - timedelta(seconds=WORD_LOOKUP_WINDOW_SECONDS)

    with _word_lookup_rate_limit_lock:
        for key in keys:
            timestamps = _word_lookup_timestamps.setdefault(key, deque())
            while timestamps and timestamps[0] <= window_start:
                timestamps.popleft()

            if len(timestamps) >= WORD_LOOKUP_LIMIT_PER_MINUTE:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail='word_lookup_rate_limited',
                )

        for key in keys:
            _word_lookup_timestamps.setdefault(key, deque()).append(current_time)


def _get_word_or_404(word: str, db: Session) -> Word:
    normalized = word.strip().lower()
    if not normalized:
        raise HTTPException(status_code=400, detail='word must not be empty')

    entry = db.scalar(select(Word).where(func.lower(Word.lemma) == normalized))
    if entry is None:
        raise HTTPException(status_code=404, detail='word not found')

    return entry


@router.get('/{word}')
def lookup_word(word: str, request: Request, db: Session = Depends(get_db)) -> dict:
    _enforce_word_lookup_rate_limit(_word_lookup_rate_limit_keys(request))

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
def word_pronunciation(word: str, request: Request, db: Session = Depends(get_db)) -> dict:
    _enforce_word_lookup_rate_limit(_word_lookup_rate_limit_keys(request))

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
