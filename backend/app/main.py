import logging
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import cors_origin_list, settings
from app.core.response import success
from app.core.router import api_router
from app.db.init_db import init_db, seed_db
from app.db.session import SessionLocal

logger = logging.getLogger('englishapp.api')

SECURITY_RESPONSE_HEADERS = {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=()'
}


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    if settings.seed_demo_data and settings.app_env == 'dev':
        with SessionLocal() as db:
            seed_db(db)

    if settings.sentry_dsn:
        try:
            import sentry_sdk

            sentry_sdk.init(
                dsn=settings.sentry_dsn,
                environment=settings.app_env,
                traces_sample_rate=settings.sentry_traces_sample_rate,
            )
            logger.info('Sentry initialized for env=%s', settings.app_env)
        except Exception:  # pragma: no cover - optional dependency path
            logger.exception('Sentry init failed; continuing without external tracking')

    yield



def _request_id(request: Request) -> str:
    return getattr(request.state, 'request_id', 'unknown')



def _error_payload(*, code: int, message: str, detail: object, trace_id: str) -> dict:
    return {
        'code': code,
        'message': message,
        'detail': detail,
        'data': None,
        'trace_id': trace_id,
    }


app = FastAPI(title=settings.app_name, version='0.1.0', lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origin_list(),
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


@app.middleware('http')
async def attach_request_context_and_security_headers(request: Request, call_next):
    request_id = request.headers.get('X-Request-ID') or str(uuid4())
    request.state.request_id = request_id

    response = await call_next(request)
    response.headers['X-Request-ID'] = request_id

    for key, value in SECURITY_RESPONSE_HEADERS.items():
        response.headers.setdefault(key, value)

    if settings.security_hsts_enabled:
        response.headers.setdefault('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')

    return response


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    request_id = _request_id(request)
    detail = exc.detail
    message = detail if isinstance(detail, str) else 'request_failed'

    logger.warning('http_exception request_id=%s method=%s path=%s status=%s', request_id, request.method, request.url.path, exc.status_code)

    return JSONResponse(
        status_code=exc.status_code,
        content=_error_payload(
            code=exc.status_code,
            message=message,
            detail=detail,
            trace_id=request_id,
        ),
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    request_id = _request_id(request)
    logger.warning('validation_error request_id=%s method=%s path=%s', request_id, request.method, request.url.path)

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content=_error_payload(
            code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            message='validation_error',
            detail=exc.errors(),
            trace_id=request_id,
        ),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    request_id = _request_id(request)
    logger.exception('unhandled_exception request_id=%s method=%s path=%s', request_id, request.method, request.url.path)

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=_error_payload(
            code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            message='internal_server_error',
            detail='internal_server_error',
            trace_id=request_id,
        ),
    )


@app.get('/health')
def healthcheck() -> dict:
    return success({'status': 'ok', 'env': settings.app_env})


app.include_router(api_router, prefix=settings.api_prefix)
