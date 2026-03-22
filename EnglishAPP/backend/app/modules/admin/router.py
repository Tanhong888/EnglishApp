from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.response import success
from app.db.models import Article, ArticleParagraph, Quiz, QuizOption, QuizQuestion, SentenceAnalysis, Word
from app.db.session import get_db
from app.tasks.audio_tasks import enqueue_article_audio_generation, get_article_audio_task, serialize_audio_task

router = APIRouter()


StageTag = Literal['cet4', 'cet6', 'kaoyan']


class AdminArticleCreateRequest(BaseModel):
    title: str
    stage_tag: StageTag
    level: int = Field(ge=1, le=4)
    topic: str
    reading_minutes: int = Field(ge=1, le=60)
    is_published: bool = False
    paragraphs: list[str] = Field(min_length=1)

    @field_validator('title', 'topic')
    @classmethod
    def validate_non_empty_text(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError('field cannot be empty')
        return cleaned

    @field_validator('paragraphs')
    @classmethod
    def validate_paragraphs(cls, value: list[str]) -> list[str]:
        paragraphs = [item.strip() for item in value if item.strip()]
        if not paragraphs:
            raise ValueError('paragraphs cannot be empty')
        return paragraphs


class AdminArticleUpdateRequest(BaseModel):
    title: str | None = None
    stage_tag: StageTag | None = None
    level: int | None = Field(default=None, ge=1, le=4)
    topic: str | None = None
    reading_minutes: int | None = Field(default=None, ge=1, le=60)
    is_published: bool | None = None
    paragraphs: list[str] | None = Field(default=None, min_length=1)

    @field_validator('title', 'topic')
    @classmethod
    def validate_optional_non_empty_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            raise ValueError('field cannot be empty')
        return cleaned

    @field_validator('paragraphs')
    @classmethod
    def validate_optional_paragraphs(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        paragraphs = [item.strip() for item in value if item.strip()]
        if not paragraphs:
            raise ValueError('paragraphs cannot be empty')
        return paragraphs


class PublishArticleRequest(BaseModel):
    is_published: bool = True


class GenerateAudioRequest(BaseModel):
    force: bool = True


class SentenceAnalysisInput(BaseModel):
    sentence_index: int = Field(ge=1)
    sentence: str
    translation: str | None = None
    structure: str | None = None

    @field_validator('sentence')
    @classmethod
    def validate_sentence(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError('sentence cannot be empty')
        return cleaned

    @field_validator('translation', 'structure')
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class ReplaceSentenceAnalysesRequest(BaseModel):
    items: list[SentenceAnalysisInput]


class QuizQuestionInput(BaseModel):
    question_index: int = Field(ge=1)
    stem: str
    options: list[str] = Field(min_length=2, max_length=6)
    correct_option_index: int = Field(ge=1)

    @field_validator('stem')
    @classmethod
    def validate_stem(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError('stem cannot be empty')
        return cleaned

    @field_validator('options')
    @classmethod
    def validate_options(cls, value: list[str]) -> list[str]:
        options = [item.strip() for item in value if item.strip()]
        if len(options) < 2:
            raise ValueError('options must contain at least two non-empty items')
        return options

    @field_validator('correct_option_index')
    @classmethod
    def validate_correct_option_index(cls, value: int, info) -> int:
        options = info.data.get('options') or []
        if options and value > len(options):
            raise ValueError('correct_option_index out of range')
        return value


class ReplaceQuizRequest(BaseModel):
    questions: list[QuizQuestionInput]


class WordCreateRequest(BaseModel):
    lemma: str
    phonetic: str | None = None
    pos: str | None = None
    meaning_cn: str | None = None

    @field_validator('lemma')
    @classmethod
    def validate_lemma(cls, value: str) -> str:
        cleaned = value.strip().lower()
        if not cleaned:
            raise ValueError('lemma cannot be empty')
        return cleaned

    @field_validator('phonetic', 'pos', 'meaning_cn')
    @classmethod
    def normalize_optional_word_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class WordUpdateRequest(BaseModel):
    phonetic: str | None = None
    pos: str | None = None
    meaning_cn: str | None = None

    @field_validator('phonetic', 'pos', 'meaning_cn')
    @classmethod
    def normalize_optional_word_update_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None



def require_admin_key(x_admin_key: str | None = Header(default=None)) -> None:
    expected_key = settings.admin_api_key.strip()
    if not expected_key:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='admin_api_key_not_configured')
    if x_admin_key is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='missing_admin_key')
    if x_admin_key != expected_key:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='invalid_admin_key')



def _load_article_or_404(db: Session, article_id: int) -> Article:
    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=404, detail='article not found')
    return article



