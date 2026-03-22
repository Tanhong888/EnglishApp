from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = 'EnglishAPP API'
    app_env: str = 'dev'
    api_prefix: str = '/api/v1'

    # Development default uses local sqlite for quick bootstrap.
    # Production should provide PostgreSQL via .env.
    database_url: str = 'sqlite:///./englishapp.db'
    redis_url: str = 'redis://localhost:6379/0'

    jwt_secret_key: str = 'change_me_to_a_32_char_minimum_secret_key_2026'
    jwt_algorithm: str = 'HS256'
    jwt_access_expire_minutes: int = 30
    jwt_refresh_expire_days: int = 14
    account_delete_retention_days: int = 30

    sentry_dsn: str = ''
    sentry_traces_sample_rate: float = 0.0
    security_hsts_enabled: bool = False
    web_article_feed_urls: str = (
        'https://feeds.bbci.co.uk/news/world/rss.xml,'
        'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml,'
        'https://feeds.bbci.co.uk/news/technology/rss.xml,'
        'https://feeds.npr.org/1001/rss.xml,'
        'https://feeds.npr.org/1019/rss.xml'
    )
    web_article_request_timeout_seconds: int = 8

    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')


settings = Settings()
