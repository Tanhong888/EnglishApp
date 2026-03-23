"""add article content metadata and user-scoped completion

Revision ID: 0006_article_content_metadata
Revises: 0005_analytics_events
Create Date: 2026-03-23
"""

from __future__ import annotations

import re

from alembic import op
import sqlalchemy as sa


revision = '0006_article_content_metadata'
down_revision = '0005_analytics_events'
branch_labels = None
depends_on = None


articles_table = sa.table(
    'articles',
    sa.column('id', sa.Integer()),
    sa.column('title', sa.String()),
    sa.column('reading_minutes', sa.Integer()),
    sa.column('is_published', sa.Boolean()),
    sa.column('is_completed', sa.Boolean()),
    sa.column('slug', sa.String()),
    sa.column('summary', sa.Text()),
    sa.column('status', sa.String()),
)

article_paragraphs_table = sa.table(
    'article_paragraphs',
    sa.column('id', sa.Integer()),
    sa.column('article_id', sa.Integer()),
    sa.column('paragraph_index', sa.Integer()),
    sa.column('text', sa.Text()),
)

article_contents_table = sa.table(
    'article_contents',
    sa.column('id', sa.Integer()),
    sa.column('article_id', sa.Integer()),
    sa.column('version', sa.Integer()),
    sa.column('content_text', sa.Text()),
    sa.column('word_count', sa.Integer()),
    sa.column('estimated_reading_minutes', sa.Integer()),
)

article_sources_table = sa.table(
    'article_sources',
    sa.column('id', sa.Integer()),
    sa.column('article_id', sa.Integer()),
    sa.column('source_type', sa.String()),
    sa.column('source_name', sa.String()),
    sa.column('source_url', sa.String()),
)

user_reading_progress_table = sa.table(
    'user_reading_progress',
    sa.column('id', sa.Integer()),
    sa.column('article_id', sa.Integer()),
    sa.column('paragraph_index', sa.Integer()),
    sa.column('progress_percent', sa.Float()),
    sa.column('completed_at', sa.DateTime()),
    sa.column('last_read_at', sa.DateTime()),
)


def _slugify(title: str) -> str:
    slug = re.sub(r'[^a-z0-9]+', '-', (title or '').strip().lower())
    return slug.strip('-') or 'article'