def _load_word_or_404(db: Session, word_id: int) -> Word:
    word = db.get(Word, word_id)
    if word is None:
        raise HTTPException(status_code=404, detail='word not found')
    return word



def _load_paragraphs(db: Session, article_id: int) -> list[ArticleParagraph]:
    return db.scalars(
        select(ArticleParagraph)
        .where(ArticleParagraph.article_id == article_id)
        .order_by(ArticleParagraph.paragraph_index.asc())
    ).all()



def _replace_paragraphs(db: Session, article_id: int, paragraphs: list[str]) -> None:
    db.execute(delete(ArticleParagraph).where(ArticleParagraph.article_id == article_id))
    for index, paragraph in enumerate(paragraphs, start=1):
        db.add(ArticleParagraph(article_id=article_id, paragraph_index=index, text=paragraph))



def _load_sentence_analyses(db: Session, article_id: int) -> list[SentenceAnalysis]:
    return db.scalars(
        select(SentenceAnalysis)
        .where(SentenceAnalysis.article_id == article_id)
        .order_by(SentenceAnalysis.sentence_index.asc(), SentenceAnalysis.id.asc())
    ).all()



def _replace_sentence_analyses(db: Session, article_id: int, items: list[SentenceAnalysisInput]) -> list[SentenceAnalysis]:
    db.execute(delete(SentenceAnalysis).where(SentenceAnalysis.article_id == article_id))
    rows: list[SentenceAnalysis] = []
    for item in sorted(items, key=lambda row: row.sentence_index):
        row = SentenceAnalysis(
            article_id=article_id,
            sentence_index=item.sentence_index,
            sentence=item.sentence,
            translation=item.translation,
            structure=item.structure,
        )
        db.add(row)
        rows.append(row)
    db.flush()
    return rows



def _load_quiz_bundle(db: Session, article_id: int) -> tuple[Quiz | None, list[QuizQuestion], dict[int, list[QuizOption]]]:
    quiz = db.scalar(select(Quiz).where(Quiz.article_id == article_id))
    if quiz is None:
        return None, [], {}

    questions = db.scalars(
        select(QuizQuestion)
        .where(QuizQuestion.quiz_id == quiz.id)
        .order_by(QuizQuestion.question_index.asc(), QuizQuestion.id.asc())
    ).all()
    if not questions:
        return quiz, [], {}

    question_ids = [question.id for question in questions]
    options = db.scalars(
        select(QuizOption)
        .where(QuizOption.question_id.in_(question_ids))
        .order_by(QuizOption.question_id.asc(), QuizOption.option_index.asc(), QuizOption.id.asc())
    ).all()
    options_by_question: dict[int, list[QuizOption]] = {}
    for option in options:
        options_by_question.setdefault(option.question_id, []).append(option)

    return quiz, questions, options_by_question



def _replace_quiz(db: Session, article_id: int, payload: ReplaceQuizRequest) -> tuple[Quiz, list[QuizQuestion], dict[int, list[QuizOption]]]:
    quiz, existing_questions, _ = _load_quiz_bundle(db, article_id)
    if quiz is None:
        quiz = Quiz(article_id=article_id)
        db.add(quiz)
        db.flush()

    question_ids = [question.id for question in existing_questions]
    if question_ids:
        db.execute(delete(QuizOption).where(QuizOption.question_id.in_(question_ids)))
        db.execute(delete(QuizQuestion).where(QuizQuestion.quiz_id == quiz.id))

    created_questions: list[QuizQuestion] = []
    options_by_question: dict[int, list[QuizOption]] = {}
    for question_payload in sorted(payload.questions, key=lambda row: row.question_index):
        question = QuizQuestion(
            quiz_id=quiz.id,
            question_index=question_payload.question_index,
            stem=question_payload.stem,
        )
        db.add(question)
        db.flush()
        created_questions.append(question)

        created_options: list[QuizOption] = []
        for option_index, option_content in enumerate(question_payload.options, start=1):
            option = QuizOption(
                question_id=question.id,
                option_index=option_index,
                content=option_content,
                is_correct=option_index == question_payload.correct_option_index,
            )
            db.add(option)
            created_options.append(option)
        options_by_question[question.id] = created_options

    db.flush()
    return quiz, created_questions, options_by_question



def _serialize_article(article: Article, paragraphs: list[ArticleParagraph]) -> dict:
    return {
        'id': article.id,
        'title': article.title,
        'stage': article.stage_tag,
        'level': article.level,
        'topic': article.topic,
        'reading_minutes': article.reading_minutes,
        'is_published': article.is_published,
        'audio_status': article.audio_status,
        'article_audio_url': article.article_audio_url,
        'published_at': article.published_at.isoformat() if article.published_at else None,
        'updated_at': article.updated_at.isoformat() if article.updated_at else None,
        'paragraph_count': len(paragraphs),
        'paragraphs': [{'index': paragraph.paragraph_index, 'text': paragraph.text} for paragraph in paragraphs],
    }



