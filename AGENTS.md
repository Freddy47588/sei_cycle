# SeiCycle development requirements

Apply the dependency health policy in `docs/DEPENDENCY_HEALTH.md` for Phase 05 and later work.

Before coding run `flutter --version`, `flutter pub get`, `flutter pub outdated`, and `flutter analyze`. Inspect both `pubspec.yaml` and `pubspec.lock`; verify package status from pub.dev and official maintenance sources. A newer version alone is not deprecation. Do not introduce deprecated APIs, discontinued/unmaintained dependencies, or unsupported SDK/native combinations. Prefer supported existing packages and official packages. Do not hide deprecation with lint ignores.

Preserve working Android/Firebase configuration and Phase 01–04 behavior. Evaluate Kotlin migration independently using official Flutter/AGP prerequisites; do not upgrade major versions only to suppress warnings. Do not remove existing dependencies or migrate them without impact assessment and regression verification.

After changes run `flutter pub get`, `flutter pub outdated`, `flutter analyze`, `flutter test --reporter expanded`, and attempt `flutter build apk --debug` when Android SDK is available. Report added/changed versions, official maintenance evidence, remaining warnings, tests, build result, and unverified transitive/native scope. Never claim every dependency API is free of deprecation from package metadata alone.

## Privacy requirements

`docs/CODEX_PROGRESS.md` is a private, local-only continuation checkpoint. Keep it updated but never track, commit, push, or quote its private contents in public artifacts. Both uppercase and lowercase checkpoint filenames are ignored.

Never publish workstation/user directory paths, machine identifiers, personal account addresses, credentials, passwords, access/refresh tokens, private keys, signing stores, raw production exports, private financial/personal records, backups or runtime logs. Keep private audit/build output under ignored local directories. Public documentation must use repository-relative paths and sanitized summaries.

Before committing or pushing, inspect staged files and all unpublished commits for private content and secret material. Use a GitHub no-reply author/committer identity for new commits. Ignoring a file does not remove it from earlier commits: clean unpublished history before pushing. Do not rewrite published history or force-push without separate explicit authorization.
