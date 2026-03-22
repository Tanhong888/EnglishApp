import logging
import threading
from datetime import datetime, timedelta, timezone
from time import sleep

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models import Article, ArticleAudioTask
from app.db.session import SessionLocal

logger = logging.getLogger('englishapp.tts')


def _utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def serialize_audio_task(task: ArticleAudioTask | None, article: Article | None = None) -> dict | None:
    if task is None:
        return None

    return {
        'task_id': task.id,
        'article_id': task.article_id,
        'status': task.status,
        'attempt_count': task.attempt_count,
        'max_attempts': task.max_attempts,
        'next_retry_at': task.next_retry_at.isoformat() if task.next_retry_at else None,
        'processing_started_at': task.processing_started_at.isoformat() if task.processing_started_at else None,
        'completed_at': task.completed_at.isoformat() if task.completed_at else None,
        'last_error': task.last_error,
        'article_audio_url': article.article_audio_url if article is not None else None,
    }


def get_article_audio_task(db: Session, article_id: int) -> ArticleAudioTask | None:
    return db.scalar(select(ArticleAudioTask).where(ArticleAudioTask.article_id == article_id))


def get_or_create_audio_task(db: Session, article: Article) -> ArticleAudioTask:
    task = get_article_audio_task(db, article.id)
    if task is None:
        task = ArticleAudioTask(article_id=article.id)
        db.add(task)
        db.flush()
    return task


def enqueue_article_audio_generation(db: Session, article: Article, force: bool = False) -> ArticleAudioTask:
    task = get_or_create_audio_task(db, article)
    should_reset = force or task.status in {'ready', 'failed'}
    should_queue = force or task.status not in {'pending', 'processing'}

    if should_reset:
        task.attempt_count = 0
        task.max_attempts = settings.tts_max_attempts
        task.completed_at = None
        task.last_error = None

    if should_queue:
        task.status = 'pending'
        task.next_retry_at = None
        task.processing_started_at = None
        article.audio_status = 'pending'
        article.article_audio_url = None
    else:
        article.audio_status = task.status

    db.flush()
    return task


def _mock_audio_url(article_id: int) -> str:
    base = settings.public_base_url.rstrip('/')
    return f'{base}{settings.api_prefix}/articles/{article_id}/audio/file'


def _should_mock_fail(article: Article) -> bool:
    keyword = settings.tts_mock_fail_keyword.strip().lower()
    if not keyword:
        return False
    return keyword in article.title.lower() or keyword in article.topic.lower()


def _claim_pending_tasks(db: Session, now: datetime, batch_size: int) -> int:
    pending_tasks = db.scalars(
        select(ArticleAudioTask)
        .where(
            ArticleAudioTask.status == 'pending',
            or_(ArticleAudioTask.next_retry_at.is_(None), ArticleAudioTask.next_retry_at <= now),
        )
        .order_by(ArticleAudioTask.created_at.asc(), ArticleAudioTask.id.asc())
        .limit(batch_size)
    ).all()

    for task in pending_tasks:
        article = db.get(Article, task.article_id)
        if article is None:
            task.status = 'failed'
            task.completed_at = now
            task.last_error = 'article_not_found'
            continue

        task.status = 'processing'
        task.processing_started_at = now
        task.attempt_count += 1
        task.last_error = None
        article.audio_status = 'processing'
        article.article_audio_url = None

    return len(pending_tasks)


def _finalize_processing_tasks(db: Session, now: datetime, batch_size: int) -> int:
    ready_to_finalize_at = now - timedelta(seconds=settings.tts_processing_delay_seconds)
    processing_tasks = db.scalars(
        select(ArticleAudioTask)
        .where(
            ArticleAudioTask.status == 'processing',
            ArticleAudioTask.processing_started_at.is_not(None),
            ArticleAudioTask.processing_started_at <= ready_to_finalize_at,
        )
        .order_by(ArticleAudioTask.processing_started_at.asc(), ArticleAudioTask.id.asc())
        .limit(batch_size)
    ).all()

    for task in processing_tasks:
        article = db.get(Article, task.article_id)
        if article is None:
            task.status = 'failed'
            task.completed_at = now
            task.last_error = 'article_not_found'
            continue

        if _should_mock_fail(article):
            if task.attempt_count >= task.max_attempts:
                task.status = 'failed'
                task.completed_at = now
                task.next_retry_at = None
                task.processing_started_at = None
                task.last_error = 'mock_tts_generation_failed'
                article.audio_status = 'failed'
                article.article_audio_url = None
            else:
                retry_delay = settings.tts_retry_base_delay_seconds * (2 ** max(task.attempt_count - 1, 0))
                task.status = 'pending'
                task.processing_started_at = None
                task.next_retry_at = now + timedelta(seconds=retry_delay)
                task.last_error = 'mock_tts_generation_failed'
                article.audio_status = 'pending'
                article.article_audio_url = None
            continue

        task.status = 'ready'
        task.completed_at = now
        task.next_retry_at = None
        task.processing_started_at = None
        task.last_error = None
        article.audio_status = 'ready'
        article.article_audio_url = _mock_audio_url(article.id)

    return len(processing_tasks)


def process_due_audio_tasks(db: Session, batch_size: int = 5) -> int:
    now = _utc_now()
    finalized = _finalize_processing_tasks(db, now, batch_size)
    claimed = _claim_pending_tasks(db, now, batch_size)
    if finalized or claimed:
        db.commit()
    return finalized + claimed


class MockTtsWorker:
    def __init__(self) -> None:
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if not settings.tts_worker_enabled:
            return
        if self._thread is not None and self._thread.is_alive():
            return

        self._stop_event = threading.Event()
        self._thread = threading.Thread(target=self._run_loop, name='englishapp-tts-worker', daemon=True)
        self._thread.start()
        logger.info('Mock TTS worker started')

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None
            logger.info('Mock TTS worker stopped')

    def _run_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                with SessionLocal() as db:
                    process_due_audio_tasks(db)
            except Exception:
                logger.exception('Mock TTS worker iteration failed')
            sleep(settings.tts_worker_poll_interval_seconds)
