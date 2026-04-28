import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bubbl_flutter_sdk_platform_interface.dart';

class MethodChannelBubblFlutterSdk extends BubblFlutterSdkPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'tech.bubbl.sdk/methods',
  );

  @visibleForTesting
  final EventChannel notificationChannel = const EventChannel(
    'tech.bubbl.sdk/events/notification',
  );

  @visibleForTesting
  final EventChannel geofenceChannel = const EventChannel(
    'tech.bubbl.sdk/events/geofence',
  );

  @visibleForTesting
  final EventChannel deviceLogChannel = const EventChannel(
    'tech.bubbl.sdk/events/device_log',
  );

  @override
  Stream<Map<String, dynamic>> notificationEvents() {
    return notificationChannel.receiveBroadcastStream().map(_toMap);
  }

  @override
  Stream<Map<String, dynamic>> geofenceEvents() {
    return geofenceChannel.receiveBroadcastStream().map(_toMap);
  }

  @override
  Stream<Map<String, dynamic>> deviceLogEvents(Map<String, dynamic>? options) {
    return deviceLogChannel.receiveBroadcastStream(options).map(_toMap);
  }

  @override
  Future<Map<String, dynamic>> boot({
    required String apiKey,
    required String environment,
    required List<String> segmentationTags,
    int? geoPollIntervalMs,
    int? defaultDistance,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'apiKey': apiKey,
      'environment': environment,
      'segmentationTags': segmentationTags,
    };
    if (geoPollIntervalMs != null) {
      payload['geoPollIntervalMs'] = geoPollIntervalMs;
    }
    if (defaultDistance != null) {
      payload['defaultDistance'] = defaultDistance;
    }

    return _invokeMap('boot', payload);
  }

  @override
  Future<Map<String, dynamic>> init({
    required String apiKey,
    required String environment,
    required List<String> segmentationTags,
    int? geoPollIntervalMs,
    int? defaultDistance,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'apiKey': apiKey,
      'environment': environment,
      'segmentationTags': segmentationTags,
    };
    if (geoPollIntervalMs != null) {
      payload['geoPollIntervalMs'] = geoPollIntervalMs;
    }
    if (defaultDistance != null) {
      payload['defaultDistance'] = defaultDistance;
    }

    return _invokeMap('init', payload);
  }

  @override
  Future<List<String>> requiredPermissions() async {
    final List<dynamic>? value = await methodChannel
        .invokeMethod<List<dynamic>>('requiredPermissions');
    return value?.map((dynamic item) => item.toString()).toList() ?? <String>[];
  }

  @override
  Future<bool> locationGranted() async {
    return _invokeBool('locationGranted');
  }

  @override
  Future<bool> notificationGranted() async {
    return _invokeBool('notificationGranted');
  }

  @override
  Future<bool> requestPushPermission() async {
    return _invokeBool('requestPushPermission');
  }

  @override
  Future<bool> updateFcmToken(String token) async {
    return _invokeBool('updateFcmToken', <String, dynamic>{'token': token});
  }

  @override
  Future<bool> updateApnsToken(String hexToken) async {
    return _invokeBool('updateApnsToken', <String, dynamic>{
      'hexToken': hexToken,
    });
  }

  @override
  Future<bool> startLocationTracking() async {
    return _invokeBool('startLocationTracking');
  }

  @override
  Future<void> refreshGeofence({
    required double latitude,
    required double longitude,
  }) {
    return methodChannel.invokeMethod<void>(
      'refreshGeofence',
      <String, dynamic>{'latitude': latitude, 'longitude': longitude},
    );
  }

  @override
  Future<bool> updateSegments(List<String> tags) async {
    return _invokeBool('updateSegments', <String, dynamic>{'tags': tags});
  }

  @override
  Future<bool> setCorrelationId(String correlationId) async {
    return _invokeBool('setCorrelationId', <String, dynamic>{
      'correlationId': correlationId,
    });
  }

  @override
  Future<String> getCorrelationId() async {
    return await methodChannel.invokeMethod<String>('getCorrelationId') ?? '';
  }

  @override
  Future<bool> clearCorrelationId() async {
    return _invokeBool('clearCorrelationId');
  }

  @override
  Future<String> getPrivacyText() async {
    return await methodChannel.invokeMethod<String>('getPrivacyText') ?? '';
  }

  @override
  Future<String> refreshPrivacyText() async {
    return await methodChannel.invokeMethod<String>('refreshPrivacyText') ?? '';
  }

  @override
  Future<Map<String, dynamic>?> getCurrentConfiguration() async {
    final dynamic value = await methodChannel.invokeMethod<dynamic>(
      'getCurrentConfiguration',
    );
    if (value == null) {
      return null;
    }
    return _toMap(value);
  }

  @override
  Future<bool> hasCampaigns() async {
    return _invokeBool('hasCampaigns');
  }

  @override
  Future<int> getCampaignCount() async {
    final int? value = await methodChannel.invokeMethod<int>(
      'getCampaignCount',
    );
    return value ?? 0;
  }

  @override
  Future<bool> forceRefreshCampaigns() async {
    return _invokeBool('forceRefreshCampaigns');
  }

  @override
  Future<void> clearCachedCampaigns() {
    return methodChannel.invokeMethod<void>('clearCachedCampaigns');
  }

  @override
  Future<String> getApiKey() async {
    return await methodChannel.invokeMethod<String>('getApiKey') ?? '';
  }

  @override
  Future<String> sayHello() async {
    return await methodChannel.invokeMethod<String>('sayHello') ?? '';
  }

  @override
  Future<bool> sendEvent(Map<String, dynamic> payload) {
    return _invokeBool('sendEvent', payload);
  }

  @override
  Future<void> cta({required int notificationId, required String locationId}) {
    return methodChannel.invokeMethod<void>('cta', <String, dynamic>{
      'notificationId': notificationId,
      'locationId': locationId,
    });
  }

  @override
  Future<bool> trackSurveyEvent({
    required String notificationId,
    required String locationId,
    required String activity,
  }) {
    return _invokeBool('trackSurveyEvent', <String, dynamic>{
      'notificationId': notificationId,
      'locationId': locationId,
      'activity': activity,
    });
  }

  @override
  Future<bool> submitSurveyResponse({
    required String notificationId,
    required String locationId,
    required List<Map<String, dynamic>> answers,
  }) {
    return _invokeBool('submitSurveyResponse', <String, dynamic>{
      'notificationId': notificationId,
      'locationId': locationId,
      'answers': answers,
    });
  }

  @override
  Future<Map<String, dynamic>?> getTenantConfig() async {
    final dynamic value = await methodChannel.invokeMethod<dynamic>(
      'getTenantConfig',
    );
    if (value == null) {
      return null;
    }
    return _toMap(value);
  }

  @override
  Future<bool> setTenantConfig({
    required String apiKey,
    required String environment,
  }) {
    return _invokeBool('setTenantConfig', <String, dynamic>{
      'apiKey': apiKey,
      'environment': environment,
    });
  }

  @override
  Future<bool> clearTenantConfig() {
    return _invokeBool('clearTenantConfig');
  }

  @override
  Future<bool> clearStoredConfig() {
    return _invokeBool('clearStoredConfig');
  }

  @override
  Future<Map<String, dynamic>> getDeviceLogStreamInfo() {
    return _invokeMap('getDeviceLogStreamInfo');
  }

  @override
  Future<List<String>> getDeviceLogTail({int maxLines = 80}) async {
    final List<dynamic>? value = await methodChannel
        .invokeMethod<List<dynamic>>('getDeviceLogTail', <String, dynamic>{
          'maxLines': maxLines,
        });
    return value?.map((dynamic item) => item.toString()).toList() ?? <String>[];
  }

  @override
  Future<Map<String, dynamic>> startDeviceLogStream(
    Map<String, dynamic> options,
  ) {
    return _invokeMap('startDeviceLogStream', options);
  }

  @override
  Future<void> stopDeviceLogStream() {
    return methodChannel.invokeMethod<void>('stopDeviceLogStream');
  }

  @override
  Future<bool> testNotification() {
    return _invokeBool('testNotification');
  }

  Future<bool> _invokeBool(String method, [Map<String, dynamic>? args]) async {
    final bool? value = await methodChannel.invokeMethod<bool>(method, args);
    return value ?? false;
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final dynamic value = await methodChannel.invokeMethod<dynamic>(
      method,
      args,
    );
    return _toMap(value);
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<Object?, Object?>) {
      return value.map<String, dynamic>(
        (Object? key, Object? mapValue) => MapEntry(key.toString(), mapValue),
      );
    }

    if (value is Map<String, dynamic>) {
      return value;
    }

    return <String, dynamic>{};
  }
}
