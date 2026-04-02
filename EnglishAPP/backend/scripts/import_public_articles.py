from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

from sqlalchemy import select

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))

from app.db.article_content_sync import ensure_article_slug, ensure_article_source, summarize_paragraphs, sync_article_content_snapshot
from app.db.init_db import _purge_manual_test_articles
from app.db.models import Article, ArticleParagraph
from app.db.session import SessionLocal

PUBLIC_ARTICLE_SPECS = [
    {
        'title': 'How NASA Plans a Moon Launch Countdown',
        'stage_tag': 'cet6',
        'level': 2,
        'topic': 'space',
        'reading_minutes': 7,
        'source_name': 'NASA',
        'source_url': 'https://www.nasa.gov/general/nasa-releases-artemis-ii-moon-mission-launch-countdown/',
        'published_at': '2026-03-26T00:00:00',
        'paragraphs': [
            'Before Artemis II can send four astronauts around the Moon, teams at NASA must begin work long before the rocket leaves the ground. Engineers at Kennedy Space Center and at partner sites start preparing about two days before launch, and every task follows a detailed timeline.',
            'NASA explains the schedule with two clocks. L-minus measures the planned time left in the full launch-day process, while T-minus measures the time left in the final sequence that leads directly to liftoff. Built-in holds give teams time to solve problems without losing control of the overall plan.',
            'Early countdown work includes powering up Orion, checking the core stage and upper stage, activating software, and making sure communication links stay stable. Later steps focus on loading super-cold propellants safely and confirming that weather, hardware, and people are all ready for a go decision.',
            'A precise countdown matters because a moon mission depends on timing, safety, and coordination at every level. NASA uses the schedule not just to count down to launch, but to reduce risk, organize decisions, and make sure one small issue does not grow into a larger mission failure.',
        ],
    },
    {
        'title': 'What a March Heat Wave Revealed in the Southwest',
        'stage_tag': 'cet6',
        'level': 2,
        'topic': 'climate',
        'reading_minutes': 7,
        'source_name': 'NASA Earth Observatory',
        'source_url': 'https://science.nasa.gov/earth/earth-observatory/a-hot-start-to-spring-in-the-southwest/',
        'published_at': '2026-03-26T00:00:00',
        'paragraphs': [
            'In March 2026, the first official days of spring felt more like summer across much of the southwestern United States. NASA Earth Observatory reported that many places saw extreme heat, and several local records fell unusually early in the year.',
            'To show the scale of the event, NASA used a weather model to map afternoon air temperatures about two meters above the ground. The darkest red areas marked places where temperatures reached or passed 104 degrees Fahrenheit, making the heat pattern visible across the entire region instead of at only a few weather stations.',
            'Ground measurements confirmed how serious the event was. Yuma, Arizona, reached 109 degrees Fahrenheit, and several places in Arizona and California climbed even higher. The heat extended into Texas and Mexico as well, showing that the event was regional rather than local.',
            'Scientists linked the heat to a strong high-pressure system that stayed over the region for more than a week, keeping skies clear and air dry. Events like this matter because they reveal how dangerous heat can arrive earlier than many people expect, creating risks for health, water planning, and energy use.',
        ],
    },
    {
        'title': 'What Decades of Arctic Sea Ice Data Show',
        'stage_tag': 'kaoyan',
        'level': 3,
        'topic': 'environment',
        'reading_minutes': 8,
        'source_name': 'NASA Science',
        'source_url': 'https://science.nasa.gov/science-research/earth-science/climate-science/sea-ice/see-how-arctic-sea-ice-is-losing-its-bulwark-against-warming-summers/',
        'published_at': '2016-11-03T00:00:00',
        'paragraphs': [
            'Short-term events in the Arctic often attract attention, but the longer record tells the deeper story. NASA has shown that Arctic sea ice has been shrinking for decades, especially in late summer when the ice normally reaches its yearly minimum extent.',
            'The change is not only about total area. The Arctic is also losing older, thicker ice that once helped the region resist warm summers. Compared with the 1980s, much more of today\'s sea ice forms in winter and melts away again quickly, leaving the ice cover more fragile.',
            'This pattern matters because ice and open water behave very differently. Bright ice reflects sunlight back into space, while dark ocean water absorbs more energy and stores heat. When more open water appears, the region warms more easily and the next season\'s ice faces a harder recovery.',
            'For researchers, decades of satellite observations provide evidence that the Arctic is becoming less stable, not just temporarily warmer. The trend affects ecosystems, shipping, climate feedbacks, and the way scientists understand rapid environmental change in polar regions.',
        ],
    },
]


def upsert_paragraphs(db, article: Article, paragraphs: list[str]) -> None:
    existing = db.scalars(
        select(ArticleParagraph)
        .where(ArticleParagraph.article_id == article.id)
        .order_by(ArticleParagraph.paragraph_index.asc(), ArticleParagraph.id.asc())
    ).all()
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


def upsert_public_article(db, spec: dict) -> Article:
    article = db.scalar(select(Article).where(Article.source_url == spec['source_url']))
    if article is None:
        article = Article(
            title=spec['title'],
            stage_tag=spec['stage_tag'],
            level=spec['level'],
            topic=spec['topic'],
            reading_minutes=spec['reading_minutes'],
            source_url=spec['source_url'],
            status='published',
            is_completed=False,
            is_published=True,
            audio_status='pending',
            article_audio_url=None,
            published_at=datetime.fromisoformat(spec['published_at']),
        )
        db.add(article)
        db.flush()

    article.title = spec['title']
    article.stage_tag = spec['stage_tag']
    article.level = spec['level']
    article.topic = spec['topic']
    article.reading_minutes = spec['reading_minutes']
    article.status = 'published'
    article.is_published = True
    article.is_completed = False
    article.audio_status = 'pending'
    article.article_audio_url = None
    article.published_at = datetime.fromisoformat(spec['published_at'])

    upsert_paragraphs(db, article, spec['paragraphs'])
    article.summary = summarize_paragraphs(spec['paragraphs'])
    ensure_article_slug(db, article)
    ensure_article_source(
        db,
        article=article,
        source_type='public',
        source_name=spec['source_name'],
        source_url=spec['source_url'],
    )
    sync_article_content_snapshot(db, article=article, paragraphs=spec['paragraphs'])
    return article


def main() -> None:
    with SessionLocal() as db:
        _purge_manual_test_articles(db)
        articles = [upsert_public_article(db, spec) for spec in PUBLIC_ARTICLE_SPECS]
        db.commit()
        for article in articles:
            print(f'upserted: {article.id} {article.title}')


if __name__ == '__main__':
    main()

