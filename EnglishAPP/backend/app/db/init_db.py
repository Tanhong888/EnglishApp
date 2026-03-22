from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.constants import DEMO_USER_ID
from app.core.security import hash_password
from app.db.base import Base
from app.db.models import (
    Article,
    ArticleParagraph,
    Quiz,
    QuizOption,
    QuizQuestion,
    SentenceAnalysis,
    User,
    UserArticleFavorite,
    UserReadingProgress,
    UserVocabEntry,
    Word,
)
from app.db.session import engine


def init_db() -> None:
    Base.metadata.create_all(bind=engine)


def _seed_sentence_analyses(db: Session) -> None:
    has_sentence_analyses = db.scalar(select(SentenceAnalysis.id).limit(1))
    if has_sentence_analyses is not None:
        return

    target_titles = [
        "How Sleep Shapes Memory",
        "The Science of Urban Trees",
    ]
    articles = db.scalars(select(Article).where(Article.title.in_(target_titles))).all()
    article_by_title = {article.title: article for article in articles}

    templates = [
        {
            "title": "How Sleep Shapes Memory",
            "sentence_index": 1,
            "sentence": "Sleep plays a major role in memory consolidation.",
            "translation": "睡眠在记忆巩固中起重要作用。",
            "structure": "主语 + 谓语 + 介词短语",
        },
        {
            "title": "How Sleep Shapes Memory",
            "sentence_index": 2,
            "sentence": "Students with better sleep quality often perform better.",
            "translation": "睡眠质量更好的学生通常表现更好。",
            "structure": "主语 + 介词短语后置修饰 + 频率副词 + 谓语",
        },
        {
            "title": "The Science of Urban Trees",
            "sentence_index": 1,
            "sentence": "Urban trees improve air quality and mental health.",
            "translation": "城市树木能改善空气质量和心理健康。",
            "structure": "主语 + 谓语 + 并列宾语",
        },
    ]

    analyses: list[SentenceAnalysis] = []
    for item in templates:
        article = article_by_title.get(item["title"])
        if article is None:
            continue
        analyses.append(
            SentenceAnalysis(
                article_id=article.id,
                sentence_index=item["sentence_index"],
                sentence=item["sentence"],
                translation=item["translation"],
                structure=item["structure"],
            )
        )

    if not analyses:
        return

    db.add_all(analyses)
    db.commit()


def _seed_quizzes(db: Session) -> None:
    has_quiz = db.scalar(select(Quiz.id).limit(1))
    if has_quiz is not None:
        return

    target_titles = [
        "How Sleep Shapes Memory",
        "The Science of Urban Trees",
        "AI and Education Equity",
    ]
    articles = db.scalars(select(Article).where(Article.title.in_(target_titles))).all()
    article_by_title = {article.title: article for article in articles}

    quiz_bank = {
        "How Sleep Shapes Memory": [
            {
                "stem": "What does the article emphasize about sleep?",
                "options": ["Memory consolidation", "Faster city traffic", "Exam registration", "Plant genetics"],
                "answer": "Memory consolidation",
            },
            {
                "stem": "Which behavior is linked with better performance in the article?",
                "options": ["Staying up late daily", "Better sleep quality", "Skipping breakfast", "Longer social media use"],
                "answer": "Better sleep quality",
            },
            {
                "stem": "The article mainly belongs to which topic?",
                "options": ["Health", "Finance", "History", "Travel"],
                "answer": "Health",
            },
        ],
        "The Science of Urban Trees": [
            {
                "stem": "Urban trees can directly improve what?",
                "options": ["Air quality", "Wi-Fi speed", "Housing price policy", "Road tolls"],
                "answer": "Air quality",
            },
            {
                "stem": "Which benefit is mentioned for city residents?",
                "options": ["Mental health support", "Free public transport", "Higher taxes", "Longer workdays"],
                "answer": "Mental health support",
            },
            {
                "stem": "Trees in dense cities also help with:",
                "options": ["Noise reduction", "Exam grading", "Cloud storage", "Flight delays"],
                "answer": "Noise reduction",
            },
        ],
        "AI and Education Equity": [
            {
                "stem": "The article discusses AI and which social concern?",
                "options": ["Education equity", "Movie tickets", "Sports ranking", "Restaurant tips"],
                "answer": "Education equity",
            },
            {
                "stem": "In this context, equity most closely means:",
                "options": ["Fair access", "Higher difficulty", "Faster machines", "Lower attendance"],
                "answer": "Fair access",
            },
            {
                "stem": "Which group is most likely to benefit from equitable AI education tools?",
                "options": ["Underserved learners", "Only engineers", "Only teachers", "Only administrators"],
                "answer": "Underserved learners",
            },
        ],
    }

    for title, questions in quiz_bank.items():
        article = article_by_title.get(title)
        if article is None:
            continue

        quiz = Quiz(article_id=article.id)
        db.add(quiz)
        db.flush()

        for question_index, q in enumerate(questions, start=1):
            question = QuizQuestion(
                quiz_id=quiz.id,
                question_index=question_index,
                stem=q["stem"],
            )
            db.add(question)
            db.flush()

            for option_index, option_text in enumerate(q["options"], start=1):
                db.add(
                    QuizOption(
                        question_id=question.id,
                        option_index=option_index,
                        content=option_text,
                        is_correct=(option_text == q["answer"]),
                    )
                )

    db.commit()


def seed_db(db: Session) -> None:
    has_articles = db.scalar(select(Article.id).limit(1))
    if has_articles:
        _seed_sentence_analyses(db)
        _seed_quizzes(db)
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
    _seed_sentence_analyses(db)
    _seed_quizzes(db)
