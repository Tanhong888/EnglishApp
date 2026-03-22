from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.response import success
from app.db.models import Word
from app.db.session import get_db

router = APIRouter()

WORD_LOOKUP_LIMIT_PER_MINUTE = 240
WORD_LOOKUP_WINDOW_SECONDS = 60
_word_lookup_rate_limiter = SlidingWindowRateLimiter(
    limit_per_window=WORD_LOOKUP_LIMIT_PER_MINUTE,
    window_seconds=WORD_LOOKUP_WINDOW_SECONDS,
    error_detail='word_lookup_rate_limited',
)


def _sync_word_lookup_rate_limit_config() -> None:
    _word_lookup_rate_limiter.limit_per_window = WORD_LOOKUP_LIMIT_PER_MINUTE
    _word_lookup_rate_limiter.window_seconds = WORD_LOOKUP_WINDOW_SECONDS


def reset_word_lookup_rate_limit_state_for_test() -> None:
    _sync_word_lookup_rate_limit_config()
    _word_lookup_rate_limiter.reset()


def _word_lookup_rate_limit_keys(request: Request) -> list[str]:
    client_host = request.client.host if request.client else 'unknown'
    return [f'ip:{client_host}']


def _enforce_word_lookup_rate_limit(keys: list[str]) -> None:
    _sync_word_lookup_rate_limit_config()
    _word_lookup_rate_limiter.enforce(keys)


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
