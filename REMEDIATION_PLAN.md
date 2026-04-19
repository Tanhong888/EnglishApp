# Remediation Plan

## Goal

Bring the current codebase to a safer and more coherent baseline, then close the largest user-facing capability gaps without rewriting the whole product.

## Scope

This plan is based on the current repository state on 2026-04-02.

## Checklist

- [x] Replace the shared `Admin Key` model with authenticated administrator access.
  Acceptance:
  Admin APIs require a logged-in admin user instead of a reusable static header secret.
  Desktop admin pages no longer expose or persist an admin key locally.

- [x] Remove reusable hard-coded JWT signing defaults from repository code.
  Acceptance:
  The backend no longer ships with a fixed JWT secret in code.
  Environment examples explicitly require a real secret for stable environments.

- [x] Gate demo data to development usage.
  Acceptance:
  Demo users/articles are seeded only when `APP_ENV=dev` and `SEED_DEMO_DATA=true`.
  README clearly marks the demo account as development-only.

- [x] Tighten analytics exposure.
  Acceptance:
  Event writes require authentication and derive `user_id` from the bearer token.
  Global analytics listing/summary are administrator-only.

- [x] Restrict CORS configuration.
  Acceptance:
  Wildcard origins are removed.
  Allowed origins are configured through environment variables.

- [x] Restore a user registration entry in the desktop client.
  Acceptance:
  Windows client exposes a registration page and can create a new account against `/auth/register`.

- [x] Close the user-side reading loop for analysis and quiz.
  Acceptance:
  Article detail page can display sentence analyses and submit reading quiz answers.
  Quiz submission returns real scoring instead of a fixed zero result.

- [x] Align project documentation with actual functionality.
  Acceptance:
  Root README reflects the real feature set and current environment variables.

- [x] Add user-side article audio playback.
  Acceptance:
  Article detail page shows audio generation status and can play/pause/restart ready article audio.
  Desktop client gracefully handles pending/processing/failed audio states.

- [x] Restore green automated test execution on this machine.
  Acceptance:
  Local `pytest` execution passes on this machine.
  `flutter analyze` passes on this machine.

## Implementation Notes

- Admin access is now tied to `ADMIN_EMAILS`.
- Existing front-end session payloads now include `is_admin`.
- Demo content remains available for local development but is no longer positioned as a production default.
