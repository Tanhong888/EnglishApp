"""initial schema

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-03-20
"""

from alembic import op
import sqlalchemy as sa


revision = "0001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("nickname", sa.String(length=128), nullable=False),
        sa.Column("target", sa.String(length=32), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email"),
    )

    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("token_jti", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("replaced_by_jti", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_jti"),
    )
    op.create_index(op.f("ix_refresh_tokens_user_id"), "refresh_tokens", ["user_id"], unique=False)

    op.create_table(
        "articles",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("stage_tag", sa.String(length=32), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("topic", sa.String(length=64), nullable=False),
        sa.Column("reading_minutes", sa.Integer(), nullable=False),
        sa.Column("is_completed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_published", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("audio_status", sa.String(length=32), nullable=False, server_default="pending"),
        sa.Column("article_audio_url", sa.String(length=1024), nullable=True),
        sa.Column("published_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )

    op.create_table(
        "words",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("lemma", sa.String(length=128), nullable=False),
        sa.Column("phonetic", sa.String(length=128), nullable=True),
        sa.Column("pos", sa.String(length=32), nullable=True),
        sa.Column("meaning_cn", sa.String(length=512), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("lemma"),
    )

    op.create_table(
        "article_paragraphs",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("article_id", sa.Integer(), nullable=False),
        sa.Column("paragraph_index", sa.Integer(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(["article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("article_id", "paragraph_index", name="uq_article_paragraph_index"),
    )

    op.create_table(
        "user_article_favorites",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("article_id", sa.Integer(), nullable=False),
        sa.Column("is_favorited", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("favorited_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("unfavorited_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "article_id", name="uq_user_article_favorite"),
    )
    op.create_index(op.f("ix_user_article_favorites_user_id"), "user_article_favorites", ["user_id"], unique=False)

    op.create_table(
        "user_reading_progress",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("article_id", sa.Integer(), nullable=False),
        sa.Column("paragraph_index", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("last_read_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "article_id", name="uq_user_article_progress"),
    )
    op.create_index(op.f("ix_user_reading_progress_user_id"), "user_reading_progress", ["user_id"], unique=False)

    op.create_table(
        "user_vocab_entries",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("word_id", sa.Integer(), nullable=False),
        sa.Column("source_article_id", sa.Integer(), nullable=False),
        sa.Column("mastered", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["source_article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["word_id"], ["words.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "word_id", "source_article_id", name="uq_user_word_source"),
    )
    op.create_index(op.f("ix_user_vocab_entries_user_id"), "user_vocab_entries", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_user_vocab_entries_user_id"), table_name="user_vocab_entries")
    op.drop_table("user_vocab_entries")
    op.drop_index(op.f("ix_user_reading_progress_user_id"), table_name="user_reading_progress")
    op.drop_table("user_reading_progress")
    op.drop_index(op.f("ix_user_article_favorites_user_id"), table_name="user_article_favorites")
    op.drop_table("user_article_favorites")
    op.drop_table("article_paragraphs")
    op.drop_table("words")
    op.drop_table("articles")
    op.drop_index(op.f("ix_refresh_tokens_user_id"), table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
    op.drop_table("users")
