from datetime import UTC, date, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.response import success
from app.db.models import Article, User, UserArticleFavorite, UserReadingProgress, UserVocabEntry, Word
from app.db.session import get_db

router = APIRouter()


def paginate(items: list[dict], page: int, size: int) -> dict:
    start = (page - 1) * size
    end = start + size
    sliced = items[start:end]
    total = len(items)
    return {
        'items': sliced,
        'page': page,
        'size': size,
        'total': total,
        'has_next': end < total,
    }


@router.get('/stats')
def me_stats(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    read_articles = db.scalar(
        select(func.count(func.distinct(UserReadingProgress.article_id))).where(UserReadingProgress.user_id == current_user.id)
    ) or 0
    study_days = db.scalar(
        select(func.count(func.distinct(func.date(UserReadingProgress.last_read_at)))).where(
            UserReadingProgress.user_id == current_user.id
        )
    ) or 0
    vocab_count = db.scalar(select(func.count(UserVocabEntry.id)).where(UserVocabEntry.user_id == current_user.id)) or 0

    completion_rate = 0.0
    total_progressed = read_articles
    if total_progressed > 0:
        completed = db.scalar(
            select(func.count(func.distinct(UserReadingProgress.article_id)))
            .join(Article, Article.id == UserReadingProgress.article_id)
            .where(UserReadingProgress.user_id == current_user.id, Article.is_completed.is_(True))
        ) or 0
        completion_rate = round(completed / total_progressed, 2)

    return success(
        {
            'read_articles': read_articles,
            'study_days': study_days,
            'vocab_count': vocab_count,
            'completion_rate': completion_rate,
        }
    )


@router.get('/learning-records')
def learning_records(
    days: int | None = Query(default=None, ge=1, le=3650),
    date_from: date | None = None,
    date_to: date | None = None,
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    query = (
        select(func.date(UserReadingProgress.last_read_at), func.count(UserReadingProgress.id))
        .where(UserReadingProgress.user_id == current_user.id)
    )

    if days is not None:
        cutoff = datetime.now(UTC).replace(tzinfo=None) - timedelta(days=days)
        query = query.where(UserReadingProgress.last_read_at >= cutoff)

    if date_from is not None:
        query = query.where(UserReadingProgress.last_read_at >= datetime.combine(date_from, datetime.min.time()))

    if date_to is not None:
        query = query.where(UserReadingProgress.last_read_at <= datetime.combine(date_to, datetime.max.time()))

    rows = db.execute(
        query.group_by(func.date(UserReadingProgress.last_read_at))
        .order_by(func.date(UserReadingProgress.last_read_at).desc())
        .limit(365)
    ).all()

    records = [
        {
            'date': str(date_value),
            'articles': count_value,
            'minutes': count_value * 8,
        }
        for date_value, count_value in rows
    ]
    return success(paginate(records, page=page, size=size))

@router.get('/vocab')
def me_vocab(
    source_article_id: int | None = None,
    mastered: bool | None = None,
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    query = (
        select(UserVocabEntry, Word)
        .join(Word, Word.id == UserVocabEntry.word_id)
        .where(UserVocabEntry.user_id == current_user.id)
        .order_by(UserVocabEntry.created_at.desc())
    )

    if source_article_id is not None:
        query = query.where(UserVocabEntry.source_article_id == source_article_id)
    if mastered is not None:
        query = query.where(UserVocabEntry.mastered == mastered)

    rows = db.execute(query).all()

    grouped: dict[int, dict] = {}
    for entry, word in rows:
        if word.id not in grouped:
            grouped[word.id] = {
                'word_id': word.id,
                'lemma': word.lemma,
                'source_count': 0,
                'latest_source_article_id': entry.source_article_id,
                'mastered': entry.mastered,
            }
        grouped[word.id]['source_count'] += 1
        if entry.source_article_id > grouped[word.id]['latest_source_article_id']:
            grouped[word.id]['latest_source_article_id'] = entry.source_article_id
        grouped[word.id]['mastered'] = grouped[word.id]['mastered'] and entry.mastered

    items = list(grouped.values())
    return success(paginate(items, page=page, size=size))


@router.get('/favorites')
def me_favorites(
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    rows = db.execute(
        select(UserArticleFavorite, Article)
        .join(Article, Article.id == UserArticleFavorite.article_id)
        .where(UserArticleFavorite.user_id == current_user.id, UserArticleFavorite.is_favorited.is_(True))
        .order_by(UserArticleFavorite.favorited_at.desc())
    ).all()

    items = [
        {
            'article_id': article.id,
            'title': article.title,
            'favorited_at': favorite.favorited_at.isoformat(),
        }
        for favorite, article in rows
    ]
    return success(paginate(items, page=page, size=size))