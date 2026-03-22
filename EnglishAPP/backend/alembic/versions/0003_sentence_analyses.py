"""add sentence analyses table

Revision ID: 0003_sentence_analyses
Revises: 0002_user_deletion_lifecycle
Create Date: 2026-03-21
"""

from alembic import op
import sqlalchemy as sa


revision = "0003_sentence_analyses"
down_revision = "0002_user_deletion_lifecycle"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "sentence_analyses",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("article_id", sa.Integer(), nullable=False),
        sa.Column("sentence_index", sa.Integer(), nullable=False),
        sa.Column("sentence", sa.Text(), nullable=False),
        sa.Column("translation", sa.Text(), nullable=True),
        sa.Column("structure", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("article_id", "sentence_index", name="uq_sentence_analysis_article_index"),
    )
    op.create_index(op.f("ix_sentence_analyses_article_id"), "sentence_analyses", ["article_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_sentence_analyses_article_id"), table_name="sentence_analyses")
    op.drop_table("sentence_analyses")
