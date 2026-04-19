from datetime import UTC, date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
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
    vocab_count = db.scalar(select(func.count(UserVocabEntry.id)).where(UserVocabEntry.user_id == current_user.id)) or 0
    study_days = db.scalar(
        select(func.count(func.distinct(func.date(UserReadingProgress.last_read_at)))).where(
            UserReadingProgress.user_id == current_user.id
        )
    ) or 0
    completed_articles = db.scalar(
        select(func.count(func.distinct(UserReadingProgress.article_id))).where(
            UserReadingProgress.user_id == current_user.id,
            UserReadingProgress.completed_at.is_not(None),
        )
    ) or 0
    completion_rate = round(completed_articles / read_articles, 2) if read_articles else 0.0

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
    days: int | None = Query(default=None, ge=1, le=365),
    date_from: date | None = None,
    date_to: date | None = None,
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    query = select(func.date(UserReadingProgress.last_read_at), func.count(UserReadingProgress.id)).where(
        UserReadingProgress.user_id == current_user.id
    )

    if days is not None:
        start_dt = datetime.now(UTC).replace(tzinfo=None) - timedelta(days=days)
        query = query.where(UserReadingProgress.last_read_at >= start_dt)
    if date_from is not None:
        query = query.where(func.date(UserReadingProgress.last_read_at) >= date_from.isoformat())
    if date_to is not None:
        query = query.where(func.date(UserReadingProgress.last_read_at) <= date_to.isoformat())

    rows = db.execute(
        query.group_by(func.date(UserReadingProgress.last_read_at)).order_by(func.date(UserReadingProgress.last_read_at).desc())
    ).all()

    items = [{'date': str(day), 'articles': count_value, 'minutes': count_value * 8} for day, count_value in rows]
    return success(paginate(items, page=page, size=size))


@router.get('/vocab')
def me_vocab(
    q: str | None = Query(default=None, min_length=1, max_length=50),
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
        .order_by(UserVocabEntry.created_at.desc(), UserVocabEntry.id.desc())
    )

    keyword = q.strip() if q else None
    if keyword:
        fuzzy = f'%{keyword}%'
        query = query.where(
            or_(
                Word.lemma.ilike(fuzzy),
                Word.meaning_cn.ilike(fuzzy),
                Word.pos.ilike(fuzzy),
            )
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
                'latest_entry_id': entry.id,
                'lemma': word.lemma,
                'phonetic': word.phonetic,
                'pos': word.pos,
                'meaning_cn': word.meaning_cn,
                'source_count': 0,
                'latest_source_article_id': entry.source_article_id,
                'mastered': True,
            }
        grouped[word.id]['source_count'] += 1
        grouped[word.id]['mastered'] = grouped[word.id]['mastered'] and entry.mastered

    items = list(grouped.values())
    return success(paginate(items, page=page, size=size))


@router.get('/vocab/entries/{entry_id}')
def me_vocab_entry_detail(
    entry_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    target = db.execute(
        select(UserVocabEntry, Word)
        .join(Word, Word.id == UserVocabEntry.word_id)
        .where(UserVocabEntry.id == entry_id, UserVocabEntry.user_id == current_user.id)
    ).first()
    if target is None:
        raise HTTPException(status_code=404, detail='vocab entry not found')

    entry, word = target
    source_rows = db.execute(
        select(UserVocabEntry, Article)
        .join(Article, Article.id == UserVocabEntry.source_article_id)
        .where(UserVocabEntry.user_id == current_user.id, UserVocabEntry.word_id == word.id)
        .order_by(UserVocabEntry.created_at.desc(), UserVocabEntry.id.desc())
    ).all()

    sources = [
        {
            'entry_id': source_entry.id,
            'source_article_id': article.id,
            'source_article_title': article.title,
            'mastered': source_entry.mastered,
            'created_at': source_entry.created_at.isoformat(),
            'updated_at': source_entry.updated_at.isoformat(),
        }
        for source_entry, article in source_rows
    ]

    return success(
        {
            'entry_id': entry.id,
            'word_id': word.id,
            'lemma': word.lemma,
            'phonetic': word.phonetic,
            'pos': word.pos,
            'meaning_cn': word.meaning_cn,
            'source_count': len(sources),
            'mastered': all(item['mastered'] for item in sources) if sources else False,
            'sources': sources,
            'last_reviewed_at': datetime.now(UTC).replace(tzinfo=None).isoformat(),
        }
    )


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
        .order_by(UserArticleFavorite.favorited_at.desc(), UserArticleFavorite.id.desc())
    ).all()

    items = [
        {
            'article_id': article.id,
            'title': article.title,
            'summary': article.summary,
            'reading_minutes': article.reading_minutes,
            'favorited_at': favorite.favorited_at.isoformat(),
        }
        for favorite, article in rows
    ]
    return success(paginate(items, page=page, size=size))
