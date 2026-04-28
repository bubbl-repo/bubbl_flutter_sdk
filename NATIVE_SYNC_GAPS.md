# Flutter SDK Native Sync Gaps

This note captures the main drift between `bubbl_flutter_sdk` and the current native SDKs as of 2026-04-28.

## 1. Dependency versions are behind

Current Flutter wrapper references:

- Android native SDK: `2.2.1`
- iOS native SDK: `2.2.0`
- Flutter package version: `2.2.1`

Current native SDK releases:

- Android SDK: `2.4.0`
- iOS SDK: `2.4.0`

Files to update:

- `pubspec.yaml`
- `android/build.gradle.kts`
- `ios/bubbl_flutter_sdk.podspec`
- `README.md`

Specific version drift:

- `pubspec.yaml` -> `version: 2.2.1`
- `android/build.gradle.kts` -> `implementation("tech.bubbl.sdk:bubbl-sdk:2.2.1")`
- `ios/bubbl_flutter_sdk.podspec` -> `s.version = '2.2.0'`
- `ios/bubbl_flutter_sdk.podspec` -> `s.dependency 'BubblSDK', '2.2.0'`

## 2. Environment mapping is wrong across platforms

Flutter currently exposes:

- `development`
- `staging`
- `production`

But native platforms differ:

- Android native supports:
  - `NIGHTLY`
  - `STAGING`
  - `PRODUCTION`
- iOS native supports:
  - `development`
  - `staging`
  - `production`

Current Flutter bug:

- Dart sends `DEVELOPMENT`
- iOS bridge maps `DEVELOPMENT` -> `.development`
- Android bridge maps anything except `PRODUCTION` to `STAGING`

That means Flutter `development` silently becomes Android `staging`.

Files involved:

- `lib/src/models.dart`
- `android/src/main/kotlin/tech/bubbl/bubbl_flutter_sdk/BubblFlutterSdkPlugin.kt`
- `ios/Classes/BubblFlutterSdkPlugin.swift`

Recommended fix:

- Decide on one shared Flutter enum model.
- Most likely:
  - rename Flutter `development` to `nightly`, or
  - add both `development` and `nightly` explicitly and map carefully per platform.

At minimum, the current silent fallback on Android should be removed.

## 3. Flutter surface is missing native token-forwarding APIs

Native iOS exposes:

- `BubblPlugin.updateAPNsToken(_:)`
- `BubblPlugin.updateFCMToken(_:)`

Native Android exposes:

- `BubblSdk.syncFcmToken(context: Context, token: String)`

Flutter does not currently expose token forwarding methods in the Dart API.

Why this matters:

- Host Flutter apps often need to explicitly forward refreshed push tokens.
- The native SDKs have support for token sync, but the wrapper does not expose it cleanly.

Recommended additions to Flutter API:

- `Future<bool> updateFcmToken(String token)`
- iOS-only or cross-platform token forwarding API for APNs if needed

Files likely needing updates:

- `lib/bubbl_flutter_sdk.dart`
- `lib/bubbl_flutter_sdk_platform_interface.dart`
- `lib/bubbl_flutter_sdk_method_channel.dart`
- `android/src/main/kotlin/tech/bubbl/bubbl_flutter_sdk/BubblFlutterSdkPlugin.kt`
- `ios/Classes/BubblFlutterSdkPlugin.swift`

## 4. Some Flutter methods are not implemented consistently across platforms

### `clearCachedCampaigns`

Android:

- Actually calls `BubblSdk.clearCachedCampaigns()`

iOS:

- Returns `true` but currently does not clear anything

That is a behavior mismatch hidden behind a shared Dart API.

### `startLocationTracking`

iOS:

- Requests location permissions and waits for authorization transitions

Android:

- Starts tracking directly and expects permissions to already be handled

This may be intentional, but the wrapper behavior is not symmetrical.

## 5. Flutter wrapper does not expose several newer iOS-native utilities

Current iOS native SDK has public utilities that are not exposed in Flutter, including:

- `fetchConfiguration(forceRefresh:)`
- `refetchGeofence()`
- `getNotificationStats()`
- `resetNotificationStats()`
- `clearLogs()`
- log file access helpers

Some related functionality is partly wrapped in Flutter already:

- `refreshPrivacyText`
- `getCurrentConfiguration`
- `forceRefreshCampaigns`

But the full utility surface is not exposed.

Recommendation:

- Decide whether Flutter should remain a minimal wrapper or aim for parity with native helper APIs.
- If parity is the goal, add wrappers for the high-value utilities first:
  - token forwarding
  - explicit config refresh
  - notification stats
  - log management

## 6. Polling override / advanced runtime behavior needs verification

Flutter boot options expose:

- `geoPollIntervalMs`
- `defaultDistance`

Android:

- uses both

iOS:

- bridge clearly handles `geoPollIntervalMs`
- Flutter bridge accepts `defaultDistance`, but current iOS bridge boot config does not use it

This means `defaultDistance` is currently Android-only behavior from Flutter.

Recommendation:

- Either implement iOS support if native iOS should support it, or
- document it as Android-only in Dart docs and types.

## 7. Docs are behind current native release reality

Current docs still say:

- Android dependency `2.2.1`
- iOS pod dependency `2.2.0`

These should be updated once the wrapper is synced.

Files:

- `README.md`
- potentially `CHANGELOG.md`

## Recommended update order

1. Bump native dependencies to Android `2.4.0` and iOS `2.4.0`.
2. Fix environment mapping so Flutter does not mis-route `development` on Android.
3. Add token-forwarding methods to the Flutter API.
4. Resolve behavior mismatch for `clearCachedCampaigns`.
5. Decide whether to expose more native utilities or keep the wrapper intentionally minimal.
6. Bump Flutter package version and update docs.

## Most urgent issues

If doing the smallest safe sync first, these are the important ones:

1. Android native dependency version bump to `2.4.0`
2. iOS native dependency version bump to `2.4.0`
3. Fix `development` environment mapping on Android
4. Expose FCM token forwarding
5. Fix or document `clearCachedCampaigns` mismatch
