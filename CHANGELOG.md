## 2.2.7

- Added explicit plugin-level fallback telemetry posting to transmission `/notification-event` for `sendEvent`, `cta`, `trackSurveyEvent`, and `submitSurveyResponse`.
- Added notification-to-campaign cache in native bridges so telemetry can include `campaignId` when events are emitted after payload receipt.
- Added payload normalization support for campaign frequency fields (`coolingPeriodSeconds`, `maximumTriggers`, `ctaSuspend`) in notification event payloads.

## 2.2.6

- Updated bundled native SDK pins to `2.2.6` on both Android (`tech.bubbl.sdk:bubbl-sdk`) and iOS (`BubblSDK` pod).

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