def _serialize_sentence_analyses(article_id: int, rows: list[SentenceAnalysis]) -> dict:
    return {
        'article_id': article_id,
        'items': [
            {
                'sentence_id': row.id,
                'sentence_index': row.sentence_index,
                'sentence': row.sentence,
                'translation': row.translation,
                'structure': row.structure,
            }
            for row in rows
        ],
    }



def _serialize_quiz(article_id: int, questions: list[QuizQuestion], options_by_question: dict[int, list[QuizOption]]) -> dict:
    return {
        'article_id': article_id,
        'questions': [
            {
                'question_id': question.id,
                'question_index': question.question_index,
                'stem': question.stem,
                'correct_option_index': next(
                    (option.option_index for option in options_by_question.get(question.id, []) if option.is_correct),
                    None,
                ),
                'options': [
                    {
                        'option_id': option.id,
                        'option_index': option.option_index,
                        'content': option.content,
                        'is_correct': option.is_correct,
                    }
                    for option in options_by_question.get(question.id, [])
                ],
            }
            for question in questions
        ],
    }



def _serialize_word(word: Word) -> dict:
    return {
        'id': word.id,
        'lemma': word.lemma,
        'phonetic': word.phonetic,
        'pos': word.pos,
        'meaning_cn': word.meaning_cn,
    }


