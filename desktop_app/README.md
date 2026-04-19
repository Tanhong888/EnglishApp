# EnglishAPP Desktop

This directory contains the Flutter Windows desktop client for EnglishAPP.

The desktop app is the main learner-facing experience in this repository. It talks to the FastAPI backend, renders reading content, and exposes features such as login, article reading, AI teacher actions, vocabulary review, quizzes, and admin content flows.

## Requirements

- Flutter SDK with Windows desktop support enabled.
- A running backend service, typically at `http://127.0.0.1:8000/api/v1`.

## Local Run

From the repository root:

```powershell
flutter config --enable-windows-desktop
flutter doctor

cd desktop_app
flutter pub get
flutter run -d windows
```

## Local Checks

```powershell
cd desktop_app
flutter analyze
flutter test
```

## Notes

- The current API client defaults to `http://127.0.0.1:8000/api/v1`, so the backend should usually stay on port `8000` during local development.
- The app is currently Windows-first. Other Flutter targets are not the primary development focus in this repository.
- For end-to-end local testing, start the backend first and sign in with the demo account documented in the repository root `README.md`.

## Related Docs

- Root project overview: [`../README.md`](../README.md)
- Contribution guide: [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
- UI architecture notes: [`../APP_UI_ARCH.md`](../APP_UI_ARCH.md)
