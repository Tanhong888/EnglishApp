from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.constants import DEMO_USER_ID
from app.core.security import hash_password
from app.db.base import Base
from app.db.article_content_sync import (
    ensure_article_slug,
    ensure_article_source,
    summarize_paragraphs,
    sync_article_content_snapshot,
    sync_reading_progress_completion,
)
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

DEMO_ARTICLE_SPECS = [
    {
        'title': 'How Sleep Shapes Memory',
        'stage_tag': 'cet4',
        'level': 1,
        'topic': 'health',
        'reading_minutes': 6,
        'is_completed': False,
        'audio_status': 'processing',
        'article_audio_url': None,
        'paragraphs': [
            'Sleep is not simply a passive state of rest. During sleep, the brain actively organizes information gathered during the day and strengthens important memories.',
            'Researchers often describe this process as memory consolidation. Facts, vocabulary, and problem-solving strategies can become easier to recall after a full night of high-quality sleep.',
            'For students, this means that study time and sleep time work together rather than compete with each other. Staying up late may create the feeling of working harder, but it can reduce the brain\'s ability to store new knowledge efficiently.',
            'In daily life, consistent sleep habits are just as important as long sleep duration. Going to bed at regular times, limiting screen use before sleep, and creating a calm environment can all support better learning performance.',
        ],
    },
    {
        'title': 'The Science of Urban Trees',
        'stage_tag': 'cet6',
        'level': 2,
        'topic': 'environment',
        'reading_minutes': 8,
        'is_completed': True,
        'audio_status': 'ready',
        'article_audio_url': 'https://example.com/audio-2.mp3',
        'paragraphs': [
            'Urban trees improve air quality by capturing dust and reducing some pollutants near busy roads. Their leaves and branches also provide shade that lowers surface temperatures in hot neighborhoods.',
            'Scientists have found that green streets are linked to better mental health. People who live near trees often report lower stress levels and a stronger sense of comfort in daily life.',
            'Trees can also reduce noise and support biodiversity. Even small pockets of urban greenery may become habitats for birds, insects, and other forms of life that would otherwise disappear from dense cities.',
            'Because land in large cities is limited, planning where to place trees matters. Successful projects usually balance environmental benefits, public safety, and long-term maintenance costs.',
        ],
    },
    {
        'title': 'AI and Education Equity',
        'stage_tag': 'kaoyan',
        'level': 3,
        'topic': 'education',
        'reading_minutes': 9,
        'is_completed': False,
        'audio_status': 'failed',
        'article_audio_url': None,
        'paragraphs': [
            'Artificial intelligence is entering classrooms through tutoring tools, writing assistants, and personalized learning platforms. In theory, these systems can help students receive support at the moment they need it.',
            'However, access is not distributed equally. Some learners have fast internet connections, modern devices, and teachers trained to use digital tools well, while others face technical and economic barriers every day.',
            'Education equity means more than offering the same software to everyone. It requires attention to language differences, accessibility needs, cost, teacher support, and the social context in which students learn.',
            'If AI tools are designed carefully, they may reduce gaps by giving underserved learners faster feedback and more flexible practice opportunities. If they are deployed carelessly, they may simply reproduce the same inequalities that already exist.',
        ],
    },
]

DEMO_WORD_SPECS = [
    {'lemma': 'consolidate', 'phonetic': 'kənˈsɑːlɪdeɪt', 'pos': 'vt.', 'meaning_cn': '巩固'},
    {'lemma': 'equity', 'phonetic': 'ˈekwəti', 'pos': 'n.', 'meaning_cn': '公平'},
]


def init_db() -> None:
    Base.metadata.create_all(bind=engine)



def _ensure_demo_user(db: Session) -> User:
    user = db.scalar(select(User).where(User.id == DEMO_USER_ID))
    if user is None:
        user = User(
            id=DEMO_USER_ID,
            email='demo@englishapp.dev',
            password_hash=hash_password('Passw0rd!'),
            nickname='demo_user',
            target='cet4',
            is_active=True,
        )
        db.add(user)
        db.flush()
    return user



