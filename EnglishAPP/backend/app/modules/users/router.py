from fastapi import APIRouter, Depends

from app.core.auth import get_current_user
from app.core.response import success
from app.db.models import User

router = APIRouter()


@router.get('/me')
def get_current_user_profile(current_user: User = Depends(get_current_user)) -> dict:
    return success(
        {
            'id': current_user.id,
            'email': current_user.email,
            'nickname': current_user.nickname,
            'target': current_user.target,
        }
    )
