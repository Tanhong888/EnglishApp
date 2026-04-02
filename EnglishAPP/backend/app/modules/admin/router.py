from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from app.core.auth import require_admin_user
from app.core.config import settings
from app.core.response import success
from app.db.article_content_sync import ensure_article_slug, ensure_article_source, summarize_paragraphs, sync_article_content_snapshot
from app.db.models import Article, ArticleAudioTask, ArticleParagraph, ArticleSource, Quiz, QuizOption, QuizQuestion, SentenceAnalysis, User, Word
from app.db.session import get_db

router = APIRouter()


class AdminArticleCreateRequest(BaseModel):
    title: str
    stage_tag: str
    level: int = Field(ge=1, le=4)
    topic: str
    reading_minutes: int = Field(ge=1)
    is_published: bool = False
    paragraphs: list[str] = Field(min_length=1)
    summary: str | None = None
    source_url: str | None = None


class AdminArticleUpdateRequest(BaseModel):
    title: str | None = None
    stage_tag: str | None = None
    level: int | None = Field(default=None, ge=1, le=4)
    topic: str | None = None
    reading_minutes: int | None = Field(default=None, ge=1)
    paragraphs: list[str] | None = None
    summary: str | None = None
    source_url: str | None = None


class PublishRequest(BaseModel):
    is_published: bool


class SentenceAnalysisItemRequest(BaseModel):
    sentence_index: int = Field(ge=1)
    sentence: str
    translation: str | None = None
    structure: str | None = None


class SentenceAnalysisReplaceRequest(BaseModel):
    items: list[SentenceAnalysisItemRequest]


class QuizQuestionRequest(BaseModel):
    question_index: int = Field(ge=1)
    stem: str
    options: list[str] = Field(min_length=2)
    correct_option_index: int = Field(ge=1)


class QuizReplaceRequest(BaseModel):
    questions: list[QuizQuestionRequest]


class AdminWordCreateRequest(BaseModel):
    lemma: str
    phonetic: str | None = None
    pos: str | None = None
    meaning_cn: str


class AdminWordUpdateRequest(BaseModel):
    phonetic: str | None = None
    pos: str | None = None
    meaning_cn: str | None = None


def _article_audio_url(article_id: int) -> str:
    return f'{settings.public_base_url}{settings.api_prefix}/articles/{article_id}/audio/file'


def _paragraphs_for_article(db: Session, article_id: int) -> list[ArticleParagraph]:
    return db.scalars(
        select(ArticleParagraph)
        .where(ArticleParagraph.article_id == article_id)
        .order_by(ArticleParagraph.paragraph_index.asc(), ArticleParagraph.id.asc())
    ).all()


def _replace_paragraphs(db: Session, article: Article, paragraphs: list[str]) -> None:
    existing = _paragraphs_for_article(db, article.id)
    by_index = {item.paragraph_index: item for item in existing}
    desired = set()

    for index, text in enumerate(paragraphs, start=1):
        desired.add(index)
        paragraph = by_index.get(index)
        if paragraph is None:
            db.add(ArticleParagraph(article_id=article.id, paragraph_index=index, text=text))
        else:
            paragraph.text = text

    for paragraph in existing:
        if paragraph.paragraph_index not in desired:
            db.delete(paragraph)

    db.flush()


def _serialize_source(db: Session, article: Article) -> dict[str, str | None]:
    source = db.scalar(
        select(ArticleSource)
        .where(ArticleSource.article_id == article.id)
        .order_by(ArticleSource.id.desc())
        .limit(1)
    )
    if source is None:
        return {
            'type': None,
            'name': None,
            'url': article.source_url,
        }
    return {
        'type': source.source_type,
        'name': source.source_name,
        'url': source.source_url or article.source_url,
    }


def _serialize_admin_article(db: Session, article: Article) -> dict:
    paragraph_count = db.scalar(select(func.count(ArticleParagraph.id)).where(ArticleParagraph.article_id == article.id)) or 0
    source = _serialize_source(db, article)
    return {
        'id': article.id,
        'title': article.title,
        'slug': article.slug,
        'stage': article.stage_tag,
        'level': article.level,
        'topic': article.topic,
        'summary': article.summary,
        'status': article.status,
        'source_url': article.source_url,
        'source': source,
        'reading_minutes': article.reading_minutes,
        'is_published': article.is_published,
        'paragraph_count': paragraph_count,
        'audio_status': article.audio_status,
        'published_at': article.published_at.isoformat(),
        'created_at': article.created_at.isoformat(),
        'updated_at': article.updated_at.isoformat(),
    }


