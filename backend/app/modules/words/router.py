import json
import re
from functools import lru_cache
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends, HTTPException, Request as FastapiRequest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.response import success
from app.db.models import Word
from app.db.session import get_db

router = APIRouter()

WORD_LOOKUP_LIMIT_PER_MINUTE = 240
WORD_LOOKUP_WINDOW_SECONDS = 60
YOUDAO_LOOKUP_TIMEOUT_SECONDS = 5
_youdao_lookup_url = 'https://dict.youdao.com/jsonapi'
_offline_dictionary_path = Path(__file__).resolve().parents[2] / 'data' / 'offline_dictionary.json'
_word_lookup_rate_limiter = SlidingWindowRateLimiter(
    limit_per_window=WORD_LOOKUP_LIMIT_PER_MINUTE,
    window_seconds=WORD_LOOKUP_WINDOW_SECONDS,
    error_detail='word_lookup_rate_limited',
)


@lru_cache(maxsize=1)
def _offline_dictionary() -> dict[str, dict[str, str]]:
    if not _offline_dictionary_path.exists():
        return {}
    try:
        payload = json.loads(_offline_dictionary_path.read_text(encoding='utf-8-sig'))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(payload, dict):
        return {}
    return {
        key.strip().lower(): value
        for key, value in payload.items()
        if isinstance(key, str) and isinstance(value, dict)
    }



def _sync_word_lookup_rate_limit_config() -> None:
    _word_lookup_rate_limiter.limit_per_window = WORD_LOOKUP_LIMIT_PER_MINUTE
    _word_lookup_rate_limiter.window_seconds = WORD_LOOKUP_WINDOW_SECONDS



def reset_word_lookup_rate_limit_state_for_test() -> None:
    _sync_word_lookup_rate_limit_config()
    _word_lookup_rate_limiter.reset()



def _word_lookup_rate_limit_keys(request: FastapiRequest) -> list[str]:
    client_host = request.client.host if request.client else 'unknown'
    return [f'ip:{client_host}']



def _enforce_word_lookup_rate_limit(keys: list[str]) -> None:
    _sync_word_lookup_rate_limit_config()
    _word_lookup_rate_limiter.enforce(keys)



def _normalize_word(word: str) -> str:
    normalized = re.sub(r'^[^A-Za-z]+|[^A-Za-z]+$', '', word.strip().lower())
    if not normalized:
        raise HTTPException(status_code=400, detail='word must not be empty')
    return normalized



_IRREGULAR_WORD_FORMS = {
    'am': 'be',
    'is': 'be',
    'are': 'be',
    'was': 'be',
    'were': 'be',
    'been': 'be',
    'being': 'be',
    'has': 'have',
    'had': 'have',
    'does': 'do',
    'did': 'do',
    'done': 'do',
    'went': 'go',
    'gone': 'go',
    'came': 'come',
    'made': 'make',
    'took': 'take',
    'taken': 'take',
    'saw': 'see',
    'seen': 'see',
    'found': 'find',
    'thought': 'think',
    'said': 'say',
    'knew': 'know',
    'known': 'know',
    'gave': 'give',
    'given': 'give',
    'felt': 'feel',
    'left': 'leave',
    'brought': 'bring',
    'began': 'begin',
    'begun': 'begin',
    'kept': 'keep',
    'held': 'hold',
    'wrote': 'write',
    'written': 'write',
    'spoke': 'speak',
    'spoken': 'speak',
    'ran': 'run',
    'paid': 'pay',
    'sat': 'sit',
    'met': 'meet',
    'lost': 'lose',
    'understood': 'understand',
    'led': 'lead',
    'grew': 'grow',
    'grown': 'grow',
    'spent': 'spend',
    'won': 'win',
    'taught': 'teach',
    'heard': 'hear',
    'learnt': 'learn',
    'meant': 'mean',
    'sent': 'send',
    'built': 'build',
    'chose': 'choose',
    'chosen': 'choose',
    'wore': 'wear',
    'worn': 'wear',
    'drove': 'drive',
    'driven': 'drive',
}


