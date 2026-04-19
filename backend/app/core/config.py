import secrets

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = 'EnglishAPP API'
    app_env: str = 'dev'
    api_prefix: str = '/api/v1'
    public_base_url: str = 'http://127.0.0.1:8000'

    # Development default uses local sqlite for quick bootstrap.
    # Production should provide PostgreSQL via .env.
    database_url: str = 'sqlite:///./englishapp.db'
    redis_url: str = 'redis://localhost:6379/0'

    # Fall back to an ephemeral dev secret when JWT_SECRET_KEY is absent so the
    # repository never ships a reusable signing key.
    jwt_secret_key: str = secrets.token_urlsafe(48)
    jwt_algorithm: str = 'HS256'
    jwt_access_expire_minutes: int = 30
    jwt_refresh_expire_days: int = 14
    account_delete_retention_days: int = 30

    sentry_dsn: str = ''
    sentry_traces_sample_rate: float = 0.0
    security_hsts_enabled: bool = False
    admin_emails: str = 'demo@englishapp.dev'
    cors_allowed_origins: str = (
        'http://127.0.0.1,'
        'http://localhost,'
        'http://127.0.0.1:3000,'
        'http://localhost:3000,'
        'http://127.0.0.1:5173,'
        'http://localhost:5173'
    )
    seed_demo_data: bool = True
    tts_worker_enabled: bool = True
    tts_worker_poll_interval_seconds: float = 0.2
    tts_processing_delay_seconds: float = 0.3
    tts_retry_base_delay_seconds: float = 0.3
    tts_max_attempts: int = 3
    tts_mock_fail_keyword: str = '[tts-fail]'
    web_article_feed_urls: str = (
        'https://www.nasa.gov/news-release/feed/,'
        'https://www.nasa.gov/news/feed/,'
        'https://science.nasa.gov/feed/earth-observatory/image-of-the-day,'
        'https://science.nasa.gov/feed/earth-observatory/natural-events'
    )
    web_article_request_timeout_seconds: int = 8

    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')


settings = Settings()


def _parse_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(',') if item.strip()]


def admin_email_set() -> set[str]:
    return {item.lower() for item in _parse_csv(settings.admin_emails)}


def cors_origin_list() -> list[str]:
    return _parse_csv(settings.cors_allowed_origins)