def _sync_article_snapshot_and_source(db: Session, article: Article, paragraphs: list[str], source_type: str) -> None:
    ensure_article_slug(db, article)
    if article.summary is None:
        article.summary = summarize_paragraphs(paragraphs)
    ensure_article_source(
        db,
        article=article,
        source_type=source_type,
        source_name='admin_console' if source_type == 'manual' else None,
        source_url=article.source_url,
    )
    sync_article_content_snapshot(db, article=article, paragraphs=paragraphs)


def _enqueue_audio_task(db: Session, article: Article) -> ArticleAudioTask:
    task = db.scalar(select(ArticleAudioTask).where(ArticleAudioTask.article_id == article.id))
    if task is None:
        task = ArticleAudioTask(article_id=article.id)
        db.add(task)
        db.flush()

    task.status = 'pending'
    task.attempt_count = 0
    task.max_attempts = settings.tts_max_attempts
    task.next_retry_at = None
    task.processing_started_at = None
    task.completed_at = None
    task.last_error = None
    article.audio_status = 'pending'
    article.article_audio_url = None
    return task


def _progress_audio_task(db: Session, article: Article, task: ArticleAudioTask) -> ArticleAudioTask:
    if task.status in {'ready', 'failed'}:
        return task

    task.attempt_count += 1
    task.processing_started_at = datetime.now(UTC).replace(tzinfo=None)

    if settings.tts_mock_fail_keyword in article.title:
        if task.attempt_count >= task.max_attempts:
            task.status = 'failed'
            task.completed_at = datetime.now(UTC).replace(tzinfo=None)
            task.last_error = 'mock_tts_generation_failed'
            article.audio_status = 'failed'
            article.article_audio_url = None
        else:
            task.status = 'pending'
            task.next_retry_at = datetime.now(UTC).replace(tzinfo=None)
            article.audio_status = 'pending'
        db.commit()
        db.refresh(task)
        return task

    task.status = 'ready'
    task.completed_at = datetime.now(UTC).replace(tzinfo=None)
    article.audio_status = 'ready'
    article.article_audio_url = _article_audio_url(article.id)
    db.commit()
    db.refresh(task)
    return task


@router.get('/articles')
def list_admin_articles(
    _: User = Depends(require_admin_user),
    q: str | None = Query(default=None, min_length=1, max_length=100),
    published: bool | None = None,
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    db: Session = Depends(get_db),
) -> dict:
    query = select(Article).order_by(Article.created_at.desc(), Article.id.desc())
    if published is not None:
        query = query.where(Article.is_published == published)
    if q:
        fuzzy = f'%{q.strip()}%'
        query = query.where(or_(Article.title.ilike(fuzzy), Article.summary.ilike(fuzzy), Article.source_url.ilike(fuzzy)))

    articles = db.scalars(query).all()
    total = len(articles)
    start = (page - 1) * size
    items = articles[start:start + size]
    return success(
        {
            'items': [_serialize_admin_article(db, article) for article in items],
            'page': page,
            'size': size,
            'total': total,
            'has_next': start + len(items) < total,
        }
    )


@router.get('/articles/{article_id}')
def admin_article_detail(article_id: int, _: User = Depends(require_admin_user), db: Session = Depends(get_db)) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')
    data = _serialize_admin_article(db, article)
    data['paragraphs'] = [{'index': p.paragraph_index, 'text': p.text} for p in _paragraphs_for_article(db, article_id)]
    return success(data)


@router.post('/articles')
def create_admin_article(payload: AdminArticleCreateRequest, _: User = Depends(require_admin_user), db: Session = Depends(get_db)) -> dict:
    article = Article(
        title=payload.title,
        stage_tag=payload.stage_tag,
        level=payload.level,
        topic=payload.topic,
        summary=payload.summary,
        reading_minutes=payload.reading_minutes,
        status='published' if payload.is_published else 'draft',
        source_url=payload.source_url,
        is_published=payload.is_published,
        audio_status='pending',
    )
    db.add(article)
    db.flush()
    _replace_paragraphs(db, article, payload.paragraphs)
    if article.summary is None:
        article.summary = summarize_paragraphs(payload.paragraphs)
    _sync_article_snapshot_and_source(db, article, payload.paragraphs, source_type='manual')
    if payload.is_published:
        _enqueue_audio_task(db, article)
    db.commit()
    db.refresh(article)
    return success(_serialize_admin_article(db, article))


