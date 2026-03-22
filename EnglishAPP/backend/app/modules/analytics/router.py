import json
from collections import Counter
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.response import success
from app.db.models import AnalyticsEvent, User
from app.db.session import get_db

router = APIRouter()

ANALYTICS_TRACK_LIMIT_PER_MINUTE = 120
ANALYTICS_TRACK_WINDOW_SECONDS = 60
_track_event_rate_limiter = SlidingWindowRateLimiter(
    limit_per_window=ANALYTICS_TRACK_LIMIT_PER_MINUTE,
    window_seconds=ANALYTICS_TRACK_WINDOW_SECONDS,
    error_detail='analytics_track_rate_limited',
)


class TrackEventRequest(BaseModel):
    event_name: str = Field(min_length=1, max_length=64)
    user_id: int | None = Field(default=None, ge=1)
    article_id: int | None = Field(default=None, ge=1)
    word: str | None = Field(default=None, min_length=1, max_length=128)
    context: dict[str, str | int | float | bool | None] | None = None


def _sync_track_rate_limit_config() -> None:
    _track_event_rate_limiter.limit_per_window = ANALYTICS_TRACK_LIMIT_PER_MINUTE
    _track_event_rate_limiter.window_seconds = ANALYTICS_TRACK_WINDOW_SECONDS


def reset_analytics_rate_limit_state_for_test() -> None:
    _sync_track_rate_limit_config()
    _track_event_rate_limiter.reset()


def _track_rate_limit_keys(payload: TrackEventRequest, request: Request) -> list[str]:
    keys: list[str] = []
    if payload.user_id is not None:
        keys.append(f'user:{payload.user_id}')

    client_host = request.client.host if request.client and request.client.host else 'unknown'
    keys.append(f'ip:{client_host}')
    return keys


def _enforce_track_event_rate_limit(keys: list[str], now: datetime | None = None) -> None:
    _sync_track_rate_limit_config()
    _track_event_rate_limiter.enforce(keys, now=now)


def _build_summary_payload(events: list[AnalyticsEvent], days: int, since: datetime) -> dict:
    event_counts = Counter(item.event_name for item in events)
    active_users = {item.user_id for item in events if item.user_id is not None}

    timeline_counter: dict[str, int] = {}
    for item in events:
        day = item.created_at.date().isoformat()
        timeline_counter[day] = timeline_counter.get(day, 0) + 1

    top_word_counter = Counter(item.word for item in events if item.event_name == 'word_tap' and item.word)

    return {
        'window_days': days,
        'since': since.isoformat(),
        'event_total': len(events),
        'dau': len(active_users),
        'event_counts': dict(event_counts),
        'timeline': [{'date': day, 'events': timeline_counter[day]} for day in sorted(timeline_counter.keys())],
        'top_words': [
            {'word': word, 'count': count}
            for word, count in top_word_counter.most_common(10)
        ],
    }


def _query_events(db: Session, *, days: int, user_id: int | None = None) -> tuple[datetime, list[AnalyticsEvent]]:
    since = datetime.now() - timedelta(days=days)

    query = select(AnalyticsEvent).where(AnalyticsEvent.created_at >= since)
    if user_id is not None:
        query = query.where(AnalyticsEvent.user_id == user_id)

    events = db.scalars(query.order_by(desc(AnalyticsEvent.created_at))).all()
    return since, events


@router.post('/events')
def track_event(payload: TrackEventRequest, request: Request, db: Session = Depends(get_db)) -> dict:
    keys = _track_rate_limit_keys(payload, request)
    _enforce_track_event_rate_limit(keys)

    word = payload.word.strip().lower() if payload.word else None
    context_json = json.dumps(payload.context, ensure_ascii=False) if payload.context is not None else None

    event = AnalyticsEvent(
        user_id=payload.user_id,
        event_name=payload.event_name,
        article_id=payload.article_id,
        word=word,
        context_json=context_json,
    )
    db.add(event)
    db.commit()
    db.refresh(event)

    return success(
        {
            'event_id': event.id,
            'event_name': event.event_name,
            'created_at': event.created_at.isoformat(),
        }
    )


@router.get('/events')
def list_events(
    limit: int = Query(default=20, ge=1, le=100),
    event_name: str | None = None,
    db: Session = Depends(get_db),
) -> dict:
    query = select(AnalyticsEvent)
    if event_name:
        query = query.where(AnalyticsEvent.event_name == event_name)

    events = db.scalars(query.order_by(desc(AnalyticsEvent.created_at)).limit(limit)).all()
    items = [
        {
            'event_id': item.id,
            'event_name': item.event_name,
            'user_id': item.user_id,
            'article_id': item.article_id,
            'word': item.word,
            'context_json': item.context_json,
            'created_at': item.created_at.isoformat(),
        }
        for item in events
    ]
    return success({'items': items, 'limit': limit})


@router.get('/dashboard/summary')
def dashboard_summary(
    days: int = Query(default=7, ge=1, le=90),
    db: Session = Depends(get_db),
) -> dict:
    since, events = _query_events(db, days=days)
    return success(_build_summary_payload(events, days, since))


@router.get('/dashboard/me-summary')
def dashboard_me_summary(
    days: int = Query(default=7, ge=1, le=90),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    since, events = _query_events(db, days=days, user_id=current_user.id)
    return success(_build_summary_payload(events, days, since))