def _candidate_words(normalized: str) -> list[str]:
    candidates: list[str] = [normalized]

    def add(candidate: str) -> None:
        if len(candidate) >= 2 and candidate not in candidates:
            candidates.append(candidate)

    irregular = _IRREGULAR_WORD_FORMS.get(normalized)
    if irregular is not None:
        add(irregular)

    if normalized.endswith('ies') and len(normalized) > 4:
        add(f'{normalized[:-3]}y')
    if normalized.endswith('es') and len(normalized) > 3:
        add(normalized[:-2])
    if normalized.endswith('s') and len(normalized) > 3:
        add(normalized[:-1])
    if normalized.endswith('ied') and len(normalized) > 4:
        add(f'{normalized[:-3]}y')
    if normalized.endswith('ed') and len(normalized) > 3:
        stem = normalized[:-2]
        add(stem)
        add(normalized[:-1])
        if len(stem) >= 2 and stem[-1] == stem[-2]:
            add(stem[:-1])
    if normalized.endswith('ing') and len(normalized) > 5:
        stem = normalized[:-3]
        add(stem)
        add(f'{stem}e')
        if len(stem) >= 2 and stem[-1] == stem[-2]:
            add(stem[:-1])
    if normalized.endswith('er') and len(normalized) > 4:
        stem = normalized[:-2]
        add(stem)
        if len(stem) >= 2 and stem[-1] == stem[-2]:
            add(stem[:-1])
    if normalized.endswith('est') and len(normalized) > 5:
        stem = normalized[:-3]
        add(stem)
        if len(stem) >= 2 and stem[-1] == stem[-2]:
            add(stem[:-1])

    return candidates



def _flatten_texts(value: object) -> list[str]:
    if isinstance(value, str):
        text = value.strip()
        return [text] if text else []
    if isinstance(value, list):
        items: list[str] = []
        for item in value:
            items.extend(_flatten_texts(item))
        return items
    if isinstance(value, dict):
        items: list[str] = []
        for item in value.values():
            items.extend(_flatten_texts(item))
        return items
    return []



def _dedupe_texts(values: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for value in values:
        cleaned = value.strip()
        if not cleaned or cleaned in seen:
            continue
        seen.add(cleaned)
        deduped.append(cleaned)
    return deduped



def _extract_youdao_payload(payload: dict, normalized: str) -> dict | None:
    candidates: list[dict] = []
    for section_name in ('ec', 'simple'):
        section = payload.get(section_name)
        if not isinstance(section, dict):
            continue
        words = section.get('word')
        if not isinstance(words, list):
            continue
        for item in words:
            if isinstance(item, dict):
                candidates.append(item)

    lemma = normalized
    phones: list[str] = []
    poses: list[str] = []
    meanings: list[str] = []

    for candidate in candidates:
        candidate_lemma = candidate.get('return-phrase') or candidate.get('word')
        if isinstance(candidate_lemma, str) and candidate_lemma.strip():
            lemma = candidate_lemma.strip().lower()

        for phone in (candidate.get('ukphone'), candidate.get('usphone'), candidate.get('phone')):
            if isinstance(phone, str) and phone.strip():
                phones.append(phone.strip())

        trs = candidate.get('trs')
        if isinstance(trs, list):
            for item in trs:
                if not isinstance(item, dict):
                    continue
                pos = item.get('pos')
                if isinstance(pos, str) and pos.strip():
                    poses.append(pos.strip())
                meanings.extend(_flatten_texts(item.get('tr')))

    basic = payload.get('basic')
    if isinstance(basic, dict):
        for phone in (basic.get('ukPhonetic'), basic.get('usPhonetic'), basic.get('phonetic')):
            if isinstance(phone, str) and phone.strip():
                phones.append(phone.strip())
        meanings.extend(_flatten_texts(basic.get('explains')))

    fanyi = payload.get('fanyi')
    if isinstance(fanyi, dict):
        meanings.extend(_flatten_texts(fanyi.get('tran')))

    deduped_meanings = _dedupe_texts(meanings)
    if not deduped_meanings:
        return None

    deduped_phones = _dedupe_texts(phones)
    deduped_poses = _dedupe_texts(poses)
    return {
        'lemma': lemma,
        'phonetic': deduped_phones[0] if deduped_phones else None,
        'pos': ' / '.join(deduped_poses[:3]) if deduped_poses else None,
        'meaning_cn': '；'.join(deduped_meanings[:4]),
    }



def _fetch_youdao_word(normalized: str) -> dict | None:
    query = urlencode({'q': normalized, 'jsonversion': '2', 'client': 'mobile'})
    request = Request(
        f'{_youdao_lookup_url}?{query}',
        headers={
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'application/json',
        },
    )
    try:
        with urlopen(request, timeout=YOUDAO_LOOKUP_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode('utf-8'))
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError):
        return None

    if not isinstance(payload, dict):
        return None
    return _extract_youdao_payload(payload, normalized)



