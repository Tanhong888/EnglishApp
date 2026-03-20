from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "EnglishAPP API"
    app_env: str = "dev"
    api_prefix: str = "/api/v1"

    # Development default uses local sqlite for quick bootstrap.
    # Production should provide PostgreSQL via .env.
    database_url: str = "sqlite:///./englishapp.db"
    redis_url: str = "redis://localhost:6379/0"

    jwt_secret_key: str = "change_me_to_a_32_char_minimum_secret_key_2026"
    jwt_algorithm: str = "HS256"
    jwt_access_expire_minutes: int = 30
    jwt_refresh_expire_days: int = 14
    account_delete_retention_days: int = 30

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()


