from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.core.config import settings
from app.core.response import success
from app.db.models import RefreshToken, User, UserArticleFavorite, UserReadingProgress, UserVocabEntry
from app.db.session import get_db

router = APIRouter()


class DeleteAccountRequest(BaseModel):
    mode: Literal['soft', 'hard'] = 'soft'


@router.get('/me')
def get_current_user_profile(current_user: User = Depends(get_current_user)) -> dict:
    return success(
        {
            'id': current_user.id,
            'email': current_user.email,
            'nickname': current_user.nickname,
            'target': current_user.target,
            'is_active': current_user.is_active,
            'deleted_at': current_user.deleted_at.isoformat() if current_user.deleted_at else None,
            'deletion_due_at': current_user.deletion_due_at.isoformat() if current_user.deletion_due_at else None,
        }
    )


@router.delete('/me')
def delete_current_user_account(
    payload: DeleteAccountRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    mode = payload.mode
    now = datetime.now(timezone.utc).replace(tzinfo=None)

    if mode == 'soft':
        current_user.is_active = False
        current_user.deleted_at = now
        current_user.deletion_due_at = now + timedelta(days=settings.account_delete_retention_days)

        token_rows = db.scalars(
            select(RefreshToken).where(RefreshToken.user_id == current_user.id, RefreshToken.revoked_at.is_(None))
        ).all()
        for token_row in token_rows:
            token_row.revoked_at = now

        db.commit()
        return success(
            {
                'deleted': True,
                'mode': 'soft',
                'retention_days': settings.account_delete_retention_days,
                'deletion_due_at': current_user.deletion_due_at.isoformat(),
                'revoked_refresh_tokens': len(token_rows),
            }
        )

    db.execute(delete(UserVocabEntry).where(UserVocabEntry.user_id == current_user.id))
    db.execute(delete(UserArticleFavorite).where(UserArticleFavorite.user_id == current_user.id))
    db.execute(delete(UserReadingProgress).where(UserReadingProgress.user_id == current_user.id))
    db.execute(delete(RefreshToken).where(RefreshToken.user_id == current_user.id))
    db.execute(delete(User).where(User.id == current_user.id))
    db.commit()

    return success({'deleted': True, 'mode': 'hard', 'retention_days': 0, 'deletion_due_at': None})