def _word_count(text: str) -> int:
    return len(re.findall(r'[A-Za-z]+', text or ''))


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    article_columns = {column['name'] for column in inspector.get_columns('articles')}
    reading_columns = {column['name'] for column in inspector.get_columns('user_reading_progress')}
    table_names = set(inspector.get_table_names())
    article_indexes = {index['name'] for index in inspector.get_indexes('articles')}

    if 'slug' not in article_columns:
        op.add_column('articles', sa.Column('slug', sa.String(length=255), nullable=True))
    if 'summary' not in article_columns:
        op.add_column('articles', sa.Column('summary', sa.Text(), nullable=True))
    if 'status' not in article_columns:
        op.add_column('articles', sa.Column('status', sa.String(length=32), nullable=True))
    if 'source_url' not in article_columns:
        op.add_column('articles', sa.Column('source_url', sa.String(length=1024), nullable=True))
    if 'ix_articles_slug' not in article_indexes:
        op.create_index('ix_articles_slug', 'articles', ['slug'], unique=True)

    if 'article_contents' not in table_names:
        op.create_table(
            'article_contents',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('article_id', sa.Integer(), nullable=False),
            sa.Column('version', sa.Integer(), nullable=False),
            sa.Column('content_text', sa.Text(), nullable=False),
            sa.Column('word_count', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('estimated_reading_minutes', sa.Integer(), nullable=False, server_default='1'),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.ForeignKeyConstraint(['article_id'], ['articles.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('article_id', 'version', name='uq_article_content_version'),
        )
        op.create_index(op.f('ix_article_contents_article_id'), 'article_contents', ['article_id'], unique=False)

    if 'article_sources' not in table_names:
        op.create_table(
            'article_sources',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('article_id', sa.Integer(), nullable=False),
            sa.Column('source_type', sa.String(length=32), nullable=False),
            sa.Column('source_name', sa.String(length=255), nullable=True),
            sa.Column('source_url', sa.String(length=1024), nullable=True),
            sa.Column('author', sa.String(length=255), nullable=True),
            sa.Column('publisher', sa.String(length=255), nullable=True),
            sa.Column('external_id', sa.String(length=255), nullable=True),
            sa.Column('fetched_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.ForeignKeyConstraint(['article_id'], ['articles.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index(op.f('ix_article_sources_article_id'), 'article_sources', ['article_id'], unique=False)

    if 'progress_percent' not in reading_columns:
        op.add_column('user_reading_progress', sa.Column('progress_percent', sa.Float(), nullable=True))
    if 'completed_at' not in reading_columns:
        op.add_column('user_reading_progress', sa.Column('completed_at', sa.DateTime(), nullable=True))

    articles = bind.execute(
        sa.select(articles_table.c.id, articles_table.c.title, articles_table.c.reading_minutes, articles_table.c.is_published)
        .order_by(articles_table.c.id.asc())
    ).fetchall()
    seen_slugs: set[str] = set()
    for article in articles:
        paragraphs = bind.execute(
            sa.select(article_paragraphs_table.c.text)
            .where(article_paragraphs_table.c.article_id == article.id)
            .order_by(article_paragraphs_table.c.paragraph_index.asc(), article_paragraphs_table.c.id.asc())
        ).fetchall()
        paragraph_texts = [row.text.strip() for row in paragraphs if row.text and row.text.strip()]
        summary = None
        if paragraph_texts:
            summary_text = re.sub(r'\s+', ' ', ' '.join(paragraph_texts)).strip()
            summary = summary_text[:240].rstrip()
            if len(summary_text) > len(summary):
                summary = f'{summary}...'

            existing_snapshot = bind.execute(
                sa.select(article_contents_table.c.id).where(article_contents_table.c.article_id == article.id).limit(1)
            ).fetchone()
            if existing_snapshot is None:
                content_text = '\n\n'.join(paragraph_texts)
                bind.execute(
                    article_contents_table.insert().values(
                        article_id=article.id,
                        version=1,
                        content_text=content_text,
                        word_count=_word_count(content_text),
                        estimated_reading_minutes=article.reading_minutes or 1,
                    )
                )

        slug = _slugify(article.title)
        if slug in seen_slugs:
            slug = f'{slug}-{article.id}'
        seen_slugs.add(slug)

        bind.execute(
            articles_table.update()
            .where(articles_table.c.id == article.id)
            .values(
                slug=slug,
                summary=summary,
                status='published' if article.is_published else 'draft',
            )
        )

        existing_source = bind.execute(
            sa.select(article_sources_table.c.id).where(article_sources_table.c.article_id == article.id).limit(1)
        ).fetchone()
        if existing_source is None:
            bind.execute(
                article_sources_table.insert().values(
                    article_id=article.id,
                    source_type='legacy',
                    source_name='legacy_bootstrap',
                    source_url=None,
                )
            )

    progress_rows = bind.execute(
        sa.select(
            user_reading_progress_table.c.id,
            user_reading_progress_table.c.article_id,
            user_reading_progress_table.c.paragraph_index,
            user_reading_progress_table.c.last_read_at,
            articles_table.c.is_completed,
        ).select_from(
            user_reading_progress_table.join(articles_table, articles_table.c.id == user_reading_progress_table.c.article_id)
        )
    ).fetchall()

    paragraph_counts = {
        row.article_id: row.count_value
        for row in bind.execute(
            sa.select(
                article_paragraphs_table.c.article_id,
                sa.func.count(article_paragraphs_table.c.id).label('count_value'),
            )
            .group_by(article_paragraphs_table.c.article_id)
        ).fetchall()
    }

    for row in progress_rows:
        paragraph_count = paragraph_counts.get(row.article_id, 0)
        if paragraph_count > 0:
            normalized_index = min(max(row.paragraph_index or 1, 1), paragraph_count)
            progress_percent = round((normalized_index / paragraph_count) * 100, 2)
            completed_at = row.last_read_at if normalized_index >= paragraph_count else None
        else:
            normalized_index = max(row.paragraph_index or 1, 1)
            progress_percent = 0.0
            completed_at = None

        if row.is_completed:
            progress_percent = 100.0
            completed_at = completed_at or row.last_read_at

        bind.execute(
            user_reading_progress_table.update()
            .where(user_reading_progress_table.c.id == row.id)
            .values(
                paragraph_index=normalized_index,
                progress_percent=progress_percent,
                completed_at=completed_at,
            )
        )


def downgrade() -> None:
    op.drop_column('user_reading_progress', 'completed_at')
    op.drop_column('user_reading_progress', 'progress_percent')

    op.drop_index(op.f('ix_article_sources_article_id'), table_name='article_sources')
    op.drop_table('article_sources')

    op.drop_index(op.f('ix_article_contents_article_id'), table_name='article_contents')
    op.drop_table('article_contents')

    op.drop_index('ix_articles_slug', table_name='articles')
    op.drop_column('articles', 'source_url')
    op.drop_column('articles', 'status')
    op.drop_column('articles', 'summary')
    op.drop_column('articles', 'slug')
