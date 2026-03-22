from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html import unescape
import re
from urllib.error import URLError
from urllib.request import Request, urlopen
from xml.etree import ElementTree as ET

from fastapi import APIRouter, HTTPException, Query

from app.core.config import settings
from app.core.response import success

router = APIRouter()


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