@router.get('/articles')
def list_admin_articles(
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    published: bool | None = None,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    query = select(Article)
    if published is not None:
        query = query.where(Article.is_published.is_(published))

    query = query.order_by(Article.updated_at.desc(), Article.id.desc())
    total = db.scalar(select(func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * size
    articles = db.scalars(query.offset(offset).limit(size)).all()

    items = []
    for article in articles:
        paragraph_count = db.scalar(
            select(func.count()).select_from(ArticleParagraph).where(ArticleParagraph.article_id == article.id)
        ) or 0
        items.append(
            {
                'id': article.id,
                'title': article.title,
                'stage': article.stage_tag,
                'level': article.level,
                'topic': article.topic,
                'reading_minutes': article.reading_minutes,
                'is_published': article.is_published,
                'audio_status': article.audio_status,
                'published_at': article.published_at.isoformat() if article.published_at else None,
                'updated_at': article.updated_at.isoformat() if article.updated_at else None,
                'paragraph_count': paragraph_count,
            }
        )

    return success(
        {
            'items': items,
            'page': page,
            'size': size,
            'total': total,
            'has_next': offset + len(items) < total,
        }
    )


@router.get('/articles/{article_id}')
def get_admin_article(
    article_id: int,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    article = _load_article_or_404(db, article_id)
    paragraphs = _load_paragraphs(db, article_id)
    return success(_serialize_article(article, paragraphs))


@router.post('/articles')
def create_admin_article(
    payload: AdminArticleCreateRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    article = Article(
        title=payload.title,
        stage_tag=payload.stage_tag,
        level=payload.level,
        topic=payload.topic,
        reading_minutes=payload.reading_minutes,
        is_published=payload.is_published,
        audio_status='pending' if payload.is_published else 'pending',
        article_audio_url=None,
        published_at=now,
    )
    db.add(article)
    db.flush()
    _replace_paragraphs(db, article.id, payload.paragraphs)
    if payload.is_published:
        enqueue_article_audio_generation(db, article, force=True)
    db.commit()
    db.refresh(article)

    paragraphs = _load_paragraphs(db, article.id)
    return success(_serialize_article(article, paragraphs))


@router.patch('/articles/{article_id}')
def update_admin_article(
    article_id: int,
    payload: AdminArticleUpdateRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    article = _load_article_or_404(db, article_id)
    became_published = False
    should_regenerate_audio = False

    if payload.title is not None:
        article.title = payload.title
    if payload.stage_tag is not None:
        article.stage_tag = payload.stage_tag
    if payload.level is not None:
        article.level = payload.level
    if payload.topic is not None:
        article.topic = payload.topic
    if payload.reading_minutes is not None:
        article.reading_minutes = payload.reading_minutes
    if payload.is_published is not None:
        if payload.is_published and not article.is_published:
            article.published_at = datetime.now(timezone.utc).replace(tzinfo=None)
            became_published = True
        article.is_published = payload.is_published
    if payload.paragraphs is not None:
        _replace_paragraphs(db, article.id, payload.paragraphs)
        if article.is_published or payload.is_published is True:
            should_regenerate_audio = True

    if became_published or should_regenerate_audio:
        enqueue_article_audio_generation(db, article, force=True)

    db.commit()
    db.refresh(article)
    paragraphs = _load_paragraphs(db, article.id)
    return success(_serialize_article(article, paragraphs))


@router.post('/articles/{article_id}/publish')
def publish_admin_article(
    article_id: int,
    payload: PublishArticleRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    article = _load_article_or_404(db, article_id)
    if payload.is_published and not article.is_published:
        article.published_at = datetime.now(timezone.utc).replace(tzinfo=None)
    article.is_published = payload.is_published
    if payload.is_published:
        enqueue_article_audio_generation(db, article, force=True)

    db.commit()
    db.refresh(article)
    paragraphs = _load_paragraphs(db, article.id)
    return success(_serialize_article(article, paragraphs))


@router.get('/articles/{article_id}/audio-task')
def get_admin_audio_task(
    article_id: int,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    article = _load_article_or_404(db, article_id)
    task = get_article_audio_task(db, article_id)
    return success({'article_id': article_id, 'task': serialize_audio_task(task, article)})


@router.post('/articles/{article_id}/audio/generate')
def generate_admin_audio(
    article_id: int,
    payload: GenerateAudioRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    article = _load_article_or_404(db, article_id)
    if not article.is_published:
        raise HTTPException(status_code=409, detail='article must be published before audio generation')

    task = enqueue_article_audio_generation(db, article, force=payload.force)
    db.commit()
    db.refresh(article)
    return success({'article_id': article_id, 'task': serialize_audio_task(task, article)})


@router.get('/articles/{article_id}/sentence-analyses')
def get_admin_sentence_analyses(
    article_id: int,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    _load_article_or_404(db, article_id)
    rows = _load_sentence_analyses(db, article_id)
    return success(_serialize_sentence_analyses(article_id, rows))


@router.put('/articles/{article_id}/sentence-analyses')
def replace_admin_sentence_analyses(
    article_id: int,
    payload: ReplaceSentenceAnalysesRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    _load_article_or_404(db, article_id)
    _replace_sentence_analyses(db, article_id, payload.items)
    db.commit()
    rows = _load_sentence_analyses(db, article_id)
    return success(_serialize_sentence_analyses(article_id, rows))


@router.get('/articles/{article_id}/quiz')
def get_admin_quiz(
    article_id: int,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    _load_article_or_404(db, article_id)
    _, questions, options_by_question = _load_quiz_bundle(db, article_id)
    return success(_serialize_quiz(article_id, questions, options_by_question))


@router.put('/articles/{article_id}/quiz')
def replace_admin_quiz(
    article_id: int,
    payload: ReplaceQuizRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    _load_article_or_404(db, article_id)
    _, questions, options_by_question = _replace_quiz(db, article_id, payload)
    db.commit()
    return success(_serialize_quiz(article_id, questions, options_by_question))


@router.get('/words')
def list_admin_words(
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
    q: str | None = None,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    query = select(Word)
    if q:
        normalized = f'%{q.strip().lower()}%'
        query = query.where(
            func.lower(Word.lemma).like(normalized)
            | func.lower(func.coalesce(Word.meaning_cn, '')).like(normalized)
            | func.lower(func.coalesce(Word.pos, '')).like(normalized)
        )

    query = query.order_by(Word.lemma.asc(), Word.id.asc())
    total = db.scalar(select(func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * size
    items = db.scalars(query.offset(offset).limit(size)).all()

    return success(
        {
            'items': [_serialize_word(word) for word in items],
            'page': page,
            'size': size,
            'total': total,
            'has_next': offset + len(items) < total,
        }
    )


@router.post('/words')
def create_admin_word(
    payload: WordCreateRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    exists = db.scalar(select(Word).where(func.lower(Word.lemma) == payload.lemma))
    if exists is not None:
        raise HTTPException(status_code=409, detail='word already exists')

    word = Word(
        lemma=payload.lemma,
        phonetic=payload.phonetic,
        pos=payload.pos,
        meaning_cn=payload.meaning_cn,
    )
    db.add(word)
    db.commit()
    db.refresh(word)
    return success(_serialize_word(word))


@router.patch('/words/{word_id}')
def update_admin_word(
    word_id: int,
    payload: WordUpdateRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    word = _load_word_or_404(db, word_id)
    if payload.phonetic is not None:
        word.phonetic = payload.phonetic
    if payload.pos is not None:
        word.pos = payload.pos
    if payload.meaning_cn is not None:
        word.meaning_cn = payload.meaning_cn
    db.commit()
    db.refresh(word)
    return success(_serialize_word(word))
