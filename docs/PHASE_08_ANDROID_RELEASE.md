# Phase 08 — Android signing and release

Resumed verification: 24 October 2026 (Asia/Jakarta). Historical observations below retain their dates; final results are in the test and handoff reports.

17 October 2026, Asia/Jakarta. Classification: **release candidate / owner review**, not an owner-approved production release. See [test report](PHASE_08_TEST_REPORT.md) for current build/device results and [handoff](PHASE_08_FINAL_HANDOFF.md) for final Git/PR state.

## Identity and configuration

- Package/namespace: `id.seicycle.app`; display name: **SeiCycle**.
- Candidate version: **1.0.1+2**, advanced from installed `1.0.0+1`. No Git tags or GitHub Releases existed at inspection. Other distribution channels were not accessible: owner must confirm code 2 exceeds every previously distributed code before publication.
- Owner-requested branding refinement keeps the original logo asset unchanged: transparent source padding is excluded during deterministic Flutter Canvas rendering, with legacy mdpi?xxxhdpi marks occupying 84% of their canvas. Android 26+ receives an adaptive foreground with the whole mark inside a centered 64dp square on a 108dp canvas, within the 66dp safe zone. Launch resources now show the original logo; Android 12+ uses the cream splash background. Flutter header/sidebar/login/Dashboard logo layout is enlarged and checked separately. No AI redraw or replacement brand was used.
- Notifications use a dedicated white-on-transparent rendition of the same mark, rather than the adaptive launcher drawable. A specific resource-keep rule protects this dynamically named icon during release shrinking. Native reminder delivery/permission acceptance remains separate.
- Main manifest now explicitly includes Internet permission; previously it existed only in debug/profile manifests, which would prevent release Firebase connectivity. Notification/boot permissions and receivers are retained.
- AGP 8.11.1, Gradle 8.14 and Kotlin 2.2.20 retained. Kotlin JVM target uses supported `compilerOptions` with Java 17 bytecode instead of the deprecated `kotlinOptions.jvmTarget` setter. Flutter's broader built-in-Kotlin migration warning remains a separate migration item.
- Android-only Firebase configuration; other platforms need their own setup and acceptance.

## Owner-authorized signing material

The owner explicitly approved creating a new key and storing it under **Documents / SeiCycle Signing**, outside the repository, with credentials encrypted by Windows DPAPI. A new **RSA 4096** key with alias `seicycle-release` and public subject `CN=SeiCycle Release, O=Kebun Sei, C=ID` was generated without overwriting an existing key. Store and key passwords are randomly generated, are not printed, and are supplied to build processes only through environment variables. Folder access is restricted to the current Windows user and SYSTEM. A private owner recovery note accompanies the material.

DPAPI protects credentials for the current Windows user/machine. It is **not a portable password backup**. Before distribution the owner must escrow the password in an approved password manager, copy the keystore to encrypted offline storage and test recovery on another trusted machine. This backup acceptance remains pending. No signing files, encrypted credential blob, passwords or machine-specific paths enter Git.

## Reproducible configuration

Copy `android/key.properties.example` to ignored `android/key.properties` and fill locally, or supply these environment variables from a secret store:

| Property | Environment override |
| --- | --- |
| `storeFile` | `SEICYCLE_STORE_FILE` |
| `storePassword` | `SEICYCLE_STORE_PASSWORD` |
| `keyAlias` | `SEICYCLE_KEY_ALIAS` |
| `keyPassword` | `SEICYCLE_KEY_PASSWORD` |

Environment values take precedence. Relative store paths resolve from `android/`; Windows paths should use forward slashes. Do not put passwords in command arguments or committed files. DPAPI decryption/build helpers for this authorized workstation remain private; the public Gradle configuration also supports CI secret injection.

`validateReleaseCredentials` gates release tasks before compilation/signing. It rejects missing properties, absent stores, unusable credentials, expired/not-yet-valid certificates and Android debug certificates/aliases. `release` exclusively uses the release signing configuration; no debug fallback or unsigned distribution path was added. Debug builds remain possible without production credentials.

```bash
flutter clean
flutter pub get
flutter pub outdated
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
flutter build apk --release
```

The full final sequence and actual outcomes are recorded in [test evidence](PHASE_08_TEST_REPORT.md). Raw build output remains ignored. A first missing-credential invocation correctly failed with the actionable release-blocked message; key generation required a retry after Windows PowerShell treated normal keytool stderr as a terminating error. The existing encrypted credential was reused and no existing key was overwritten.

## Validate the artifact before installing

Expected output: `build/app/outputs/flutter-apk/app-release.apk`.

```powershell
Get-FileHash build/app/outputs/flutter-apk/app-release.apk -Algorithm SHA256
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
```

Check package, version, permissions, APK size, certificate and absence of `application-debuggable`. Confirm the artifact was built from the reviewed commit and retain its checksum privately/publicly as appropriate. Certificate fingerprint is public information; private keys/passwords are not.

The connected Infinix X6833B initially had a debug-signed `1.0.0+1` installation. Its public certificate subject was Android Debug. A newly signed release cannot replace it in place. **Do not uninstall automatically:** owner approval is required because uninstall removes local application data/session/drafts. Firestore cloud records are separate and are not deleted by uninstalling the APK.

After approved installation, test cold start without debug service, login, live reads, back navigation, notifications, export/share and the full role checklist. Installation/build success alone does not establish worker availability or production readiness.

## Official compatibility references

- [Flutter Android release/signing](https://docs.flutter.dev/deployment/android)
- [Kotlin Gradle/AGP compatibility](https://kotlinlang.org/docs/gradle-configure-project.html)
- [AGP 8.11 requirements](https://developer.android.com/build/releases/agp-8-11-0-release-notes)

KGP 2.2.20 is within the documented Gradle 8.14/AGP 8.11.1 range; these sources do not prove every native dependency/API is free of deprecation. Licensing noted by `flutter doctor` and owner distribution/version decisions remain distinct gates.

## Rebuilding branding resources

Run `flutter test tools/render_launcher_assets_test.dart` after an approved original-logo change. This resource-rendering harness writes deterministic Android assets; it is not a production runtime test and is not included in the application test count. The master `lib/assets/logo.png` is unchanged. [Android adaptive-icon requirements](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive) define the safe zone; [splash guidance](https://developer.android.com/develop/ui/views/launch/splash-screen) describes launch behavior.

## Verified candidate ? 24 October

Validated code commit `924cdea403c3253eb34118ecbeb2cb9b3a919825`; debug build 212.9s, signed release 249.3s. Output `build/app/outputs/flutter-apk/app-release.apk`, 70,783,903 bytes (67.5 MiB). SHA-256: `b7f879d536c808e882370c68398a1c21d07bdd2fe906c97e3c2da02b59fc57e5`. AAPT confirms `id.seicycle.app`, versionName 1.0.1, versionCode 2, minSdk 24, expected Internet permission and no debuggable flag. APK signature verification passed with v2, owner subject CN=SeiCycle Release/O=Kebun Sei/C=ID; certificate SHA-256 `f26fcac77490aaebd83afbb944c906a20f774358ff1fea81d96e11ef883a8e91`. It is not the installed debug certificate.

The owner explicitly approved uninstalling debug and installing this exact signed hash. No uninstall occurred before approval. Final device results and remaining authentication/native gates are in the test report. The actual enlarged launcher mark was visually checked on Infinix after the final debug update.
