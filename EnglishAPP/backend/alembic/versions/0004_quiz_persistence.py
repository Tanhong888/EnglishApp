"""add quiz persistence tables

Revision ID: 0004_quiz_persistence
Revises: 0003_sentence_analyses
Create Date: 2026-03-21
"""

from alembic import op
import sqlalchemy as sa


revision = "0004_quiz_persistence"
down_revision = "0003_sentence_analyses"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "quizzes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("article_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("article_id"),
    )

    op.create_table(
        "quiz_questions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("quiz_id", sa.Integer(), nullable=False),
        sa.Column("question_index", sa.Integer(), nullable=False),
        sa.Column("stem", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["quiz_id"], ["quizzes.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("quiz_id", "question_index", name="uq_quiz_question_index"),
    )
    op.create_index(op.f("ix_quiz_questions_quiz_id"), "quiz_questions", ["quiz_id"], unique=False)

    op.create_table(
        "quiz_options",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("question_id", sa.Integer(), nullable=False),
        sa.Column("option_index", sa.Integer(), nullable=False),
        sa.Column("content", sa.String(length=255), nullable=False),
        sa.Column("is_correct", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.ForeignKeyConstraint(["question_id"], ["quiz_questions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("question_id", "option_index", name="uq_quiz_option_index"),
    )
    op.create_index(op.f("ix_quiz_options_question_id"), "quiz_options", ["question_id"], unique=False)

    op.create_table(
        "user_quiz_attempts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("article_id", sa.Integer(), nullable=False),
        sa.Column("correct_count", sa.Integer(), nullable=False),
        sa.Column("total_count", sa.Integer(), nullable=False),
        sa.Column("accuracy", sa.Float(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_user_quiz_attempts_article_id"), "user_quiz_attempts", ["article_id"], unique=False)

    op.create_table(
        "user_quiz_answers",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("attempt_id", sa.Integer(), nullable=False),
        sa.Column("question_id", sa.Integer(), nullable=False),
        sa.Column("selected_option", sa.String(length=255), nullable=True),
        sa.Column("is_correct", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["attempt_id"], ["user_quiz_attempts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["question_id"], ["quiz_questions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("attempt_id", "question_id", name="uq_attempt_question"),
    )
    op.create_index(op.f("ix_user_quiz_answers_attempt_id"), "user_quiz_answers", ["attempt_id"], unique=False)
    op.create_index(op.f("ix_user_quiz_answers_question_id"), "user_quiz_answers", ["question_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_user_quiz_answers_question_id"), table_name="user_quiz_answers")
    op.drop_index(op.f("ix_user_quiz_answers_attempt_id"), table_name="user_quiz_answers")
    op.drop_table("user_quiz_answers")

    op.drop_index(op.f("ix_user_quiz_attempts_article_id"), table_name="user_quiz_attempts")
    op.drop_table("user_quiz_attempts")

    op.drop_index(op.f("ix_quiz_options_question_id"), table_name="quiz_options")
    op.drop_table("quiz_options")

    op.drop_index(op.f("ix_quiz_questions_quiz_id"), table_name="quiz_questions")
    op.drop_table("quiz_questions")

    op.drop_table("quizzes")
