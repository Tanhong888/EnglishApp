from __future__ import annotations

import re
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from html import unescape
from urllib.error import URLError
from urllib.request import urlopen
from xml.etree import ElementTree as ET

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.auth import require_admin_user
from app.core.config import settings
from app.core.response import success
from app.db.article_content_sync import ensure_article_slug, ensure_article_source, sync_article_content_snapshot
from app.db.models import Article, ArticleParagraph, User
from app.db.session import get_db

router = APIRouter()
ATOM_NS = {'atom': 'http://www.w3.org/2005/Atom'}
HTML_TAG_RE = re.compile(r'<[^>]+>')
WHITESPACE_RE = re.compile(r'\s+')


class WebArticleImportRequest(BaseModel):
    title: str
    url: str
    source: str
    summary: str
    published_at: datetime
    stage_tag: str | None = None
    level: int | None = None
    topic: str | None = None


def fetch_feed_xml(url: str) -> str:
    with urlopen(url, timeout=settings.web_article_request_timeout_seconds) as response:
        return response.read().decode('utf-8', errors='ignore')


def _clean_text(value: str | None) -> str:
    if not value:
        return ''
    text = unescape(value)
    text = HTML_TAG_RE.sub(' ', text)
    text = WHITESPACE_RE.sub(' ', text)
    return text.strip()


def _feed_urls() -> list[str]:
    return [item.strip() for item in settings.web_article_feed_urls.split(',') if item.strip()]


def _parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.strip()
    if not text:
        return None
    try:
        if text.endswith('Z'):
            return datetime.fromisoformat(text.replace('Z', '+00:00'))
        return datetime.fromisoformat(text)
    except ValueError:
        try:
            return parsedate_to_datetime(text)
        except (TypeError, ValueError):
            return None


def _rss_entries(root: ET.Element) -> list[dict]:
    channel = root.find('channel')
    if channel is None:
        return []
    source = _clean_text(channel.findtext('title')) or 'Unknown Source'
    items: list[dict] = []
    for item in channel.findall('item'):
        items.append(
            {
                'title': _clean_text(item.findtext('title')),
                'url': (item.findtext('link') or '').strip(),
                'summary': _clean_text(item.findtext('description')),
                'published_at': _parse_datetime(item.findtext('pubDate')),
                'source': source,
            }
        )
    return items


def _atom_link_href(entry: ET.Element) -> str:
    fallback = ''
    for link in entry.findall('atom:link', ATOM_NS):
        href = link.attrib.get('href', '').strip()
        rel = (link.attrib.get('rel') or 'alternate').strip().lower()
        if not href:
            continue
        if fallback == '':
            fallback = href
        if rel in {'', 'alternate'}:
            return href
    return fallback


def _atom_entries(root: ET.Element) -> list[dict]:
    source = _clean_text(root.findtext('atom:title', default='', namespaces=ATOM_NS)) or 'Unknown Source'
    items: list[dict] = []
    for entry in root.findall('atom:entry', ATOM_NS):
        summary = _clean_text(entry.findtext('atom:summary', default='', namespaces=ATOM_NS))
        if not summary:
            summary = _clean_text(entry.findtext('atom:content', default='', namespaces=ATOM_NS))
        items.append(
            {
                'title': _clean_text(entry.findtext('atom:title', default='', namespaces=ATOM_NS)),
                'url': _atom_link_href(entry),
                'summary': summary,
                'published_at': _parse_datetime(entry.findtext('atom:updated', default='', namespaces=ATOM_NS)),
                'source': source,
            }
        )
    return items


def _collect_feed_entries() -> tuple[list[dict], list[str]]:
    entries: list[dict] = []
    errors: list[str] = []
    seen_urls: set[str] = set()

    for url in _feed_urls():
        try:
            xml_text = fetch_feed_xml(url)
            root = ET.fromstring(xml_text)
            if root.tag.endswith('feed'):
                feed_items = _atom_entries(root)
            else:
                feed_items = _rss_entries(root)
            for item in feed_items:
                item_url = item['url']
                if not item_url or item_url in seen_urls:
                    continue
                seen_urls.add(item_url)
                entries.append(item)
        except (ET.ParseError, OSError, URLError):
            errors.append(url)

    entries.sort(key=lambda item: item['published_at'] or datetime.min.replace(tzinfo=UTC), reverse=True)
    return entries, errors


def _infer_defaults(source: str, url: str) -> tuple[str, str, int]:
    text = f'{source} {url}'.lower()
    if 'techcrunch' in text or 'technology' in text or 'tech' in text:
        return 'technology', 'cet6', 2
    if 'science' in text:
        return 'science', 'cet6', 2
    if 'education' in text or 'school' in text:
        return 'education', 'cet6', 2
    return 'news', 'cet6', 2


@router.get('/search')
def search_web_articles(
    q: str | None = Query(default=None, min_length=1, max_length=100),
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, ge=1, le=50),
) -> dict:
    entries, errors = _collect_feed_entries()
    if q:
        keyword = q.strip().lower()
        entries = [
            item for item in entries if keyword in item['title'].lower() or keyword in item['summary'].lower() or keyword in item['source'].lower()
        ]

    total = len(entries)
    start = (page - 1) * size
    items = entries[start:start + size]
    return success(
        {
            'items': [
                {
                    'title': item['title'],
                    'url': item['url'],
                    'summary': item['summary'],
                    'source': item['source'],
                    'published_at': item['published_at'].astimezone(UTC).isoformat() if item['published_at'] else None,
                }
                for item in items
            ],
            'page': page,
            'size': size,
            'total': total,
            'has_next': start + len(items) < total,
            'sources_checked': len(_feed_urls()),
            'source_errors': errors,
        }
    )


@router.post('/import')
def import_web_article(
    payload: WebArticleImportRequest,
    _: User = Depends(require_admin_user),
    db: Session = Depends(get_db),
) -> dict:
    title = _clean_text(payload.title)
    source = _clean_text(payload.source)
    summary = _clean_text(payload.summary)
    source_url = payload.url.strip()
    published_at = payload.published_at if payload.published_at.tzinfo else payload.published_at.replace(tzinfo=UTC)

    if not title or not source or not source_url:
        raise HTTPException(status_code=422, detail='invalid_web_article_payload')

    existing = db.scalar(select(Article).where(Article.source_url == source_url))
    if existing is not None:
        return success({'article_id': existing.id, 'imported': False, 'idempotent': True})

    inferred_topic, inferred_stage, inferred_level = _infer_defaults(source, source_url)
    stage_tag = payload.stage_tag or inferred_stage
    level = payload.level or inferred_level
    topic = payload.topic or inferred_topic
    paragraph = summary or title
    reading_minutes = max(1, len(paragraph.split()) // 180 + 1)

    article = Article(
        title=title,
        stage_tag=stage_tag,
        level=level,
        topic=topic,
        summary=summary,
        reading_minutes=reading_minutes,
        status='draft',
        source_url=source_url,
        is_published=False,
        audio_status='pending',
        published_at=published_at.astimezone(UTC).replace(tzinfo=None),
    )
    db.add(article)
    db.flush()
    db.add(ArticleParagraph(article_id=article.id, paragraph_index=1, text=paragraph))
    ensure_article_slug(db, article)
    ensure_article_source(db, article=article, source_type='rss', source_name=source, source_url=source_url)
    sync_article_content_snapshot(db, article=article, paragraphs=[paragraph])
    db.commit()
    return success({'article_id': article.id, 'imported': True, 'idempotent': False})
