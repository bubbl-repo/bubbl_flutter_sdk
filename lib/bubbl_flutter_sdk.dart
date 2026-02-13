import 'bubbl_flutter_sdk_platform_interface.dart';
import 'src/models.dart';

export 'src/models.dart';

class BubblFlutterSdk {
  BubblFlutterSdk._();

  static final BubblFlutterSdk instance = BubblFlutterSdk._();

  Stream<Map<String, dynamic>> notificationEvents() {
    return BubblFlutterSdkPlatform.instance.notificationEvents();
  }

  Stream<Map<String, dynamic>> geofenceEvents() {
    return BubblFlutterSdkPlatform.instance.geofenceEvents();
  }

  Stream<Map<String, dynamic>> deviceLogEvents({
    BubblDeviceLogStreamOptions? options,
  }) {
    return BubblFlutterSdkPlatform.instance.deviceLogEvents(options?.toMap());
  }

  Future<BubblBootResult> boot({
    required String apiKey,
    BubblBootOptions options = const BubblBootOptions(),
  }) async {
    final Map<String, dynamic> result = await BubblFlutterSdkPlatform.instance
        .boot(
          apiKey: apiKey,
          environment: options.environment.wireName,
          segmentationTags: options.segmentationTags,
          geoPollIntervalMs: options.geoPollIntervalMs,
          defaultDistance: options.defaultDistance,
        );
    return BubblBootResult.fromMap(result);
  }

  Future<BubblBootResult> init({
    required String apiKey,
    BubblBootOptions options = const BubblBootOptions(),
  }) async {
    final Map<String, dynamic> result = await BubblFlutterSdkPlatform.instance
        .init(
          apiKey: apiKey,
          environment: options.environment.wireName,
          segmentationTags: options.segmentationTags,
          geoPollIntervalMs: options.geoPollIntervalMs,
          defaultDistance: options.defaultDistance,
        );
    return BubblBootResult.fromMap(result);
  }

  Future<List<String>> requiredPermissions() {
    return BubblFlutterSdkPlatform.instance.requiredPermissions();
  }

  Future<bool> locationGranted() {
    return BubblFlutterSdkPlatform.instance.locationGranted();
  }

  Future<bool> notificationGranted() {
    return BubblFlutterSdkPlatform.instance.notificationGranted();
  }

  Future<bool> requestPushPermission() {
    return BubblFlutterSdkPlatform.instance.requestPushPermission();
  }

  Future<bool> startLocationTracking() {
    return BubblFlutterSdkPlatform.instance.startLocationTracking();
  }

  Future<void> refreshGeofence({
    required double latitude,
    required double longitude,
  }) {
    return BubblFlutterSdkPlatform.instance.refreshGeofence(
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<bool> updateSegments(List<String> tags) {
    return BubblFlutterSdkPlatform.instance.updateSegments(tags);
  }

  Future<bool> setCorrelationId(String correlationId) {
    return BubblFlutterSdkPlatform.instance.setCorrelationId(correlationId);
  }

  Future<String> getCorrelationId() {
    return BubblFlutterSdkPlatform.instance.getCorrelationId();
  }

  Future<bool> clearCorrelationId() {
    return BubblFlutterSdkPlatform.instance.clearCorrelationId();
  }

  Future<String> getPrivacyText() {
    return BubblFlutterSdkPlatform.instance.getPrivacyText();
  }

  Future<String> refreshPrivacyText() {
    return BubblFlutterSdkPlatform.instance.refreshPrivacyText();
  }

  Future<BubblConfiguration?> getCurrentConfiguration() async {
    final Map<String, dynamic>? map = await BubblFlutterSdkPlatform.instance
        .getCurrentConfiguration();
    if (map == null) {
      return null;
    }
    return BubblConfiguration.fromMap(map);
  }

  Future<bool> hasCampaigns() {
    return BubblFlutterSdkPlatform.instance.hasCampaigns();
  }

  Future<int> getCampaignCount() {
    return BubblFlutterSdkPlatform.instance.getCampaignCount();
  }

  Future<bool> forceRefreshCampaigns() {
    return BubblFlutterSdkPlatform.instance.forceRefreshCampaigns();
  }

  Future<void> clearCachedCampaigns() {
    return BubblFlutterSdkPlatform.instance.clearCachedCampaigns();
  }

  Future<String> getApiKey() {
    return BubblFlutterSdkPlatform.instance.getApiKey();
  }

  Future<String> sayHello() {
    return BubblFlutterSdkPlatform.instance.sayHello();
  }

  Future<bool> sendEvent(BubblSendEventParams params) {
    return BubblFlutterSdkPlatform.instance.sendEvent(params.toMap());
  }

  Future<void> cta({required int notificationId, required String locationId}) {
    return BubblFlutterSdkPlatform.instance.cta(
      notificationId: notificationId,
      locationId: locationId,
    );
  }

  Future<bool> trackSurveyEvent({
    required String notificationId,
    required String locationId,
    required String activity,
  }) {
    return BubblFlutterSdkPlatform.instance.trackSurveyEvent(
      notificationId: notificationId,
      locationId: locationId,
      activity: activity,
    );
  }

  Future<bool> submitSurveyResponse({
    required String notificationId,
    required String locationId,
    required List<BubblSurveyAnswer> answers,
  }) {
    return BubblFlutterSdkPlatform.instance.submitSurveyResponse(
      notificationId: notificationId,
      locationId: locationId,
      answers: answers
          .map((BubblSurveyAnswer answer) => answer.toMap())
          .toList(),
    );
  }

  Future<BubblTenantConfig?> getTenantConfig() async {
    final Map<String, dynamic>? map = await BubblFlutterSdkPlatform.instance
        .getTenantConfig();
    if (map == null) {
      return null;
    }
    return BubblTenantConfig.fromMap(map);
  }

  Future<bool> setTenantConfig({
    required String apiKey,
    required BubblEnvironment environment,
  }) {
    return BubblFlutterSdkPlatform.instance.setTenantConfig(
      apiKey: apiKey,
      environment: environment.wireName,
    );
  }

  Future<bool> clearTenantConfig() {
    return BubblFlutterSdkPlatform.instance.clearTenantConfig();
  }

  Future<bool> clearStoredConfig() {
    return BubblFlutterSdkPlatform.instance.clearStoredConfig();
  }

  Future<Map<String, dynamic>> getDeviceLogStreamInfo() {
    return BubblFlutterSdkPlatform.instance.getDeviceLogStreamInfo();
  }

  Future<List<String>> getDeviceLogTail({int maxLines = 80}) {
    return BubblFlutterSdkPlatform.instance.getDeviceLogTail(
      maxLines: maxLines,
    );
  }

  Future<Map<String, dynamic>> startDeviceLogStream({
    BubblDeviceLogStreamOptions options = const BubblDeviceLogStreamOptions(),
  }) {
    return BubblFlutterSdkPlatform.instance.startDeviceLogStream(
      options.toMap(),
    );
  }

  Future<void> stopDeviceLogStream() {
    return BubblFlutterSdkPlatform.instance.stopDeviceLogStream();
  }

  Future<bool> testNotification() {
    return BubblFlutterSdkPlatform.instance.testNotification();
  }
}