def _offline_word_data(normalized: str) -> dict | None:
    dictionary = _offline_dictionary()
    for candidate in _candidate_words(normalized):
        item = dictionary.get(candidate)
        if item is None:
            continue
        meaning = item.get('meaning_cn')
        if not isinstance(meaning, str) or not meaning.strip():
            continue
        return {
            'lemma': candidate,
            'phonetic': item.get('phonetic'),
            'pos': item.get('pos'),
            'meaning_cn': meaning.strip(),
        }
    return None



def _persist_word(remote_data: dict, normalized: str, db: Session) -> Word:
    entry = Word(
        lemma=remote_data['lemma'],
        phonetic=remote_data.get('phonetic'),
        pos=remote_data.get('pos'),
        meaning_cn=remote_data['meaning_cn'],
    )
    db.add(entry)
    try:
        db.commit()
        db.refresh(entry)
        return entry
    except IntegrityError:
        db.rollback()
        for candidate in _candidate_words(normalized):
            existing = db.scalar(select(Word).where(func.lower(Word.lemma) == candidate))
            if existing is not None:
                return existing
        raise HTTPException(status_code=500, detail='word_cache_failed')



def _get_or_fetch_word(word: str, db: Session) -> tuple[Word, str]:
    normalized = _normalize_word(word)
    for candidate in _candidate_words(normalized):
        entry = db.scalar(select(Word).where(func.lower(Word.lemma) == candidate))
        if entry is not None:
            return entry, 'local'

    offline_data = _offline_word_data(normalized)
    if offline_data is not None:
        entry = _persist_word(offline_data, normalized, db)
        return entry, 'offline'

    remote_data = _fetch_youdao_word(normalized)
    if remote_data is None:
        raise HTTPException(status_code=404, detail='word not found')

    entry = _persist_word(remote_data, normalized, db)
    return entry, 'remote_cache'


@router.get('/{word}')
def lookup_word(word: str, request: FastapiRequest, db: Session = Depends(get_db)) -> dict:
    _enforce_word_lookup_rate_limit(_word_lookup_rate_limit_keys(request))

    entry, source = _get_or_fetch_word(word, db)
    return success(
        {
            'id': entry.id,
            'lemma': entry.lemma,
            'phonetic': entry.phonetic,
            'pos': entry.pos,
            'meaning_cn': entry.meaning_cn,
            'source': source,
        }
    )


@router.get('/{word}/pronunciation')
def word_pronunciation(word: str, request: FastapiRequest, db: Session = Depends(get_db)) -> dict:
    _enforce_word_lookup_rate_limit(_word_lookup_rate_limit_keys(request))

    entry, _ = _get_or_fetch_word(word, db)
    encoded = quote(entry.lemma)
    audio_url = f'https://dict.youdao.com/dictvoice?type=2&audio={encoded}'
    return success(
        {
            'lemma': entry.lemma,
            'audio_url': audio_url,
            'provider': 'youdao',
        }
    )

