# Phase 07 — Email/password authentication

17 October 2026, Asia/Jakarta. Baseline `8e9f888`, branch `feature/operational-v2`.

The login page no longer has a Google button, separator, callback or provider route. `AuthService.signInWithGoogle`, Google initialization/sign-out and the direct `google_sign_in` dependency were removed after checking application references. Firebase provider configuration, existing identities, Firebase options and Android application ID were preserved.

Email/password login, registration, Firebase session stream, profile synchronization, password visibility, inactive-account gate and logout remain. Both login and registration reject duplicate submissions. Incorrect-credential, wrong-password, invalid-email, disabled-account and network failures have Indonesian messages. The login page provides password reset with a neutral response to avoid confirming whether an address is registered.

## Existing identities and transition

A fresh read-only Authentication account listing completed during this phase: **1 account, 1 with password, 0 Google-only, 0 other-only**. Only counts were retained in public documentation. This is a point-in-time observation, not a guarantee that the provider mix cannot change. No production identity was created, deleted, merged, emailed or modified by development tests.

If a Google-only account is introduced later, use **Lupa password / atur password akun lama** with its existing verified account email. Complete the reset, then verify that the Firebase UID and `users/{uid}` are unchanged before relying on the new sign-in method. An already signed-in user may instead link a password credential after appropriate recent authentication. Keep the Google Console provider and a previously verified client available until affected users have verified their transition. An administrator must investigate inaccessible email, disabled identities or conflicting providers; never register a replacement account or merge identities merely because email addresses match.

The trusted Admin identity workflow provisions an email identity with a chosen new UID and an **inactive** profile. An existing UID/email collision becomes `needs_review`; the worker never adopts or merges the existing identity. Password setup uses the existing reset flow; the Admin panel does not store passwords. Profile removal and Auth identity removal are distinct choices.

## Evidence and limits

Phase 07 Flutter tests cover service login/registration/profile synchronization/logout/session-stream behavior, invalid input, authentication failures, loading/double-submit protection, navigation to registration, reset dispatch and the absence of Google UI. They use injected Firebase interfaces; they do not prove cold-start session persistence on a device. The Auth Emulator additionally verifies provisioning, reset-link generation and deletion with the same UID. No real-device login or email-delivery test is claimed.

Official references: [Firebase account management](https://firebase.google.com/docs/auth/admin/manage-users), [password reset and linked providers](https://firebase.google.com/docs/auth/web/manage-users).
