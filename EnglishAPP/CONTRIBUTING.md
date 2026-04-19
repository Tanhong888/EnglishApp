# Contributing to EnglishAPP

Thanks for considering a contribution.

This project is still maturing, so the most helpful contributions are the ones that keep the codebase easier to run, understand, and extend.

## Good First Contribution Areas

- Fix a clear bug in the backend or desktop client.
- Improve setup or troubleshooting documentation.
- Add or strengthen automated tests.
- Polish reading UX, admin flows, or AI teacher interactions.
- Improve content ingestion robustness or add new public-domain sources.

## Before You Start

- For small fixes, feel free to open a pull request directly.
- For larger changes, open an issue or start a discussion first so we can align on scope.
- Keep pull requests focused. Small, reviewable changes land faster than broad refactors.

## Local Setup

Clone the repository first:

```powershell
git clone <your-fork-or-repo-url>
cd EnglishAPP
```

### Backend

```powershell
cd backend
python -m pip install -e ".[dev]"
Copy-Item .env.example .env
python -m alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

Run backend tests:

```powershell
cd backend
python -m pytest tests -q
```

### Desktop App

```powershell
flutter config --enable-windows-desktop
flutter doctor

cd desktop_app
flutter pub get
flutter run -d windows
```

Run desktop checks:

```powershell
cd desktop_app
flutter analyze
flutter test
```

## Development Expectations

- Match the existing project structure and naming style instead of introducing a parallel pattern.
- Update docs when behavior, setup, commands, or environment variables change.
- Add or update tests when you change backend logic, request validation, or client behavior with a clear regression risk.
- Call out schema changes, migrations, or new environment variables in your pull request description.
- Avoid unrelated cleanups in the same pull request unless they are required to complete the change safely.

## Pull Request Checklist

- The change is scoped to one problem or feature.
- Relevant tests pass locally, or the pull request clearly explains what could not be run.
- New commands or environment variables are documented.
- UI changes include screenshots or a short video when practical.
- Database changes include an Alembic migration when needed.

## Coding Notes

- Backend targets Python 3.11+.
- Desktop code follows Flutter and Dart analyzer guidance.
- SQLite is the easiest local database for development.
- Redis and PostgreSQL are optional for first-time setup.

## What Not to Commit

- Local `.env` files.
- Database files such as `*.db`.
- Runtime logs or temporary run artifacts.
- Large unrelated formatting-only rewrites.

## Communication

- Be explicit about tradeoffs, assumptions, and any follow-up work you are leaving for later.
- If a change is intentionally incomplete, say so clearly in the pull request.
- Kind, direct feedback is encouraged.

## License

By contributing to this repository, you agree that your contributions will be licensed under the MIT License.
