# Bubbl Flutter SDK Internal Packaging and Distribution Guide

This document defines how we package and distribute `bubbl_flutter_sdk` for internal and partner app teams.

## Scope

- Flutter plugin package: `sdk/bubbl_flutter_sdk`
- Android native dependency consumed by plugin: `tech.bubbl:bubbl-sdk`
- iOS native dependency consumed by plugin: `BubblSDK`

## Current dependency pins

- Flutter plugin version: `pubspec.yaml` (`version`)
- Android native SDK: `android/build.gradle.kts` (`implementation("tech.bubbl:bubbl-sdk:...")`)
- iOS native SDK: `ios/bubbl_flutter_sdk.podspec` (`s.dependency 'BubblSDK', '...'`)
- Podspec version: `ios/bubbl_flutter_sdk.podspec` (`s.version`)

Keep these in sync for each release.

## Release strategy

Recommended: distribute by Git tag from this monorepo.

Why:
- plugin depends on private/native artifacts (GitHub Packages Maven + private BubblSDK pod source in host app)
- internal teams can pin exact commits/tags
- easy rollback by reverting dependency ref

## Pre-release checklist

1. Confirm native SDK versions to ship
- Android SDK version is published and consumable in GitHub Packages
- iOS BubblSDK tag exists and is installable via CocoaPods

2. Update versions and metadata
- bump `sdk/bubbl_flutter_sdk/pubspec.yaml` `version`
- bump `sdk/bubbl_flutter_sdk/ios/bubbl_flutter_sdk.podspec` `s.version`
- update native pins when required:
  - `sdk/bubbl_flutter_sdk/android/build.gradle.kts`
  - `sdk/bubbl_flutter_sdk/ios/bubbl_flutter_sdk.podspec`
- update `sdk/bubbl_flutter_sdk/CHANGELOG.md`
- update SDK docs if API/behavior changed

3. Run package quality gates

```bash
cd /Users/jackwright/Projects/bubbl-current/sdk/bubbl_flutter_sdk
flutter clean
flutter pub get
flutter analyze
flutter test
```

Optional stricter check:

```bash
dart format --set-exit-if-changed lib test
```

4. Run example app smoke checks

```bash
cd /Users/jackwright/Projects/bubbl-current/apps/bubbl-flutter
flutter clean
flutter pub get
```

Android:

```bash
cd /Users/jackwright/Projects/bubbl-current/apps/bubbl-flutter
flutter run -d android
```

iOS:

```bash
cd /Users/jackwright/Projects/bubbl-current/apps/bubbl-flutter/ios
pod install
cd /Users/jackwright/Projects/bubbl-current/apps/bubbl-flutter
flutter run -d ios
```

5. Validate runtime behavior (both platforms)
- `boot` succeeds
- permission flow works
- `startLocationTracking` succeeds
- geofence stream emits data after refresh
- notification stream receives payloads
- survey methods (`trackSurveyEvent`, `submitSurveyResponse`) succeed
- device log stream (`startDeviceLogStream`) emits snapshots

## Tag and publish process

1. Commit release changes

```bash
cd <repo-root-containing-sdk>
git add sdk/bubbl_flutter_sdk docs/bubbl-docs-redocly/guides
git commit -m "release(flutter-sdk): vX.Y.Z"
```

2. Create and push release tag

```bash
git tag flutter-sdk-vX.Y.Z
git push origin flutter-sdk-vX.Y.Z
```

3. Announce installation snippet to consumers (Git dependency)

```yaml
dependencies:
  bubbl_flutter_sdk:
    git:
      url: git@github.com:bubbl-repo/bubbl-current.git
      path: sdk/bubbl_flutter_sdk
      ref: flutter-sdk-vX.Y.Z
```

## Consumer prerequisites

### Android

Consumers must provide GitHub Packages credentials for `tech.bubbl:bubbl-sdk`.

`~/.gradle/gradle.properties` or project `android/gradle.properties`:

```properties
GITHUB_USERNAME=your-github-username
GITHUB_TOKEN=your-github-token
```

### iOS

Host app `ios/Podfile` must include `BubblSDK` source (Git pod currently):

```ruby
pod 'BubblSDK', :git => 'https://github.com/bubbl-repo/bubbl-ios-sdk.git', :tag => '2.1.6'
```

Then run:

```bash
cd ios
pod install
```

## Rollback

1. Revert consumer app to previous plugin tag/ref.
2. Run `flutter pub get`.
3. Re-run smoke tests.
4. If native pin changed, also verify Android/iOS dependency resolution and pod install.

## Known behavior notes

- Dart `BubblEnvironment` includes `development`, `staging`, `production`.
- Android bridge currently maps only `PRODUCTION` explicitly; any other value falls back to `STAGING`.
- iOS bridge supports `DEVELOPMENT`, `STAGING`, and `PRODUCTION`.

If true development environment parity is required across platforms, update Android environment parsing before release.
