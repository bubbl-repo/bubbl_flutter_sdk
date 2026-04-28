# bubbl_flutter_sdk

Flutter plugin wrapper for Bubbl native SDKs on Android and iOS.

## Features

- Boot/init Bubbl SDK with API key + environment
- Permissions helpers (location + notifications)
- Push token forwarding helpers (FCM and APNs)
- Start location tracking and geofence refresh
- Notification + geofence + device-log event streams
- Survey + analytics event methods
- Tenant config helpers

## Install

Add dependency in your app:

```yaml
dependencies:
  bubbl_flutter_sdk:
    path: ../bubbl_flutter_sdk
```

## Android requirements

- Min SDK 27+
- Add Maven Central dependency `tech.bubbl.sdk:bubbl-sdk:2.4.0` (no credentials required)
- Add Firebase setup in host app (`google-services.json`)
- Ensure `google-services.json` includes your exact Android `applicationId` (example app uses `tech.bubbl.flutter`)

`android/settings.gradle(.kts)`:

```kotlin
dependencyResolutionManagement {
  repositories {
    google()
    mavenCentral()
  }
}
```

## iOS requirements

- iOS 15.1+
- CocoaPods
- Native pod dependency `BubblSDK 2.4.0`
- Firebase/APNs setup in host app
- `GoogleService-Info.plist` in Runner target

## Environment mapping

- `BubblEnvironment.development`
  - iOS: maps to native `development`
  - Android: maps to native `NIGHTLY`
- `BubblEnvironment.staging`
  - iOS and Android: maps to `staging`
- `BubblEnvironment.production`
  - iOS and Android: maps to `production`

This keeps Flutter `development` from silently behaving like Android staging.

## Quick usage

```dart
final sdk = BubblFlutterSdk.instance;

await sdk.boot(
  apiKey: 'YOUR_API_KEY',
  options: const BubblBootOptions(
    environment: BubblEnvironment.staging,
    segmentationTags: <String>[],
    geoPollIntervalMs: 300000,
    defaultDistance: 25,
  ),
);

await sdk.requestPushPermission();
await sdk.startLocationTracking();

// Forward refreshed push tokens when your host app receives them.
await sdk.updateFcmToken('YOUR_FCM_TOKEN');
await sdk.updateApnsToken('YOUR_APNS_TOKEN_HEX');

// Set correlation id (for example, logged-in user id).
await sdk.setCorrelationId('12345');

sdk.notificationEvents().listen((event) {
  print('notification: $event');
});

sdk.geofenceEvents().listen((event) {
  print('geofence: $event');
});
```

See `example/lib/main.dart` for a runnable end-to-end sample.

## Notes

- `clearCachedCampaigns()` clears cached campaigns on Android.
- On iOS, `clearCachedCampaigns()` clears the persisted geofence cache file and emits an empty geofence snapshot to Flutter, but the native iOS SDK does not currently expose a full in-memory campaign reset API.
