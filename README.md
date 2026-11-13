# SriBees AI Tool — mobile app

The mobile app for the SriBees AI Tool (Stage B): the same prompt, live output, approvals and diff, with push notifications when the agent needs an answer.

Status: **1.0.0+1 (first build)** — login, tasks (new task, live conversation, Allow/Deny, follow-up, stop,
changes), staff workspace, server board, users/sessions/workspaces (owner), push notifications, Sinhala + English.
Flutter, pinned to 3.47.9 in CI. Package `com.sribeesonline.sribees_ai`, Firebase project `sribeesonline`.

The APK is built by `.github/workflows/build-apk.yml` on every push to `main`. It needs these repo secrets:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` and
`GOOGLE_SERVICES_JSON`.
