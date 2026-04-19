"""add analytics events table

Revision ID: 0005_analytics_events
Revises: 0004_quiz_persistence
Create Date: 2026-03-22
"""

from alembic import op
import sqlalchemy as sa


revision = '0005_analytics_events'
down_revision = '0004_quiz_persistence'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'analytics_events',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('event_name', sa.String(length=64), nullable=False),
        sa.Column('article_id', sa.Integer(), nullable=True),
        sa.Column('word', sa.String(length=128), nullable=True),
        sa.Column('context_json', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_analytics_events_user_id'), 'analytics_events', ['user_id'], unique=False)
    op.create_index(op.f('ix_analytics_events_event_name'), 'analytics_events', ['event_name'], unique=False)
    op.create_index(op.f('ix_analytics_events_article_id'), 'analytics_events', ['article_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_analytics_events_article_id'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_event_name'), table_name='analytics_events')
    op.drop_index(op.f('ix_analytics_events_user_id'), table_name='analytics_events')
    op.drop_table('analytics_events')
