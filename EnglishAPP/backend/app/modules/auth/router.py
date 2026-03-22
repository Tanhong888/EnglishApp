from collections import deque
from datetime import datetime, timedelta, timezone
from threading import Lock
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.response import success
from app.core.security import create_access_token, create_refresh_token, decode_token, hash_password, verify_password
from app.db.models import RefreshToken, User
from app.db.session import get_db

router = APIRouter()

AUTH_LOGIN_LIMIT_PER_MINUTE = 120
AUTH_LOGIN_WINDOW_SECONDS = 60
_login_rate_limit_lock = Lock()
_login_request_timestamps: dict[str, deque[datetime]] = {}


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


def reset_auth_login_rate_limit_state_for_test() -> None:
    with _login_rate_limit_lock:
        _login_request_timestamps.clear()


def _login_rate_limit_keys(payload: LoginRequest, request: Request) -> list[str]:
    client_host = request.client.host if request.client else 'unknown'
    normalized_email = payload.email.strip().lower()
    return [f'ip:{client_host}', f'ip_email:{client_host}:{normalized_email}']


def _enforce_login_rate_limit(keys: list[str], now: datetime | None = None) -> None:
    current_time = now or datetime.now(timezone.utc)
    window_start = current_time - timedelta(seconds=AUTH_LOGIN_WINDOW_SECONDS)

    with _login_rate_limit_lock:
        for key in keys:
            timestamps = _login_request_timestamps.setdefault(key, deque())
            while timestamps and timestamps[0] <= window_start:
                timestamps.popleft()

            if len(timestamps) >= AUTH_LOGIN_LIMIT_PER_MINUTE:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail='auth_login_rate_limited',
                )

        for key in keys:
            _login_request_timestamps.setdefault(key, deque()).append(current_time)


def serialize_user(user: User) -> dict:
    return {
        'id': user.id,
        'email': user.email,
        'nickname': user.nickname,
        'target': user.target,
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
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)) -> dict:
    _enforce_login_rate_limit(_login_rate_limit_keys(payload, request))

    user = db.scalar(select(User).where(User.email == payload.email))
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='invalid_credentials')
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='user_disabled')

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

    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='user_not_found')

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