@router.patch('/articles/{article_id}')
def update_admin_article(
    article_id: int,
    payload: AdminArticleUpdateRequest,
    _: User = Depends(require_admin_user),
    db: Session = Depends(get_db),
) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    update_data = payload.model_dump(exclude_unset=True)
    paragraphs = update_data.pop('paragraphs', None)
    for key, value in update_data.items():
        setattr(article, key, value)

    if paragraphs is not None:
        _replace_paragraphs(db, article, paragraphs)
    paragraph_texts = [item.text for item in _paragraphs_for_article(db, article.id)]
    if payload.summary is None and paragraphs is not None:
        article.summary = summarize_paragraphs(paragraph_texts)
    _sync_article_snapshot_and_source(db, article, paragraph_texts, source_type='manual')
    db.commit()
    db.refresh(article)
    return success(_serialize_admin_article(db, article))


@router.post('/articles/{article_id}/publish')
def publish_admin_article(
    article_id: int,
    payload: PublishRequest,
    _: User = Depends(require_admin_user),
    db: Session = Depends(get_db),
) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    article.is_published = payload.is_published
    article.status = 'published' if payload.is_published else 'draft'
    if payload.is_published:
        _enqueue_audio_task(db, article)
    db.commit()
    db.refresh(article)
    return success(_serialize_admin_article(db, article))


@router.get('/articles/{article_id}/audio-task')
def admin_audio_task(article_id: int, _: User = Depends(require_admin_user), db: Session = Depends(get_db)) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')
    task = db.scalar(select(ArticleAudioTask).where(ArticleAudioTask.article_id == article.id))
    if task is not None:
        task = _progress_audio_task(db, article, task)
    task_data: dict[str, Any] | None = None
    if task is not None:
        task_data = {
            'id': task.id,
            'status': task.status,
            'attempt_count': task.attempt_count,
            'max_attempts': task.max_attempts,
            'last_error': task.last_error,
            'article_audio_url': article.article_audio_url,
        }
    return success({'task': task_data})


@router.get('/articles/{article_id}/sentence-analyses')
def admin_get_sentence_analyses(article_id: int, _: User = Depends(require_admin_user), db: Session = Depends(get_db)) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')
    items = db.scalars(
        select(SentenceAnalysis)
        .where(SentenceAnalysis.article_id == article_id)
        .order_by(SentenceAnalysis.sentence_index.asc(), SentenceAnalysis.id.asc())
    ).all()
    return success({'items': [{'sentence_index': item.sentence_index, 'sentence': item.sentence, 'translation': item.translation, 'structure': item.structure} for item in items]})


@router.put('/articles/{article_id}/sentence-analyses')
def admin_replace_sentence_analyses(
    article_id: int,
    payload: SentenceAnalysisReplaceRequest,
    _: User = Depends(require_admin_user),
    db: Session = Depends(get_db),
) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')
    db.execute(delete(SentenceAnalysis).where(SentenceAnalysis.article_id == article_id))
    for item in payload.items:
        db.add(
            SentenceAnalysis(
                article_id=article_id,
                sentence_index=item.sentence_index,
                sentence=item.sentence,
                translation=item.translation,
                structure=item.structure,
            )
        )
    db.commit()
    return success(
        {
            'items': [
                {
                    'sentence_index': item.sentence_index,
                    'sentence': item.sentence,
                    'translation': item.translation,
                    'structure': item.structure,
                }
                for item in db.scalars(
                    select(SentenceAnalysis)
                    .where(SentenceAnalysis.article_id == article_id)
                    .order_by(SentenceAnalysis.sentence_index.asc(), SentenceAnalysis.id.asc())
                ).all()
            ]
        }
    )


