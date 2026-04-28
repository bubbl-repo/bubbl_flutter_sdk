## 2.4.0

- Bumped native Android and iOS SDK dependencies to `2.4.0`.
- Fixed Flutter `development` environment mapping to target Android `NIGHTLY` instead of `STAGING`.
- Added Flutter APIs for forwarding FCM and APNs device tokens to the native SDKs.
- Improved `clearCachedCampaigns()` on iOS and documented remaining platform behavior differences.

## 2.2.1

- Fixed Android push handling for nested payload envelopes (`payload`, `notification_payload`, `data`).
- Added Android notification open-intent bridging so tapped pushes are emitted reliably to Flutter listeners.

## 2.2.0

- Added robust iOS push payload compatibility for legacy and new keys.
- Added support for structured `media` and `cta` payload arrays.
- Aligned iOS bridge parsing with Android/server push payload normalization.

## 0.0.1

- Scaffolded Flutter plugin package for Bubbl.
- Added Android method/event bridge to Bubbl native SDK.
- Added iOS method/event bridge to Bubbl native SDK.
- Added typed Dart API wrapper and models.
- Added example app with boot/permissions/geofence/notification/device-log flows.
