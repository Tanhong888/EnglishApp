from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.constants import DEMO_USER_ID
from app.core.security import hash_password
from app.db.base import Base
from app.db.models import Article, ArticleParagraph, User, UserArticleFavorite, UserReadingProgress, UserVocabEntry, Word
from app.db.session import engine


def init_db() -> None:
    Base.metadata.create_all(bind=engine)


def seed_db(db: Session) -> None:
    has_articles = db.scalar(select(Article.id).limit(1))
    if has_articles:
        return

    demo_user = User(
        id=DEMO_USER_ID,
        email="demo@englishapp.dev",
        password_hash=hash_password("Passw0rd!"),
        nickname="demo_user",
        target="cet4",
        is_active=True,
    )
    db.add(demo_user)

    articles = [
        Article(
            title="How Sleep Shapes Memory",
            stage_tag="cet4",
            level=1,
            topic="health",
            reading_minutes=6,
            audio_status="processing",
        ),
        Article(
            title="The Science of Urban Trees",
            stage_tag="cet6",
            level=2,
            topic="environment",
            reading_minutes=8,
            is_completed=True,
            audio_status="ready",
            article_audio_url="https://example.com/audio-2.mp3",
        ),
        Article(
            title="AI and Education Equity",
            stage_tag="kaoyan",
            level=3,
            topic="education",
            reading_minutes=9,
            audio_status="failed",
        ),
    ]
    db.add_all(articles)
    db.flush()

    paragraphs = [
        ArticleParagraph(article_id=articles[0].id, paragraph_index=1, text="Sleep plays a major role in memory consolidation."),
        ArticleParagraph(article_id=articles[0].id, paragraph_index=2, text="Students with better sleep quality often perform better."),
        ArticleParagraph(article_id=articles[1].id, paragraph_index=1, text="Urban trees improve air quality and mental health."),
        ArticleParagraph(article_id=articles[1].id, paragraph_index=2, text="They also reduce noise, cool neighborhoods, and support biodiversity in dense cities."),
    ]
    db.add_all(paragraphs)

    words = [
        Word(lemma="consolidate", phonetic="kənˈsɑːlɪdeɪt", pos="vt.", meaning_cn="巩固"),
        Word(lemma="equity", phonetic="ˈekwəti", pos="n.", meaning_cn="公平"),
    ]
    db.add_all(words)
    db.flush()

    db.add_all(
        [
            UserReadingProgress(user_id=DEMO_USER_ID, article_id=articles[1].id, paragraph_index=2),
            UserReadingProgress(user_id=DEMO_USER_ID, article_id=articles[0].id, paragraph_index=1),
            UserArticleFavorite(user_id=DEMO_USER_ID, article_id=articles[0].id, is_favorited=True),
            UserVocabEntry(user_id=DEMO_USER_ID, word_id=words[0].id, source_article_id=articles[0].id, mastered=False),
            UserVocabEntry(user_id=DEMO_USER_ID, word_id=words[0].id, source_article_id=articles[1].id, mastered=False),
            UserVocabEntry(user_id=DEMO_USER_ID, word_id=words[1].id, source_article_id=articles[2].id, mastered=True),
        ]
    )

    db.commit()
