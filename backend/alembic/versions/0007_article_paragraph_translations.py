"""add article paragraph translations

Revision ID: 0007_article_paragraph_translations
Revises: 0006_article_content_metadata
Create Date: 2026-04-06 11:10:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision = "0007_article_paragraph_translations"
down_revision = "0006_article_content_metadata"
branch_labels = None
depends_on = None


def _column_names(table_name: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {column["name"] for column in inspector.get_columns(table_name)}


def upgrade() -> None:
    if "translation" not in _column_names("article_paragraphs"):
        op.add_column("article_paragraphs", sa.Column("translation", sa.Text(), nullable=True))


def downgrade() -> None:
    if "translation" in _column_names("article_paragraphs"):
        op.drop_column("article_paragraphs", "translation")
