import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'bubbl_flutter_sdk_method_channel.dart';

abstract class BubblFlutterSdkPlatform extends PlatformInterface {
  BubblFlutterSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static BubblFlutterSdkPlatform _instance = MethodChannelBubblFlutterSdk();

  static BubblFlutterSdkPlatform get instance => _instance;

  static set instance(BubblFlutterSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<Map<String, dynamic>> notificationEvents() {
    throw UnimplementedError('notificationEvents() has not been implemented.');
  }

  Stream<Map<String, dynamic>> geofenceEvents() {
    throw UnimplementedError('geofenceEvents() has not been implemented.');
  }

  Stream<Map<String, dynamic>> deviceLogEvents(Map<String, dynamic>? options) {
    throw UnimplementedError('deviceLogEvents() has not been implemented.');
  }

  Future<Map<String, dynamic>> boot({
    required String apiKey,
    required String environment,
    required List<String> segmentationTags,
    int? geoPollIntervalMs,
    int? defaultDistance,
  }) {
    throw UnimplementedError('boot() has not been implemented.');
  }

  Future<Map<String, dynamic>> init({
    required String apiKey,
    required String environment,
    required List<String> segmentationTags,
    int? geoPollIntervalMs,
    int? defaultDistance,
  }) {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<List<String>> requiredPermissions() {
    throw UnimplementedError('requiredPermissions() has not been implemented.');
  }

  Future<bool> locationGranted() {
    throw UnimplementedError('locationGranted() has not been implemented.');
  }

  Future<bool> notificationGranted() {
    throw UnimplementedError('notificationGranted() has not been implemented.');
  }

  Future<bool> requestPushPermission() {
    throw UnimplementedError(
      'requestPushPermission() has not been implemented.',
    );
  }

  Future<bool> updateFcmToken(String token) {
    throw UnimplementedError('updateFcmToken() has not been implemented.');
  }

  Future<bool> updateApnsToken(String hexToken) {
    throw UnimplementedError('updateApnsToken() has not been implemented.');
  }

  Future<bool> startLocationTracking() {
    throw UnimplementedError(
      'startLocationTracking() has not been implemented.',
    );
  }

  Future<void> refreshGeofence({
    required double latitude,
    required double longitude,
  }) {
    throw UnimplementedError('refreshGeofence() has not been implemented.');
  }

  Future<bool> updateSegments(List<String> tags) {
    throw UnimplementedError('updateSegments() has not been implemented.');
  }

  Future<bool> setCorrelationId(String correlationId) {
    throw UnimplementedError('setCorrelationId() has not been implemented.');
  }

  Future<String> getCorrelationId() {
    throw UnimplementedError('getCorrelationId() has not been implemented.');
  }

  Future<bool> clearCorrelationId() {
    throw UnimplementedError('clearCorrelationId() has not been implemented.');
  }

  Future<String> getPrivacyText() {
    throw UnimplementedError('getPrivacyText() has not been implemented.');
  }

  Future<String> refreshPrivacyText() {
    throw UnimplementedError('refreshPrivacyText() has not been implemented.');
  }

  Future<Map<String, dynamic>?> getCurrentConfiguration() {
    throw UnimplementedError(
      'getCurrentConfiguration() has not been implemented.',
    );
  }

  Future<bool> hasCampaigns() {
    throw UnimplementedError('hasCampaigns() has not been implemented.');
  }

  Future<int> getCampaignCount() {
    throw UnimplementedError('getCampaignCount() has not been implemented.');
  }

  Future<bool> forceRefreshCampaigns() {
    throw UnimplementedError(
      'forceRefreshCampaigns() has not been implemented.',
    );
  }

  Future<void> clearCachedCampaigns() {
    throw UnimplementedError(
      'clearCachedCampaigns() has not been implemented.',
    );
  }

  Future<String> getApiKey() {
    throw UnimplementedError('getApiKey() has not been implemented.');
  }

  Future<String> sayHello() {
    throw UnimplementedError('sayHello() has not been implemented.');
  }

  Future<bool> sendEvent(Map<String, dynamic> payload) {
    throw UnimplementedError('sendEvent() has not been implemented.');
  }

  Future<void> cta({required int notificationId, required String locationId}) {
    throw UnimplementedError('cta() has not been implemented.');
  }

  Future<bool> trackSurveyEvent({
    required String notificationId,
    required String locationId,
    required String activity,
  }) {
    throw UnimplementedError('trackSurveyEvent() has not been implemented.');
  }

  Future<bool> submitSurveyResponse({
    required String notificationId,
    required String locationId,
    required List<Map<String, dynamic>> answers,
  }) {
    throw UnimplementedError(
      'submitSurveyResponse() has not been implemented.',
    );
  }

  Future<Map<String, dynamic>?> getTenantConfig() {
    throw UnimplementedError('getTenantConfig() has not been implemented.');
  }

  Future<bool> setTenantConfig({
    required String apiKey,
    required String environment,
  }) {
    throw UnimplementedError('setTenantConfig() has not been implemented.');
  }

  Future<bool> clearTenantConfig() {
    throw UnimplementedError('clearTenantConfig() has not been implemented.');
  }

  Future<bool> clearStoredConfig() {
    throw UnimplementedError('clearStoredConfig() has not been implemented.');
  }

  Future<Map<String, dynamic>> getDeviceLogStreamInfo() {
    throw UnimplementedError(
      'getDeviceLogStreamInfo() has not been implemented.',
    );
  }

  Future<List<String>> getDeviceLogTail({int maxLines = 80}) {
    throw UnimplementedError('getDeviceLogTail() has not been implemented.');
  }

  Future<Map<String, dynamic>> startDeviceLogStream(
    Map<String, dynamic> options,
  ) {
    throw UnimplementedError(
      'startDeviceLogStream() has not been implemented.',
    );
  }

  Future<void> stopDeviceLogStream() {
    throw UnimplementedError('stopDeviceLogStream() has not been implemented.');
  }

  Future<bool> testNotification() {
    throw UnimplementedError('testNotification() has not been implemented.');
  }
}
