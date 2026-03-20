from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.response import success
from app.core.security import create_access_token, create_refresh_token, decode_token, hash_password, verify_password
from app.db.models import RefreshToken, User
from app.db.session import get_db

router = APIRouter()


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=64)
    nickname: str | None = Field(default=None, min_length=2, max_length=24)
    target: str | None = Field(default=None)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


def serialize_user(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "nickname": user.nickname,
        "target": user.target,
    }


@router.post('/register')
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> dict:
    exists = db.scalar(select(User).where(User.email == payload.email))
    if exists is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='email_already_registered')

    user = User(
        email=payload.email,
        password_hash=hash_password(payload.password),
        nickname=payload.nickname or payload.email.split('@')[0],
        target=payload.target,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return success(serialize_user(user))


@router.post('/login')
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> dict:
    user = db.scalar(select(User).where(User.email == payload.email))
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='invalid_credentials')

    access_token = create_access_token(user.id)
    refresh_token, jti, expires_at = create_refresh_token(user.id)

    db.add(RefreshToken(user_id=user.id, token_jti=jti, expires_at=expires_at.replace(tzinfo=None)))
    db.commit()

    return success(
        {
            'access_token': access_token,
            'refresh_token': refresh_token,
            'token_type': 'bearer',
            'user': serialize_user(user),
        }
    )


@router.post('/refresh')
def refresh_token(payload: RefreshRequest, db: Session = Depends(get_db)) -> dict:
    token_payload = decode_token(payload.refresh_token, expected_type='refresh')
    user_id = int(token_payload.get('sub', 0))
    jti = token_payload.get('jti')
    if not jti:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='invalid_refresh_token')

    token_row = db.scalar(select(RefreshToken).where(RefreshToken.token_jti == jti, RefreshToken.user_id == user_id))
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if token_row is None or token_row.revoked_at is not None or token_row.expires_at < now:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='refresh_token_revoked')

    new_jti = str(uuid4())
    token_row.revoked_at = now
    token_row.replaced_by_jti = new_jti

    new_refresh_token, _, new_expires_at = create_refresh_token(user_id=user_id, jti=new_jti)
    db.add(RefreshToken(user_id=user_id, token_jti=new_jti, expires_at=new_expires_at.replace(tzinfo=None)))

    access_token = create_access_token(user_id)
    db.commit()

    return success(
        {
            'access_token': access_token,
            'refresh_token': new_refresh_token,
            'token_type': 'bearer',
            'old_refresh_token_revoked': True,
        }
    )


@router.post('/logout')
def logout(payload: RefreshRequest, db: Session = Depends(get_db)) -> dict:
    token_payload = decode_token(payload.refresh_token, expected_type='refresh')
    user_id = int(token_payload.get('sub', 0))
    jti = token_payload.get('jti')

    token_row = db.scalar(select(RefreshToken).where(RefreshToken.token_jti == jti, RefreshToken.user_id == user_id))
    if token_row is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='refresh_token_not_found')

    token_row.revoked_at = datetime.now(timezone.utc)
    db.commit()

    return success({'revoked': True})

