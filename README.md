# bubbl_flutter_sdk

Flutter plugin wrapper for Bubbl native SDKs on Android and iOS.

## Features

- Boot/init Bubbl SDK with API key + environment
- Permissions helpers (location + notifications)
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
- Add Bubbl Maven repository for `tech.bubbl:bubbl-sdk:2.1.0` (no credentials required)
- Add Firebase setup in host app (`google-services.json`)
- Ensure `google-services.json` includes your exact Android `applicationId` (example app uses `tech.bubbl.flutter`)

`android/settings.gradle(.kts)`:

```kotlin
dependencyResolutionManagement {
  repositories {
    google()
    mavenCentral()
    maven { url = uri("https://maven.bubbl.tech/repository/releases/") }
  }
}
```

## iOS requirements

- iOS 15.1+
- CocoaPods
- Firebase/APNs setup in host app
- `GoogleService-Info.plist` in Runner target

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
