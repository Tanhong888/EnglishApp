import re
from datetime import datetime
from typing import Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import Article, ArticleContent, ArticleParagraph, ArticleSource, UserReadingProgress


def slugify_title(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.strip().lower())
    return slug.strip("-") or "article"


def ensure_article_slug(db: Session, article: Article) -> str:
    base_slug = slugify_title(article.title)
    candidate = base_slug

    if article.id is not None:
        conflict = db.scalar(select(Article.id).where(Article.slug == candidate, Article.id != article.id))
    else:
        conflict = db.scalar(select(Article.id).where(Article.slug == candidate))

    if conflict is not None:
        suffix = article.id or db.scalar(select(func.count(Article.id))) or 0
        candidate = f"{base_slug}-{suffix}"

    article.slug = candidate
    return candidate


def summarize_paragraphs(paragraphs: Sequence[str], limit: int = 240) -> str | None:
    text = " ".join(item.strip() for item in paragraphs if item and item.strip())
    if not text:
        return None
    normalized = re.sub(r"\s+", " ", text).strip()
    if len(normalized) <= limit:
        return normalized
    clipped = normalized[:limit].rstrip()
    last_space = clipped.rfind(" ")
    if last_space > 0:
        clipped = clipped[:last_space]
    return f"{clipped}..."


def build_content_text(paragraphs: Sequence[str]) -> str:
    return "\n\n".join(item.strip() for item in paragraphs if item and item.strip())


def count_english_words(text: str) -> int:
    return len(re.findall(r"[A-Za-z]+", text or ""))


def sync_article_content_snapshot(
    db: Session,
    *,
    article: Article,
    paragraphs: Sequence[str],
) -> ArticleContent | None:
    content_text = build_content_text(paragraphs)
    if not content_text:
        return None

    latest = db.scalar(
        select(ArticleContent)
        .where(ArticleContent.article_id == article.id)
        .order_by(ArticleContent.version.desc(), ArticleContent.id.desc())
        .limit(1)
    )
    word_count = count_english_words(content_text)

    if (
        latest is not None
        and latest.content_text == content_text
        and latest.estimated_reading_minutes == article.reading_minutes
        and latest.word_count == word_count
    ):
        return latest

    next_version = 1 if latest is None else latest.version + 1
    snapshot = ArticleContent(
        article_id=article.id,
        version=next_version,
        content_text=content_text,
        word_count=word_count,
        estimated_reading_minutes=article.reading_minutes,
    )
    db.add(snapshot)
    db.flush()
    return snapshot


def ensure_article_source(
    db: Session,
    *,
    article: Article,
    source_type: str,
    source_name: str | None = None,
    source_url: str | None = None,
    author: str | None = None,
    publisher: str | None = None,
    external_id: str | None = None,
    fetched_at: datetime | None = None,
) -> ArticleSource:
    source = db.scalar(
        select(ArticleSource).where(
            ArticleSource.article_id == article.id,
            ArticleSource.source_type == source_type,
        )
    )
    if source is None:
        source = ArticleSource(article_id=article.id, source_type=source_type)
        db.add(source)

    source.source_name = source_name or source.source_name
    source.source_url = source_url or source.source_url
    source.author = author or source.author
    source.publisher = publisher or source.publisher
    source.external_id = external_id or source.external_id
    source.fetched_at = fetched_at or source.fetched_at
    db.flush()
    return source


def compute_progress_fields(paragraph_index: int, paragraph_count: int) -> tuple[int, float, bool]:
    if paragraph_count <= 0:
        normalized_index = max(paragraph_index, 1)
        return normalized_index, 0.0, False

    normalized_index = min(max(paragraph_index, 1), paragraph_count)
    progress_percent = round((normalized_index / paragraph_count) * 100, 2)
    return normalized_index, progress_percent, normalized_index >= paragraph_count


def sync_reading_progress_completion(
    db: Session,
    *,
    progress: UserReadingProgress,
    article: Article,
    completed_at_fallback: datetime | None = None,
) -> UserReadingProgress:
    paragraph_count = db.scalar(
        select(func.count(ArticleParagraph.id)).where(ArticleParagraph.article_id == article.id)
    ) or 0
    normalized_index, progress_percent, completed = compute_progress_fields(progress.paragraph_index, paragraph_count)
    progress.paragraph_index = normalized_index
    progress.progress_percent = progress_percent

    if completed:
        progress.completed_at = progress.completed_at or completed_at_fallback or progress.last_read_at
    elif article.is_completed and progress.completed_at is None:
        progress.progress_percent = 100.0
        progress.completed_at = completed_at_fallback or progress.last_read_at
    else:
        progress.completed_at = None

    return progress