def _upsert_demo_articles(db: Session) -> dict[str, Article]:
    titles = [spec['title'] for spec in DEMO_ARTICLE_SPECS]
    existing_articles = db.scalars(select(Article).where(Article.title.in_(titles))).all()
    article_by_title = {article.title: article for article in existing_articles}

    for spec in DEMO_ARTICLE_SPECS:
        article = article_by_title.get(spec['title'])
        if article is None:
            article = Article(
                title=spec['title'],
                slug=None,
                stage_tag=spec['stage_tag'],
                level=spec['level'],
                topic=spec['topic'],
                summary=None,
                reading_minutes=spec['reading_minutes'],
                status='published',
                source_url=None,
                is_completed=spec['is_completed'],
                audio_status=spec['audio_status'],
                article_audio_url=spec['article_audio_url'],
                is_published=True,
            )
            db.add(article)
            db.flush()
            article_by_title[article.title] = article
        else:
            article.stage_tag = spec['stage_tag']
            article.level = spec['level']
            article.topic = spec['topic']
            article.reading_minutes = spec['reading_minutes']
            article.status = 'published'
            article.is_completed = spec['is_completed']
            article.audio_status = spec['audio_status']
            article.article_audio_url = spec['article_audio_url']
            article.is_published = True

        existing_paragraphs = db.scalars(
            select(ArticleParagraph)
            .where(ArticleParagraph.article_id == article.id)
            .order_by(ArticleParagraph.paragraph_index.asc())
        ).all()
        paragraph_by_index = {paragraph.paragraph_index: paragraph for paragraph in existing_paragraphs}
        desired_indices = set()

        for paragraph_index, text in enumerate(spec['paragraphs'], start=1):
            desired_indices.add(paragraph_index)
            paragraph = paragraph_by_index.get(paragraph_index)
            if paragraph is None:
                db.add(
                    ArticleParagraph(
                        article_id=article.id,
                        paragraph_index=paragraph_index,
                        text=text,
                    )
                )
            else:
                paragraph.text = text

        for paragraph in existing_paragraphs:
            if paragraph.paragraph_index not in desired_indices:
                db.delete(paragraph)

        ensure_article_slug(db, article)
        article.summary = summarize_paragraphs(spec['paragraphs'])
        ensure_article_source(
            db,
            article=article,
            source_type='seed',
            source_name='demo_seed',
            source_url=article.source_url,
        )
        sync_article_content_snapshot(db, article=article, paragraphs=spec['paragraphs'])

    db.flush()
    return article_by_title



def _upsert_demo_words(db: Session) -> dict[str, Word]:
    lemmas = [spec['lemma'] for spec in DEMO_WORD_SPECS]
    existing_words = db.scalars(select(Word).where(Word.lemma.in_(lemmas))).all()
    word_by_lemma = {word.lemma: word for word in existing_words}

    for spec in DEMO_WORD_SPECS:
        word = word_by_lemma.get(spec['lemma'])
        if word is None:
            word = Word(**spec)
            db.add(word)
            db.flush()
            word_by_lemma[word.lemma] = word
        else:
            word.phonetic = spec['phonetic']
            word.pos = spec['pos']
            word.meaning_cn = spec['meaning_cn']

    db.flush()
    return word_by_lemma



def _ensure_demo_learning_data(db: Session, article_by_title: dict[str, Article], word_by_lemma: dict[str, Word]) -> None:
    progress_specs = [
        ('The Science of Urban Trees', 2),
        ('How Sleep Shapes Memory', 1),
    ]
    for title, paragraph_index in progress_specs:
        article = article_by_title[title]
        existing = db.scalar(
            select(UserReadingProgress).where(
                UserReadingProgress.user_id == DEMO_USER_ID,
                UserReadingProgress.article_id == article.id,
            )
        )
        if existing is None:
            existing = UserReadingProgress(
                user_id=DEMO_USER_ID,
                article_id=article.id,
                paragraph_index=paragraph_index,
            )
            db.add(existing)

        sync_reading_progress_completion(
            db,
            progress=existing,
            article=article,
            completed_at_fallback=existing.last_read_at,
        )

    favorite_article = article_by_title['How Sleep Shapes Memory']
    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == DEMO_USER_ID,
            UserArticleFavorite.article_id == favorite_article.id,
        )
    )
    if favorite is None:
        db.add(UserArticleFavorite(user_id=DEMO_USER_ID, article_id=favorite_article.id, is_favorited=True))

    vocab_specs = [
        ('consolidate', 'How Sleep Shapes Memory', False),
        ('consolidate', 'The Science of Urban Trees', False),
        ('equity', 'AI and Education Equity', True),
    ]
    for lemma, article_title, mastered in vocab_specs:
        article = article_by_title[article_title]
        word = word_by_lemma[lemma]
        entry = db.scalar(
            select(UserVocabEntry).where(
                UserVocabEntry.user_id == DEMO_USER_ID,
                UserVocabEntry.word_id == word.id,
                UserVocabEntry.source_article_id == article.id,
            )
        )
        if entry is None:
            db.add(
                UserVocabEntry(
                    user_id=DEMO_USER_ID,
                    word_id=word.id,
                    source_article_id=article.id,
                    mastered=mastered,
                )
            )



