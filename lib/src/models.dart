class BubblBootOptions {
  const BubblBootOptions({
    this.environment = BubblEnvironment.staging,
    this.segmentationTags = const <String>[],
    this.geoPollIntervalMs,
    this.defaultDistance,
  });

  final BubblEnvironment environment;
  final List<String> segmentationTags;
  final int? geoPollIntervalMs;
  final int? defaultDistance;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'environment': environment.wireName,
      'segmentationTags': segmentationTags,
      if (geoPollIntervalMs != null) 'geoPollIntervalMs': geoPollIntervalMs,
      if (defaultDistance != null) 'defaultDistance': defaultDistance,
    };
  }
}

class BubblBootResult {
  const BubblBootResult({
    required this.initializedNow,
    required this.alreadyInitialized,
    this.restartRequiredForTenantChange = false,
  });

  final bool initializedNow;
  final bool alreadyInitialized;
  final bool restartRequiredForTenantChange;

  factory BubblBootResult.fromMap(Map<String, dynamic> map) {
    return BubblBootResult(
      initializedNow: map['initializedNow'] == true,
      alreadyInitialized: map['alreadyInitialized'] == true,
      restartRequiredForTenantChange:
          map['restartRequiredForTenantChange'] == true,
    );
  }
}

class BubblConfiguration {
  const BubblConfiguration({
    required this.notificationsCount,
    required this.daysCount,
    required this.batteryCount,
    required this.privacyText,
  });

  final int notificationsCount;
  final int daysCount;
  final int batteryCount;
  final String privacyText;

  factory BubblConfiguration.fromMap(Map<String, dynamic> map) {
    return BubblConfiguration(
      notificationsCount: (map['notificationsCount'] as num?)?.toInt() ?? 0,
      daysCount: (map['daysCount'] as num?)?.toInt() ?? 0,
      batteryCount: (map['batteryCount'] as num?)?.toInt() ?? 0,
      privacyText: map['privacyText'] as String? ?? '',
    );
  }
}

class BubblTenantConfig {
  const BubblTenantConfig({
    required this.apiKeyMasked,
    required this.environment,
  });

  final String apiKeyMasked;
  final String environment;

  factory BubblTenantConfig.fromMap(Map<String, dynamic> map) {
    return BubblTenantConfig(
      apiKeyMasked: map['apiKeyMasked'] as String? ?? '',
      environment: map['environment'] as String? ?? 'STAGING',
    );
  }
}

class BubblSendEventParams {
  const BubblSendEventParams({
    required this.curatedNotificationId,
    required this.locationId,
    required this.type,
    required this.activity,
    required this.latitude,
    required this.longitude,
  });

  final String curatedNotificationId;
  final String locationId;
  final String type;
  final String activity;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'curatedNotificationID': curatedNotificationId,
      'locationID': locationId,
      'type': type,
      'activity': activity,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class BubblChoiceSelection {
  const BubblChoiceSelection({required this.choiceId});

  final int choiceId;

  Map<String, dynamic> toMap() => <String, dynamic>{'choice_id': choiceId};
}

class BubblSurveyAnswer {
  const BubblSurveyAnswer({
    required this.questionId,
    required this.type,
    required this.value,
    this.choice,
  });

  final int questionId;
  final String type;
  final String value;
  final List<BubblChoiceSelection>? choice;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'question_id': questionId,
      'type': type,
      'value': value,
      if (choice != null)
        'choice': choice!.map((item) => item.toMap()).toList(),
    };
  }
}

class BubblDeviceLogStreamOptions {
  const BubblDeviceLogStreamOptions({
    this.targetDeviceSuffix,
    this.intervalMs,
    this.maxLines,
  });

  final String? targetDeviceSuffix;
  final int? intervalMs;
  final int? maxLines;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (targetDeviceSuffix != null) 'targetDeviceSuffix': targetDeviceSuffix,
      if (intervalMs != null) 'intervalMs': intervalMs,
      if (maxLines != null) 'maxLines': maxLines,
    };
  }
}

enum BubblEnvironment {
  development,
  staging,
  production;

  String get wireName {
    switch (this) {
      case BubblEnvironment.development:
        return 'DEVELOPMENT';
      case BubblEnvironment.staging:
        return 'STAGING';
      case BubblEnvironment.production:
        return 'PRODUCTION';
    }
  }

  String get nativeIntentDescription {
    switch (this) {
      case BubblEnvironment.development:
        return 'iOS development / Android nightly';
      case BubblEnvironment.staging:
        return 'staging';
      case BubblEnvironment.production:
        return 'production';
    }
  }
}