@router.get('/articles/{article_id}/quiz')
def admin_get_quiz(article_id: int, _: User = Depends(require_admin_user), db: Session = Depends(get_db)) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    quiz = db.scalar(select(Quiz).where(Quiz.article_id == article_id))
    if quiz is None:
        return success({'questions': []})

    questions = db.scalars(
        select(QuizQuestion)
        .where(QuizQuestion.quiz_id == quiz.id)
        .order_by(QuizQuestion.question_index.asc(), QuizQuestion.id.asc())
    ).all()

    serialized_questions: list[dict[str, Any]] = []
    for question in questions:
        options = db.scalars(
            select(QuizOption)
            .where(QuizOption.question_id == question.id)
            .order_by(QuizOption.option_index.asc(), QuizOption.id.asc())
        ).all()
        correct_option_index = next((option.option_index for option in options if option.is_correct), None)
        serialized_questions.append(
            {
                'question_index': question.question_index,
                'stem': question.stem,
                'options': [option.content for option in options],
                'correct_option_index': correct_option_index,
            }
        )

    return success({'questions': serialized_questions})

@router.put('/articles/{article_id}/quiz')
def admin_replace_quiz(
    article_id: int,
    payload: QuizReplaceRequest,
    _: User = Depends(require_admin_user),
    db: Session = Depends(get_db),
) -> dict:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')

    quiz = db.scalar(select(Quiz).where(Quiz.article_id == article_id))
    if quiz is not None:
        question_ids = db.scalars(select(QuizQuestion.id).where(QuizQuestion.quiz_id == quiz.id)).all()
        if question_ids:
            db.execute(delete(QuizOption).where(QuizOption.question_id.in_(question_ids)))
        db.execute(delete(QuizQuestion).where(QuizQuestion.quiz_id == quiz.id))
    else:
        quiz = Quiz(article_id=article_id)
        db.add(quiz)
        db.flush()

    serialized_questions: list[dict] = []
    for item in payload.questions:
        question = QuizQuestion(quiz_id=quiz.id, question_index=item.question_index, stem=item.stem)
        db.add(question)
        db.flush()
        for option_index, option_text in enumerate(item.options, start=1):
            db.add(
                QuizOption(
                    question_id=question.id,
                    option_index=option_index,
                    content=option_text,
                    is_correct=(option_index == item.correct_option_index),
                )
            )
        serialized_questions.append(
            {
                'question_index': item.question_index,
                'stem': item.stem,
                'options': item.options,
                'correct_option_index': item.correct_option_index,
            }
        )
    db.commit()
    return success({'questions': serialized_questions})


@router.get('/words')
def admin_list_words(
    _: User = Depends(require_admin_user),
    q: str | None = Query(default=None, min_length=1, max_length=100),
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    db: Session = Depends(get_db),
) -> dict:
    query = select(Word).order_by(Word.id.desc())
    if q:
        fuzzy = f'%{q.strip()}%'
        query = query.where(or_(Word.lemma.ilike(fuzzy), Word.meaning_cn.ilike(fuzzy), Word.pos.ilike(fuzzy)))
    words = db.scalars(query).all()
    total = len(words)
    start = (page - 1) * size
    items = words[start:start + size]
    return success(
        {
            'items': [{'id': word.id, 'lemma': word.lemma, 'phonetic': word.phonetic, 'pos': word.pos, 'meaning_cn': word.meaning_cn} for word in items],
            'page': page,
            'size': size,
            'total': total,
            'has_next': start + len(items) < total,
        }
    )


@router.post('/words')
def admin_create_word(payload: AdminWordCreateRequest, _: User = Depends(require_admin_user), db: Session = Depends(get_db)) -> dict:
    word = Word(lemma=payload.lemma.lower(), phonetic=payload.phonetic, pos=payload.pos, meaning_cn=payload.meaning_cn)
    db.add(word)
    db.commit()
    db.refresh(word)
    return success({'id': word.id, 'lemma': word.lemma, 'phonetic': word.phonetic, 'pos': word.pos, 'meaning_cn': word.meaning_cn})


@router.patch('/words/{word_id}')
def admin_update_word(
    word_id: int,
    payload: AdminWordUpdateRequest,
    _: User = Depends(require_admin_user),
    db: Session = Depends(get_db),
) -> dict:
    word = db.get(Word, word_id)
    if word is None:
        raise HTTPException(status_code=404, detail='word not found')
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(word, key, value)
    db.commit()
    db.refresh(word)
    return success({'id': word.id, 'lemma': word.lemma, 'phonetic': word.phonetic, 'pos': word.pos, 'meaning_cn': word.meaning_cn})




