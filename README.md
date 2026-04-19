# EnglishAPP

EnglishAPP is a Windows-first English graded reading app for Chinese learners. It combines a FastAPI backend with a Flutter desktop client, and focuses on helping learners stay inside the reading flow while still getting the support they need.

The current project already includes authentication, article reading, paragraph translation, quizzes, vocabulary review, admin content management, a sentence-level AI teacher, and a content ingestion pipeline for public-domain English sources.

## Highlights

- Graded English reading with article metadata such as stage, level, topic, difficulty, and reading time.
- Reading support tools including paragraph translation, sentence analysis, and vocabulary lookup.
- AI teacher actions for sentence-level translation, grammar explanation, and question answering.
- Quiz flow and vocabulary collection for turning reading into practice.
- Admin content editing tools for managing article data.
- Content ingestion pipeline that can import and normalize public-domain content from Project Gutenberg.
- Local-first development setup with SQLite by default.

## Tech Stack

- Backend: FastAPI, SQLAlchemy, Alembic, SQLite by default.
- Desktop client: Flutter for Windows.
- Optional infrastructure: PostgreSQL and Redis via Docker Compose.

## Repository Layout

```text
EnglishAPP/
  backend/        FastAPI service, database models, migrations, ingestion scripts
  desktop_app/    Flutter Windows desktop client
  README.md
  CONTRIBUTING.md
  docker-compose.yml
```

## Current Status

This repository is actively evolving and is best treated as an early open-source project rather than a production-hardened platform. The core flows are present and testable locally, and the current focus is improving developer experience, documentation, and contributor readiness.

## Quick Start

Clone the repository first:

```powershell
git clone <your-fork-or-repo-url>
cd EnglishAPP
```

### Requirements

- Windows 10 or 11 for the desktop app.
- Python 3.11 or newer.
- Flutter SDK with Windows desktop support enabled.
- Git.
- Docker Desktop if you want PostgreSQL and Redis locally.

### 1. Start the Backend

```powershell
cd backend
python -m pip install -e ".[dev]"
Copy-Item .env.example .env
python -m alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

Backend URLs:

- Health check: `http://127.0.0.1:8000/health`
- OpenAPI docs: `http://127.0.0.1:8000/docs`
- API base: `http://127.0.0.1:8000/api/v1`

Notes:

- The default local database is SQLite, so PostgreSQL is not required for the first run.
- Demo data is seeded in development when `SEED_DEMO_DATA=true`.

### 2. Start the Desktop App

```powershell
flutter config --enable-windows-desktop
flutter doctor

cd desktop_app
flutter pub get
flutter run -d windows
```

The desktop client currently points to `http://127.0.0.1:8000/api/v1`, so keep the backend on port `8000` unless you also update the client configuration.

### 3. Use the Demo Account

- Email: `demo@englishapp.dev`
- Password: `Passw0rd!`

## AI Teacher

The reading page includes an AI teacher panel for sentence-level help:

- `translate`: natural Chinese translation plus reading hints.
- `grammar`: structure-focused explanation.
- `qa`: ask a custom question about the selected sentence.

By default, local development uses a mock provider, so the feature is usable even without a model API key.

If you want to connect a real model service, add these values to `backend/.env` and restart the backend:

```env
AI_TEACHER_PROVIDER=openai
AI_TEACHER_API_KEY=your_api_key
AI_TEACHER_BASE_URL=https://api.openai.com/v1
AI_TEACHER_MODEL=gpt-5-mini
AI_TEACHER_TIMEOUT_SECONDS=25
```

## Content Ingestion

The backend can import public-domain English content and normalize it into the app's article model.

Example commands:

```powershell
cd backend
python scripts/import_content.py latest --source project_gutenberg --limit 3 --max-candidates 30
python scripts/import_content.py url --url https://www.gutenberg.org/ebooks/1080
python scripts/import_content.py tasks --limit 10
```

The current first-party ingestion source is Project Gutenberg.

## Optional Infrastructure

If you want PostgreSQL and Redis locally, start them from the repository root:

```powershell
docker compose up -d
```

Default ports:

- PostgreSQL: `5432`
- Redis: `6379`

SQLite is still the recommended default for the first local run.

## Testing

### Backend

```powershell
cd backend
python -m pytest tests -q
```

### Desktop

```powershell
cd desktop_app
flutter analyze
flutter test
```

## Documentation Map

These repository docs are useful if you want to go deeper:

- `TECH_DESIGN.md`: implementation details and system behavior.
- `APP_UI_ARCH.md`: desktop UI architecture notes.
- `组件安装说明.md`: Windows-oriented installation guide.
- `阅读页AI老师PRD.md`: AI teacher product scope and acceptance criteria.
- `PROJECT_GAP_ANALYSIS.md`: current gaps and open improvement areas.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

Useful contribution areas:

- Bug fixes and test coverage.
- Desktop UX improvements.
- Better setup automation and developer experience.
- Documentation and onboarding.
- More ingestion sources and reading tools.

## License

This project is released under the [MIT License](LICENSE).
