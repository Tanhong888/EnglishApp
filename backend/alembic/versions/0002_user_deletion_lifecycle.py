"""add account deletion lifecycle fields

Revision ID: 0002_user_deletion_lifecycle
Revises: 0001_initial_schema
Create Date: 2026-03-20
"""

from alembic import op
import sqlalchemy as sa


revision = '0002_user_deletion_lifecycle'
down_revision = '0001_initial_schema'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('deleted_at', sa.DateTime(), nullable=True))
    op.add_column('users', sa.Column('deletion_due_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'deletion_due_at')
    op.drop_column('users', 'deleted_at')
