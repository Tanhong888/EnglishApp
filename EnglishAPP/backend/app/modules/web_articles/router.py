from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html import unescape
import re
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from xml.etree import ElementTree as ET

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.response import success
from app.db.article_content_sync import count_english_words, ensure_article_slug, ensure_article_source, sync_article_content_snapshot
from app.db.models import Article, ArticleParagraph, ArticleSource
from app.db.session import get_db

router = APIRouter()


class ImportWebArticleRequest(BaseModel):
    title: str
    url: str
    source: str
    summary: str | None = None
    published_at: str | None = None
    stage_tag: str | None = None
    level: int | None = Field(default=None, ge=1, le=4)
    topic: str | None = None
    force_new: bool = False

    @field_validator('title', 'url', 'source')
    @classmethod
    def validate_non_empty_text(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError('field cannot be empty')
        return cleaned

    @field_validator('summary', 'published_at', 'stage_tag', 'topic')
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
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


def _feed_urls() -> list[str]:
    return [item.strip() for item in settings.web_article_feed_urls.split(',') if item.strip()]


def _strip_html(value: str | None) -> str:
    if not value:
        return ''
    text = re.sub(r'<[^>]+>', ' ', value)
    text = unescape(text)
    return re.sub(r'\s+', ' ', text).strip()


def _parse_datetime(raw: str | None) -> datetime | None:
    if not raw:
        return None

    try:
        dt = parsedate_to_datetime(raw)
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except (TypeError, ValueError, IndexError):
        pass

    try:
        normalized = raw.replace('Z', '+00:00')
        dt = datetime.fromisoformat(normalized)
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except ValueError:
        return None


def fetch_feed_xml(feed_url: str) -> str:
    request = Request(
        feed_url,
        headers={
            'User-Agent': 'EnglishAPP/0.1 (+https://github.com/Tanhong888/EnglishApp)',
            'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml',
        },
    )
    with urlopen(request, timeout=settings.web_article_request_timeout_seconds) as response:
        return response.read().decode('utf-8', errors='ignore')


def _first_text(element: ET.Element | None, names: list[str], namespaces: dict[str, str] | None = None) -> str | None:
    if element is None:
        return None

    for name in names:
        node = element.find(name, namespaces or {})
        if node is not None and node.text and node.text.strip():
            return node.text.strip()
    return None


def _parse_rss_items(root: ET.Element, feed_url: str) -> list[dict]:
    channel = root.find('channel')
    if channel is None:
        return []

    namespaces = {
        'content': 'http://purl.org/rss/1.0/modules/content/',
        'dc': 'http://purl.org/dc/elements/1.1/',
    }
    feed_title = _first_text(channel, ['title']) or feed_url
    items: list[dict] = []
    for item in channel.findall('item'):
        link = _first_text(item, ['link'])
        if not link:
            continue

        source = _first_text(item, ['source']) or feed_title
        summary = _strip_html(_first_text(item, ['description', 'content:encoded', 'dc:description'], namespaces))
        published_dt = _parse_datetime(_first_text(item, ['pubDate', 'dc:date'], namespaces))

        items.append(
            {
                'title': _first_text(item, ['title']) or 'Untitled',
                'source': source,
                'summary': summary,
                'url': link,
                'published_at': published_dt.isoformat() if published_dt else None,
                '_published_sort': published_dt or datetime(1970, 1, 1, tzinfo=timezone.utc),
            }
        )
    return items


def _parse_atom_items(root: ET.Element, feed_url: str) -> list[dict]:
    ns = {'atom': 'http://www.w3.org/2005/Atom'}
    feed_title = _first_text(root, ['atom:title'], ns) or feed_url
    items: list[dict] = []
    for entry in root.findall('atom:entry', ns):
        link = None
        for candidate in entry.findall('atom:link', ns):
            href = candidate.attrib.get('href')
            if href:
                link = href
                break
        if not link:
            continue

        source = feed_title
        source_node = entry.find('atom:source/atom:title', ns)
        if source_node is not None and source_node.text and source_node.text.strip():
            source = source_node.text.strip()

        summary = _strip_html(
            _first_text(entry, ['atom:summary', 'atom:content'], ns)
            or _first_text(entry, ['summary', 'content'])
        )
        published_dt = _parse_datetime(
            _first_text(entry, ['atom:updated', 'atom:published'], ns)
            or _first_text(entry, ['updated', 'published'])
        )

        items.append(
            {
                'title': _first_text(entry, ['atom:title'], ns) or 'Untitled',
                'source': source,
                'summary': summary,
                'url': link,
                'published_at': published_dt.isoformat() if published_dt else None,
                '_published_sort': published_dt or datetime(1970, 1, 1, tzinfo=timezone.utc),
            }
        )
    return items


def parse_feed_items(feed_xml: str, feed_url: str) -> list[dict]:
    root = ET.fromstring(feed_xml)
    tag = root.tag.lower()

    if tag.endswith('rss'):
        return _parse_rss_items(root, feed_url)
    if tag.endswith('feed'):
        return _parse_atom_items(root, feed_url)
    return []


def _matches_query(item: dict, query: str | None) -> bool:
    if not query:
        return True

    haystack = ' '.join([
        item.get('title', ''),
        item.get('summary', ''),
        item.get('source', ''),
    ]).lower()
    tokens = [token for token in re.split(r'\s+', query.lower().strip()) if token]
    return all(token in haystack for token in tokens)


def aggregate_feed_items(query: str | None = None) -> tuple[list[dict], list[str]]:
    results: list[dict] = []
    failed_sources: list[str] = []
    seen_urls: set[str] = set()

    for feed_url in _feed_urls():
        try:
            feed_xml = fetch_feed_xml(feed_url)
            items = parse_feed_items(feed_xml, feed_url)
        except (ET.ParseError, URLError, TimeoutError, OSError, ValueError):
            failed_sources.append(feed_url)
            continue

        for item in items:
            url = item['url']
            if url in seen_urls:
                continue
            if not _matches_query(item, query):
                continue
            seen_urls.add(url)
            results.append(item)

    results.sort(key=lambda item: item['_published_sort'], reverse=True)
    for item in results:
        item.pop('_published_sort', None)

    return results, failed_sources


def _estimate_reading_minutes(summary: str | None) -> int:
    words = count_english_words(summary or '')
    if words <= 0:
        return 1
    return max(1, min(30, round(words / 180)))


def _import_paragraphs(summary: str | None) -> list[str]:
    if summary and summary.strip():
        return [summary.strip()]
    return ['Imported from web feed. Summary unavailable; please edit before publishing.']


def _infer_import_metadata(source: str, url: str, title: str, summary: str | None) -> tuple[str, str, int]:
    host = urlparse(url).netloc.lower()
    haystack = ' '.join([source, host, title, summary or '']).lower()

    stage_tag = 'cet6'
    level = 2
    if any(token in haystack for token in ['learning english', 'bbc learning english', 'voa learning english']):
        stage_tag = 'cet4'
        level = 1

    domain_topics = {
        'techcrunch.com': 'technology',
        'theverge.com': 'technology',
        'wired.com': 'technology',
        'arstechnica.com': 'technology',
        'espn.com': 'sports',
        'skysports.com': 'sports',
        'nature.com': 'science',
        'sciencedaily.com': 'science',
        'medicalnewstoday.com': 'health',
        'wsj.com': 'business',
        'ft.com': 'business',
        'bloomberg.com': 'business',
        'economist.com': 'business',
        'edsurge.com': 'education',
    }
    for domain, topic in domain_topics.items():
        if domain in host:
            return topic, stage_tag, level

    keyword_topics = [
        ('science', ['science', 'research', 'space', 'physics', 'biology', 'npr science']),
        ('technology', ['technology', 'tech', 'ai', 'software', 'startup', 'cyber']),
        ('business', ['business', 'economy', 'market', 'finance', 'trade', 'inflation']),
        ('education', ['education', 'school', 'student', 'teacher', 'learning', 'university']),
        ('health', ['health', 'medical', 'medicine', 'hospital', 'wellness']),
        ('sports', ['sports', 'football', 'basketball', 'soccer', 'tennis', 'olympic']),
        ('politics', ['politics', 'policy', 'government', 'election', 'congress', 'senate']),
        ('culture', ['culture', 'art', 'music', 'film', 'book', 'theater']),
    ]
    for topic, keywords in keyword_topics:
        if any(keyword in haystack for keyword in keywords):
            return topic, stage_tag, level

    return 'news', stage_tag, level


@router.get('/search')
def search_web_articles(
    q: str | None = Query(default=None, min_length=2),
    page: int = Query(default=1, ge=1),
    size: int = Query(default=10, ge=1, le=20),
) -> dict:
    feed_urls = _feed_urls()
    if not feed_urls:
        raise HTTPException(status_code=500, detail='web_article_feed_urls not configured')

    items, failed_sources = aggregate_feed_items(q)
    total = len(items)
    offset = (page - 1) * size
    paged_items = items[offset : offset + size]

    return success(
        {
            'items': paged_items,
            'page': page,
            'size': size,
            'total': total,
            'has_next': offset + len(paged_items) < total,
            'query': q or '',
            'sources_checked': len(feed_urls),
            'source_errors': failed_sources,
        }
    )


@router.post('/import')
def import_web_article(
    payload: ImportWebArticleRequest,
    _: None = Depends(require_admin_key),
    db: Session = Depends(get_db),
) -> dict:
    existing_source = db.scalar(
        select(ArticleSource).where(
            ArticleSource.source_url == payload.url,
            ArticleSource.source_type == 'rss',
        )
    )
    if existing_source is not None and not payload.force_new:
        article = db.get(Article, existing_source.article_id)
        if article is None:
            raise HTTPException(status_code=404, detail='linked article not found')
        return success(
            {
                'article_id': article.id,
                'title': article.title,
                'status': article.status,
                'source_url': article.source_url,
                'imported': False,
                'idempotent': True,
            }
        )

    paragraphs = _import_paragraphs(payload.summary)
    reading_minutes = _estimate_reading_minutes(payload.summary)
    published_dt = _parse_datetime(payload.published_at)
    inferred_topic, inferred_stage_tag, inferred_level = _infer_import_metadata(
        source=payload.source,
        url=payload.url,
        title=payload.title,
        summary=payload.summary,
    )
    resolved_topic = payload.topic or inferred_topic
    resolved_stage_tag = payload.stage_tag or inferred_stage_tag
    resolved_level = payload.level or inferred_level

    article = Article(
        title=payload.title,
        slug=None,
        stage_tag=resolved_stage_tag,
        level=resolved_level,
        topic=resolved_topic,
        summary=payload.summary,
        reading_minutes=reading_minutes,
        status='draft',
        source_url=payload.url,
        is_published=False,
        audio_status='pending',
        article_audio_url=None,
        published_at=(published_dt or datetime.now(timezone.utc)).replace(tzinfo=None),
    )
    db.add(article)
    db.flush()

    for index, paragraph in enumerate(paragraphs, start=1):
        db.add(ArticleParagraph(article_id=article.id, paragraph_index=index, text=paragraph))

    ensure_article_slug(db, article)
    ensure_article_source(
        db,
        article=article,
        source_type='rss',
        source_name=payload.source,
        source_url=payload.url,
        fetched_at=published_dt,
    )
    sync_article_content_snapshot(db, article=article, paragraphs=paragraphs)

    db.commit()
    db.refresh(article)

    return success(
        {
            'article_id': article.id,
            'title': article.title,
            'status': article.status,
            'source_url': article.source_url,
            'imported': True,
            'idempotent': False,
        }
    )