def _seed_sentence_analyses(db: Session) -> None:
    has_sentence_analyses = db.scalar(select(SentenceAnalysis.id).limit(1))
    if has_sentence_analyses is not None:
        return

    target_titles = [
        'How Sleep Shapes Memory',
        'The Science of Urban Trees',
    ]
    articles = db.scalars(select(Article).where(Article.title.in_(target_titles))).all()
    article_by_title = {article.title: article for article in articles}

    templates = [
        {
            'title': 'How Sleep Shapes Memory',
            'sentence_index': 1,
            'sentence': 'Sleep plays a major role in memory consolidation.',
            'translation': '睡眠在记忆巩固中起重要作用。',
            'structure': '主语 + 谓语 + 介词短语',
        },
        {
            'title': 'How Sleep Shapes Memory',
            'sentence_index': 2,
            'sentence': 'Students with better sleep quality often perform better.',
            'translation': '睡眠质量更好的学生通常表现更好。',
            'structure': '主语 + 介词短语后置修饰 + 频率副词 + 谓语',
        },
        {
            'title': 'The Science of Urban Trees',
            'sentence_index': 1,
            'sentence': 'Urban trees improve air quality and mental health.',
            'translation': '城市树木能改善空气质量和心理健康。',
            'structure': '主语 + 谓语 + 并列宾语',
        },
    ]

    analyses: list[SentenceAnalysis] = []
    for item in templates:
        article = article_by_title.get(item['title'])
        if article is None:
            continue
        analyses.append(
            SentenceAnalysis(
                article_id=article.id,
                sentence_index=item['sentence_index'],
                sentence=item['sentence'],
                translation=item['translation'],
                structure=item['structure'],
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
        'How Sleep Shapes Memory',
        'The Science of Urban Trees',
        'AI and Education Equity',
    ]
    articles = db.scalars(select(Article).where(Article.title.in_(target_titles))).all()
    article_by_title = {article.title: article for article in articles}

    quiz_bank = {
        'How Sleep Shapes Memory': [
            {
                'stem': 'What does the article emphasize about sleep?',
                'options': ['Memory consolidation', 'Faster city traffic', 'Exam registration', 'Plant genetics'],
                'answer': 'Memory consolidation',
            },
            {
                'stem': 'Which behavior is linked with better performance in the article?',
                'options': ['Staying up late daily', 'Better sleep quality', 'Skipping breakfast', 'Longer social media use'],
                'answer': 'Better sleep quality',
            },
            {
                'stem': 'The article mainly belongs to which topic?',
                'options': ['Health', 'Finance', 'History', 'Travel'],
                'answer': 'Health',
            },
        ],
        'The Science of Urban Trees': [
            {
                'stem': 'Urban trees can directly improve what?',
                'options': ['Air quality', 'Wi-Fi speed', 'Housing price policy', 'Road tolls'],
                'answer': 'Air quality',
            },
            {
                'stem': 'Which benefit is mentioned for city residents?',
                'options': ['Mental health support', 'Free public transport', 'Higher taxes', 'Longer workdays'],
                'answer': 'Mental health support',
            },
            {
                'stem': 'Trees in dense cities also help with:',
                'options': ['Noise reduction', 'Exam grading', 'Cloud storage', 'Flight delays'],
                'answer': 'Noise reduction',
            },
        ],
        'AI and Education Equity': [
            {
                'stem': 'The article discusses AI and which social concern?',
                'options': ['Education equity', 'Movie tickets', 'Sports ranking', 'Restaurant tips'],
                'answer': 'Education equity',
            },
            {
                'stem': 'In this context, equity most closely means:',
                'options': ['Fair access', 'Higher difficulty', 'Faster machines', 'Lower attendance'],
                'answer': 'Fair access',
            },
            {
                'stem': 'Which group is most likely to benefit from equitable AI education tools?',
                'options': ['Underserved learners', 'Only engineers', 'Only teachers', 'Only administrators'],
                'answer': 'Underserved learners',
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

        for question_index, question_spec in enumerate(questions, start=1):
            question = QuizQuestion(
                quiz_id=quiz.id,
                question_index=question_index,
                stem=question_spec['stem'],
            )
            db.add(question)
            db.flush()

            for option_index, option_text in enumerate(question_spec['options'], start=1):
                db.add(
                    QuizOption(
                        question_id=question.id,
                        option_index=option_index,
                        content=option_text,
                        is_correct=(option_text == question_spec['answer']),
                    )
                )

    db.commit()



def seed_db(db: Session) -> None:
    _ensure_demo_user(db)
    article_by_title = _upsert_demo_articles(db)
    word_by_lemma = _upsert_demo_words(db)
    _ensure_demo_learning_data(db, article_by_title, word_by_lemma)
    db.commit()
    _seed_sentence_analyses(db)
    _seed_quizzes(db)
