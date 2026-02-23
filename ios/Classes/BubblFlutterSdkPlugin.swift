import Bubbl
import Combine
import CoreLocation
import Flutter
import Foundation
import MapKit
import UIKit
import UserNotifications

private final class BubblEventStreamHandler: NSObject, FlutterStreamHandler {
  var onListenHandler: ((Any?, @escaping FlutterEventSink) -> FlutterError?)?
  var onCancelHandler: ((Any?) -> FlutterError?)?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    return onListenHandler?(arguments, events)
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return onCancelHandler?(arguments)
  }
}

public class BubblFlutterSdkPlugin: NSObject, FlutterPlugin, BubblPluginDelegate {
  private enum Keys {
    static let tenantApiKey = "bubbl_api_key"
    static let tenantEnvironment = "bubbl_environment"
  }

  private struct BootConfig: Equatable {
    let apiKey: String
    let environment: String
    let segmentationTags: [String]
    let geoPollIntervalMs: Double?
  }

  private struct TenantConfig: Equatable {
    let apiKey: String
    let environment: String
  }

  private struct GeofenceCircle {
    let centerLatitude: Double
    let centerLongitude: Double
    let radiusMeters: Double
  }

  private let methodChannel: FlutterMethodChannel
  private let notificationStreamHandler = BubblEventStreamHandler()
  private let geofenceStreamHandler = BubblEventStreamHandler()
  private let deviceLogStreamHandler = BubblEventStreamHandler()

  private var notificationSink: FlutterEventSink?
  private var geofenceSink: FlutterEventSink?
  private var deviceLogSink: FlutterEventSink?

  private var hasInitialized = false
  private var hasAuthenticated = false
  private var hasPendingGeofenceRefresh = false
  private var pendingGeofenceCoordinates: (Double, Double)?
  private var activeBootConfig: BootConfig?

  private var geofenceSubscription: AnyCancellable?
  private var notificationDetailsSubscription: AnyCancellable?
  private var locationAuthorizationSubscription: AnyCancellable?
  private var locationAuthorizationTimeout: DispatchWorkItem?

  private var notificationReceivedObserver: NSObjectProtocol?
  private var notificationOpenedObserver: NSObjectProtocol?

  private var pendingNotificationPayloads: [[String: Any]] = []

  private var deviceLogTimer: DispatchSourceTimer?
  private var lastDeviceLogFingerprint = ""

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BubblFlutterSdkPlugin(messenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)

    let notificationChannel = FlutterEventChannel(
      name: "tech.bubbl.sdk/events/notification",
      binaryMessenger: registrar.messenger()
    )
    notificationChannel.setStreamHandler(instance.notificationStreamHandler)

    let geofenceChannel = FlutterEventChannel(
      name: "tech.bubbl.sdk/events/geofence",
      binaryMessenger: registrar.messenger()
    )
    geofenceChannel.setStreamHandler(instance.geofenceStreamHandler)

    let deviceLogChannel = FlutterEventChannel(
      name: "tech.bubbl.sdk/events/device_log",
      binaryMessenger: registrar.messenger()
    )
    deviceLogChannel.setStreamHandler(instance.deviceLogStreamHandler)
  }

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: "tech.bubbl.sdk/methods", binaryMessenger: messenger)
    super.init()
    setupStreamHandlers()
    bindNotificationSources()
    bootstrapFromStoredTenantIfAvailable()
  }

  deinit {
    stopDeviceLogStreamInternal()
    stopGeofenceUpdatesInternal()
    clearLocationAuthorizationWait()

    notificationDetailsSubscription?.cancel()
    notificationDetailsSubscription = nil

    if let observer = notificationReceivedObserver {
      NotificationCenter.default.removeObserver(observer)
      notificationReceivedObserver = nil
    }

    if let observer = notificationOpenedObserver {
      NotificationCenter.default.removeObserver(observer)
      notificationOpenedObserver = nil
    }
  }

  private func setupStreamHandlers() {
    notificationStreamHandler.onListenHandler = { [weak self] _, sink in
      self?.notificationSink = sink
      self?.flushPendingNotificationPayloads()
      return nil
    }
    notificationStreamHandler.onCancelHandler = { [weak self] _ in
      self?.notificationSink = nil
      return nil
    }

    geofenceStreamHandler.onListenHandler = { [weak self] _, sink in
      self?.geofenceSink = sink
      self?.startGeofenceUpdatesInternal()
      return nil
    }
    geofenceStreamHandler.onCancelHandler = { [weak self] _ in
      self?.geofenceSink = nil
      self?.stopGeofenceUpdatesInternal()
      return nil
    }

    deviceLogStreamHandler.onListenHandler = { [weak self] _, sink in
      self?.deviceLogSink = sink
      return nil
    }
    deviceLogStreamHandler.onCancelHandler = { [weak self] _ in
      self?.deviceLogSink = nil
      return nil
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      handleBoot(call, result: result)
    case "boot":
      handleBoot(call, result: result)
    case "requiredPermissions":
      result(["locationWhenInUse", "locationAlways", "pushNotifications"])
    case "locationGranted":
      result(locationPermissionGranted())
    case "notificationGranted":
      notificationPermissionGranted(result: result)
    case "requestPushPermission":
      requestPushPermission(result: result)
    case "startLocationTracking":
      startLocationTracking(result: result)
    case "refreshGeofence":
      refreshGeofence(call, result: result)
    case "updateSegments":
      updateSegments(call, result: result)
    case "setCorrelationId":
      setCorrelationId(call, result: result)
    case "getCorrelationId":
      getCorrelationId(result: result)
    case "clearCorrelationId":
      clearCorrelationId(result: result)
    case "getPrivacyText":
      result(BubblPlugin.shared.getPrivacyText())
    case "refreshPrivacyText":
      refreshPrivacyText(result: result)
    case "getCurrentConfiguration":
      getCurrentConfiguration(result: result)
    case "hasCampaigns":
      guardInitialized(result: result, functionName: "hasCampaigns") {
        result(campaignCountFromCurrentPolygons() > 0)
      }
    case "getCampaignCount":
      guardInitialized(result: result, functionName: "getCampaignCount") {
        result(campaignCountFromCurrentPolygons())
      }
    case "forceRefreshCampaigns":
      guardInitialized(result: result, functionName: "forceRefreshCampaigns") {
        triggerGeofenceRefresh(reason: "forceRefreshCampaigns")
        result(true)
      }
    case "clearCachedCampaigns":
      guardInitialized(result: result, functionName: "clearCachedCampaigns") {
        result(true)
      }
    case "getApiKey":
      result(UserDefaults.standard.string(forKey: Keys.tenantApiKey) ?? "")
    case "sayHello":
      result("Hello from Bubbl iOS bridge")
    case "sendEvent":
      sendEvent(call, result: result)
    case "cta":
      cta(call, result: result)
    case "trackSurveyEvent":
      trackSurveyEvent(call, result: result)
    case "submitSurveyResponse":
      submitSurveyResponse(call, result: result)
    case "startGeofenceUpdates":
      startGeofenceUpdatesInternal()
      result(true)
    case "stopGeofenceUpdates":
      stopGeofenceUpdatesInternal()
      result(true)
    case "clearStoredConfig":
      clearTenantConfigInternal()
      hasInitialized = false
      hasAuthenticated = false
      hasPendingGeofenceRefresh = false
      activeBootConfig = nil
      stopGeofenceUpdatesInternal()
      result(true)
    case "getTenantConfig":
      guard let tenant = loadTenantConfig() else {
        result(nil)
        return
      }
      result([
        "apiKeyMasked": maskApiKey(tenant.apiKey),
        "environment": tenant.environment,
      ])
    case "setTenantConfig":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "BUBBL_TENANT_SET_FAILED", message: "Arguments are required.", details: nil))
        return
      }
      let apiKey = (args["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let environment = (args["environment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "STAGING"
      if apiKey.isEmpty {
        result(FlutterError(code: "BUBBL_TENANT_SET_FAILED", message: "apiKey is required.", details: nil))
        return
      }
      saveTenantConfig(apiKey: apiKey, environment: environment)
      result(true)
    case "clearTenantConfig":
      clearTenantConfigInternal()
      result(true)
    case "getDeviceLogStreamInfo":
      result([
        "deviceType": "ios",
        "deviceId": currentDeviceIdentifier(),
        "deviceIdSuffix": currentDeviceSuffix(),
      ])
    case "getDeviceLogTail":
      let args = call.arguments as? [String: Any]
      let maxLines = max(10, min(200, (args?["maxLines"] as? Int) ?? 80))
      result(readDeviceLogTail(maxLines: maxLines))
    case "startDeviceLogStream":
      startDeviceLogStream(call, result: result)
    case "stopDeviceLogStream":
      stopDeviceLogStreamInternal()
      result(true)
    case "testNotification":
      testNotification(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleBoot(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "BUBBL_BOOT_FAILED", message: "Arguments are required.", details: nil))
      return
    }

    let apiKey = (args["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if apiKey.isEmpty {
      result(FlutterError(code: "BUBBL_BOOT_FAILED", message: "apiKey is required.", details: nil))
      return
    }

    let environment = (args["environment"] as? String) ?? "STAGING"
    let tags = (args["segmentationTags"] as? [String]) ?? []
    let geoPollIntervalMs = (args["geoPollIntervalMs"] as? NSNumber)?.doubleValue

    let nextConfig = normalizedBootConfig(
      apiKey: apiKey,
      environment: environment,
      segmentationTags: tags,
      geoPollIntervalMs: geoPollIntervalMs
    )

    let previousTenant = loadTenantConfig()
    let tenantChanged = previousTenant?.apiKey != nextConfig.apiKey ||
      previousTenant?.environment.uppercased() != nextConfig.environment

    saveTenantConfig(apiKey: nextConfig.apiKey, environment: nextConfig.environment)

    if hasInitialized && !tenantChanged && activeBootConfig == nextConfig && hasAuthenticated {
      startGeofenceUpdatesInternal()
      result([
        "initializedNow": false,
        "alreadyInitialized": true,
        "restartRequiredForTenantChange": false,
      ])
      return
    }

    // If init exists but auth is not established yet, force a clean restart so
    // the caller can recover from stale/failed auth sessions.
    if hasInitialized {
      stopGeofenceUpdatesInternal()
      hasAuthenticated = false
      hasPendingGeofenceRefresh = false
      pendingGeofenceCoordinates = nil
    }

    initializeBubbl(with: nextConfig)
    startGeofenceUpdatesInternal()

    result([
      "initializedNow": true,
      "alreadyInitialized": false,
      "restartRequiredForTenantChange": false,
    ])
  }

  // MARK: Notification bridge

  private func bindNotificationSources() {
    if notificationDetailsSubscription == nil {
      NotificationManager.shared.setAsNotificationDelegate()
      notificationDetailsSubscription = NotificationManager.shared.publisher
        .receive(on: DispatchQueue.main)
        .sink { [weak self] details in
          self?.handleNotificationDetails(details)
        }
    }

    if notificationReceivedObserver == nil {
      notificationReceivedObserver = NotificationCenter.default.addObserver(
        forName: NSNotification.Name("BubblNotificationReceived"),
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let userInfo = notification.userInfo else { return }
        self?.handleNotificationUserInfo(userInfo, source: "received")
      }
    }

    if notificationOpenedObserver == nil {
      notificationOpenedObserver = NotificationCenter.default.addObserver(
        forName: NSNotification.Name("BubblNotificationOpened"),
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let userInfo = notification.userInfo else { return }
        self?.handleNotificationUserInfo(userInfo, source: "opened")
      }
    }
  }

  private func handleNotificationDetails(_ details: BubblNotificationDetails) {
    var payload: [String: Any] = [
      "id": details.notifID,
      "headline": details.headline,
      "body": details.body,
      "locationId": String(details.locationID),
    ]

    if let mediaURL = details.mediaURL {
      payload["mediaUrl"] = mediaURL
    }

    if let mediaType = details.mediaType {
      payload["mediaType"] = mediaType
    }

    if let media = buildMediaArray(mediaURL: details.mediaURL, mediaType: details.mediaType) {
      payload["media"] = media
    }

    if let ctaLabel = details.ctaLabel {
      payload["ctaLabel"] = ctaLabel
    }

    if let ctaURL = details.ctaURL {
      payload["ctaUrl"] = ctaURL
    }

    if let cta = buildCTAArray(label: details.ctaLabel, url: details.ctaURL) {
      payload["cta"] = cta
    }

    if let completionMessage = details.completionMessage {
      payload["postMessage"] = completionMessage
    }

    if let questions = mapQuestions(details.questions) {
      payload["questions"] = questions
    } else {
      payload["questions"] = NSNull()
    }

    payload["raw"] = serializeJSON(payload) ?? "{}"
    emitNotificationPayload(payload)
  }

  private func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any], source: String) {
    guard var payload = mapNotificationPayload(userInfo, source: source) else {
      return
    }

    if payload["raw"] == nil {
      payload["raw"] = serializeJSON(payload) ?? "{}"
    }

    emitNotificationPayload(payload)
  }

  private func emitNotificationPayload(_ payload: [String: Any]) {
    if let sink = notificationSink {
      emitEventOnMainThread(sink, payload: payload)
      return
    }

    pendingNotificationPayloads.append(payload)
    if pendingNotificationPayloads.count > 20 {
      pendingNotificationPayloads.removeFirst(pendingNotificationPayloads.count - 20)
    }
  }

  private func flushPendingNotificationPayloads() {
    guard let sink = notificationSink else { return }
    guard !pendingNotificationPayloads.isEmpty else { return }

    let pending = pendingNotificationPayloads
    pendingNotificationPayloads.removeAll()

    pending.forEach { payload in
      emitEventOnMainThread(sink, payload: payload)
    }
  }

  private func mapNotificationPayload(
    _ userInfo: [AnyHashable: Any],
    source: String
  ) -> [String: Any]? {
    var payload: [String: Any] = extractPayloadJSON(userInfo) ?? [:]
    payload["source"] = source

    var out: [String: Any] = [:]

    if let id = firstValue(
      payload,
      keys: [
        "id",
        "nId",
        "n_id",
        "cnId",
        "notification_id",
        "notificationId",
        "curatedNotificationID",
        "curatedNotificationId",
        "curated_notification_id",
      ]
    ) {
      out["id"] = id
    }

    if let headline = firstStringValue(payload, keys: ["headline", "title", "notificationTitle"]) {
      out["headline"] = headline
    }

    if let body = firstStringValue(payload, keys: ["body", "message", "notificationBody", "con"]) {
      out["body"] = body
    }

    if let mediaURL = firstStringValue(payload, keys: ["mediaUrl", "mediaURL", "media_url"]) {
      out["mediaUrl"] = mediaURL
    }

    if let mediaType = firstStringValue(payload, keys: ["mediaType", "media_type"]) {
      out["mediaType"] = mediaType
    }

    if let media = normalizeMedia(payload["media"]) {
      out["media"] = media
      if let firstMedia = media.first {
        if out["mediaType"] == nil,
           let mediaType = firstMedia["type"] as? String,
           !mediaType.isEmpty
        {
          out["mediaType"] = mediaType
        }
        if out["mediaUrl"] == nil,
           let mediaURL = firstMedia["url"] as? String,
           !mediaURL.isEmpty
        {
          out["mediaUrl"] = mediaURL
        }
      }
    }

    if let activation = firstStringValue(
      payload,
      keys: ["activation", "geofence_activation", "geofenceActivation", "trigger", "eventType", "event_type", "event"]
    ) {
      out["activation"] = activation
    }

    if let ctaLabel = firstStringValue(payload, keys: ["ctaLabel", "cta_label"]) {
      out["ctaLabel"] = ctaLabel
    }

    if let ctaURL = firstStringValue(payload, keys: ["ctaUrl", "cta_url"]) {
      out["ctaUrl"] = ctaURL
    }

    if let cta = normalizeCTA(payload["cta"]) {
      out["cta"] = cta
      if let firstCTA = cta.first {
        if out["ctaLabel"] == nil,
           let ctaLabel = firstCTA["label"] as? String,
           !ctaLabel.isEmpty
        {
          out["ctaLabel"] = ctaLabel
        }
        if out["ctaUrl"] == nil,
           let ctaURL = firstCTA["url"] as? String,
           !ctaURL.isEmpty
        {
          out["ctaUrl"] = ctaURL
        }
      }
    }

    if let locationId = firstValue(
      payload,
      keys: ["locationId", "location_id", "locationID", "location_id_str", "locId", "loc_id", "location"]
    ) {
      out["locationId"] = locationId
    }

    if let campaignId = firstValue(
      payload,
      keys: ["campaignId", "campaign_id", "campaignIdPrimary", "geofenceId", "geofence_id", "cId"]
    ) {
      out["campaignId"] = campaignId
    }

    if let postMessage = firstStringValue(
      payload,
      keys: ["postMessage", "post_message", "completion_message", "completionMessage"]
    ) {
      out["postMessage"] = postMessage
    }

    if let questions = normalizeQuestions(payload["questions"]) {
      out["questions"] = questions
    } else {
      out["questions"] = NSNull()
    }

    if let aps = payload["aps"] as? [String: Any] {
      if out["headline"] == nil || out["body"] == nil {
        if let alert = aps["alert"] as? [String: Any] {
          if out["headline"] == nil, let title = alert["title"] as? String {
            out["headline"] = title
          }

          if out["body"] == nil, let body = alert["body"] as? String {
            out["body"] = body
          }
        } else if let alertText = aps["alert"] as? String {
          if out["headline"] == nil {
            out["headline"] = "Notification"
          }

          if out["body"] == nil {
            out["body"] = alertText
          }
        }
      }
    }

    if let sourceValue = firstStringValue(payload, keys: ["source", "eventSource", "notification_source"]) {
      out["source"] = sourceValue
    }

    let sourceLower = (out["source"] as? String)?.lowercased()
    let transport: String = {
      if sourceLower == "received" || sourceLower == "opened" || sourceLower == "remote" ||
        sourceLower == "apns" || sourceLower == "fcm" || sourceLower == "push" {
        return "remote"
      }

      if sourceLower == "local" || sourceLower == "sdk" {
        return "local"
      }

      if payload["aps"] != nil {
        return "remote"
      }

      return "unknown"
    }()
    out["transport"] = transport

    let activationRaw = (out["activation"] as? String)?.uppercased() ?? ""
    let isGeofenceRelated = activationRaw == "ON_ENTER" || activationRaw == "ON_EXIT" ||
      payload["campaignId"] != nil || payload["campaign_id"] != nil ||
      payload["geofenceId"] != nil || payload["geofence_id"] != nil ||
      ((firstStringValue(payload, keys: ["trigger", "eventType", "event_type", "event"])?.lowercased()
        .contains("geofence")) == true)
    out["isGeofenceRelated"] = isGeofenceRelated
    out["isRemoteGeofenceFallback"] = transport == "remote" && isGeofenceRelated

    out["raw"] = serializeJSON(payload) ?? "{}"

    return out.isEmpty ? nil : out
  }

  private func extractPayloadJSON(_ userInfo: [AnyHashable: Any]) -> [String: Any]? {
    let direct = userInfo.reduce(into: [String: Any]()) { result, entry in
      result[String(describing: entry.key)] = entry.value
    }

    let keys = ["payload", "notification_payload", "data"]
    for key in keys {
      guard let value = direct[key] else { continue }

      if let string = value as? String,
         let data = string.data(using: .utf8),
         let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      {
        return object
      }

      if let dictionary = value as? [String: Any] {
        return dictionary
      }

      if let dictionary = value as? NSDictionary {
        return dictionary as? [String: Any]
      }
    }

    return direct
  }

  private func firstStringValue(_ payload: [String: Any], keys: [String]) -> String? {
    for key in keys {
      guard let value = payload[key] else { continue }

      if let string = value as? String, !string.isEmpty {
        return string
      }

      if let number = value as? NSNumber {
        return number.stringValue
      }
    }

    return nil
  }

  private func firstValue(_ payload: [String: Any], keys: [String]) -> Any? {
    for key in keys {
      guard let value = payload[key] else { continue }

      if let string = value as? String {
        if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return string
        }
        continue
      }

      if value is NSNull {
        continue
      }

      return value
    }

    return nil
  }

  private func normalizeJSONArray(_ value: Any?) -> [Any]? {
    guard let value = value else { return nil }

    if let array = value as? [Any] {
      return array
    }

    if let dictionary = value as? [String: Any] {
      return [dictionary]
    }

    if let dictionary = value as? NSDictionary {
      return [dictionary]
    }

    if let string = value as? String,
       let data = string.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data)
    {
      if let parsedArray = parsed as? [Any] {
        return parsedArray
      }

      if let parsedDictionary = parsed as? [String: Any] {
        return [parsedDictionary]
      }
    }

    return nil
  }

  private func normalizeMedia(_ value: Any?) -> [[String: Any]]? {
    guard let array = normalizeJSONArray(value) else { return nil }

    var normalized: [[String: Any]] = []

    for item in array {
      let media: [String: Any]
      if let dictionary = item as? [String: Any] {
        media = dictionary
      } else if let dictionary = item as? NSDictionary, let cast = dictionary as? [String: Any] {
        media = cast
      } else {
        continue
      }

      var mapped: [String: Any] = [:]

      if let type = firstStringValue(media, keys: ["type", "mediaType", "media_type"]) {
        mapped["type"] = type
      }

      if let url = firstStringValue(media, keys: ["url", "mediaUrl", "mediaURL", "media_url"]) {
        mapped["url"] = url
      }

      if !mapped.isEmpty {
        normalized.append(mapped)
      }
    }

    return normalized.isEmpty ? nil : normalized
  }

  private func normalizeCTA(_ value: Any?) -> [[String: Any]]? {
    guard let array = normalizeJSONArray(value) else { return nil }

    var normalized: [[String: Any]] = []

    for item in array {
      let cta: [String: Any]
      if let dictionary = item as? [String: Any] {
        cta = dictionary
      } else if let dictionary = item as? NSDictionary, let cast = dictionary as? [String: Any] {
        cta = cast
      } else {
        continue
      }

      var mapped: [String: Any] = [:]

      if let label = firstStringValue(cta, keys: ["label", "ctaLabel", "cta_label"]) {
        mapped["label"] = label
      }

      if let url = firstStringValue(cta, keys: ["url", "ctaUrl", "cta_url"]) {
        mapped["url"] = url
      }

      if !mapped.isEmpty {
        normalized.append(mapped)
      }
    }

    return normalized.isEmpty ? nil : normalized
  }

  private func buildMediaArray(mediaURL: String?, mediaType: String?) -> [[String: Any]]? {
    guard let mediaURL, !mediaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }

    var mediaItem: [String: Any] = ["url": mediaURL]
    if let mediaType, !mediaType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      mediaItem["type"] = mediaType
    }

    return [mediaItem]
  }

  private func buildCTAArray(label: String?, url: String?) -> [[String: Any]]? {
    var ctaItem: [String: Any] = [:]

    if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      ctaItem["label"] = label
    }

    if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      ctaItem["url"] = url
    }

    return ctaItem.isEmpty ? nil : [ctaItem]
  }

  private func normalizeQuestions(_ value: Any?) -> [[String: Any]]? {
    guard let value = value else { return nil }

    if let array = value as? [Any] {
      return mapQuestionArray(array)
    }

    if let string = value as? String,
       let data = string.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any]
    {
      return mapQuestionArray(parsed)
    }

    return nil
  }

  private func mapQuestionArray(_ questions: [Any]) -> [[String: Any]] {
    var mappedQuestions: [[String: Any]] = []

    for item in questions {
      guard let q = item as? [String: Any] else { continue }
      var mapped: [String: Any] = [:]

      if let id = q["id"] {
        mapped["id"] = id
      }

      if let question = q["question"] as? String {
        mapped["question"] = question
      }

      if let questionType = q["question_type"] ?? q["questionType"] {
        mapped["question_type"] = questionType
      }

      if let hasChoices = q["has_choices"] ?? q["hasChoices"] {
        mapped["has_choices"] = hasChoices
      }

      if let position = q["position"] {
        mapped["position"] = position
      }

      if let rawChoices = q["choices"] as? [Any] {
        var mappedChoices: [[String: Any]] = []

        for choiceValue in rawChoices {
          guard let choice = choiceValue as? [String: Any] else { continue }

          var mappedChoice: [String: Any] = [:]
          if let id = choice["id"] {
            mappedChoice["id"] = id
          }
          if let label = choice["choice"] {
            mappedChoice["choice"] = label
          }
          if let position = choice["position"] {
            mappedChoice["position"] = position
          }
          mappedChoices.append(mappedChoice)
        }

        mapped["choices"] = mappedChoices
      } else {
        mapped["choices"] = []
      }

      mappedQuestions.append(mapped)
    }

    return mappedQuestions
  }

  private func mapQuestions(_ questions: [SurveyQuestion]?) -> [[String: Any]]? {
    guard let questions = questions else { return nil }

    return questions.map { question in
      var mapped: [String: Any] = [
        "id": question.id,
        "question": question.question,
        "has_choices": question.hasChoices,
        "position": question.position,
      ]

      if let questionType = question.questionType {
        mapped["question_type"] = questionType.rawValue
      }

      if let choices = question.choices {
        mapped["choices"] = choices.map { choice in
          [
            "id": choice.id,
            "choice": choice.choice,
            "position": choice.position,
          ]
        }
      } else {
        mapped["choices"] = []
      }

      return mapped
    }
  }

  // MARK: Boot helpers

  private func normalizedBootConfig(
    apiKey: String,
    environment: String,
    segmentationTags: [String],
    geoPollIntervalMs: Double?
  ) -> BootConfig {
    let normalizedTags = segmentationTags
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let normalizedPollMs: Double?
    if let geoPollIntervalMs, geoPollIntervalMs > 0 {
      normalizedPollMs = geoPollIntervalMs
    } else {
      normalizedPollMs = nil
    }

    return BootConfig(
      apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
      environment: environment.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      segmentationTags: normalizedTags,
      geoPollIntervalMs: normalizedPollMs
    )
  }

  private func environmentFrom(_ value: String) -> Config.Environment {
    switch value.uppercased() {
    case "PRODUCTION":
      return .production
    case "DEVELOPMENT":
      return .development
    default:
      return .staging
    }
  }

  private func initializeBubbl(with config: BootConfig) {
    hasInitialized = true
    hasAuthenticated = false
    activeBootConfig = config

    applyPollingOverrideIfSupported(config: config)

    BubblPlugin.shared.start(
      apiKey: config.apiKey,
      env: environmentFrom(config.environment),
      segmentations: config.segmentationTags,
      delegate: self
    )
  }

  private func bootstrapFromStoredTenantIfAvailable() {
    guard let tenant = loadTenantConfig() else {
      return
    }

    guard !hasInitialized else {
      return
    }

    initializeBubbl(
      with: BootConfig(
        apiKey: tenant.apiKey,
        environment: tenant.environment,
        segmentationTags: [],
        geoPollIntervalMs: nil
      )
    )
  }

  public func bubblPlugin(_ plugin: BubblPlugin, didAuthenticate deviceID: String, bubblID: String) {
    hasAuthenticated = true

    if hasPendingGeofenceRefresh {
      let pendingCoordinates = pendingGeofenceCoordinates
      hasPendingGeofenceRefresh = false
      pendingGeofenceCoordinates = nil
      triggerGeofenceRefresh(
        reason: "postAuthenticationPendingRefresh",
        latitude: pendingCoordinates?.0,
        longitude: pendingCoordinates?.1
      )
    }
  }

  public func bubblPlugin(_ plugin: BubblPlugin, didFailWith error: Error) {
    hasAuthenticated = false
    NSLog("[Bubbl] Authentication failed: %@", error.localizedDescription)
  }

  private func guardInitialized(result: @escaping FlutterResult, functionName: String, block: () -> Void) {
    guard hasInitialized else {
      result(FlutterError(
        code: "BUBBL_NOT_INITIALIZED",
        message: "Call Bubbl.boot(...) before calling \(functionName)().",
        details: nil
      ))
      return
    }

    block()
  }

  private func applyPollingOverrideIfSupported(config: BootConfig) {
    guard let pollMs = config.geoPollIntervalMs else {
      return
    }

    let foregroundSeconds = max(60.0, pollMs / 1000.0)
    let backgroundSeconds = max(foregroundSeconds, foregroundSeconds * 6.0)
    let selector = NSSelectorFromString("configureGeofencePollingWithForegroundInterval:backgroundInterval:")
    let target = BubblPlugin.shared as NSObject

    guard target.responds(to: selector) else {
      return
    }

    _ = target.perform(
      selector,
      with: NSNumber(value: foregroundSeconds),
      with: NSNumber(value: backgroundSeconds)
    )
  }

  private func refetchGeofenceWithCoordinatesIfAvailable(latitude: Double, longitude: Double) -> Bool {
    let selector = NSSelectorFromString("refetchGeofenceWithLatitude:longitude:")
    let target = BubblPlugin.shared as NSObject

    guard target.responds(to: selector) else {
      return false
    }

    _ = target.perform(
      selector,
      with: NSNumber(value: latitude),
      with: NSNumber(value: longitude)
    )
    return true
  }

  private func triggerGeofenceRefresh(
    reason: String,
    latitude: Double? = nil,
    longitude: Double? = nil
  ) {
    let explicitCoordinates: (Double, Double)? = {
      guard let latitude, let longitude else { return nil }
      return (latitude, longitude)
    }()

    if !hasInitialized {
      hasPendingGeofenceRefresh = true
      pendingGeofenceCoordinates = explicitCoordinates ?? pendingGeofenceCoordinates
      NSLog("[Bubbl] Queued geofence refresh (%@) until SDK init.", reason)
      return
    }

    if !hasAuthenticated {
      hasPendingGeofenceRefresh = true
      pendingGeofenceCoordinates = explicitCoordinates ?? pendingGeofenceCoordinates
      NSLog("[Bubbl] Queued geofence refresh (%@) until authentication.", reason)
      return
    }

    pendingGeofenceCoordinates = nil

    if let coordinates = explicitCoordinates,
       refetchGeofenceWithCoordinatesIfAvailable(
         latitude: coordinates.0,
         longitude: coordinates.1
       )
    {
      return
    }

    BubblPlugin.shared.refetchGeofence()
  }

  private func clearLocationAuthorizationWait() {
    locationAuthorizationSubscription?.cancel()
    locationAuthorizationSubscription = nil
    locationAuthorizationTimeout?.cancel()
    locationAuthorizationTimeout = nil
  }

  private func serializeJSON(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value) else {
      return nil
    }

    guard let data = try? JSONSerialization.data(withJSONObject: value, options: []) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  private func saveTenantConfig(apiKey: String, environment: String) {
    UserDefaults.standard.set(apiKey, forKey: Keys.tenantApiKey)
    UserDefaults.standard.set(environment, forKey: Keys.tenantEnvironment)
  }

  private func loadTenantConfig() -> TenantConfig? {
    guard
      let apiKey = UserDefaults.standard.string(forKey: Keys.tenantApiKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty,
      let environment = UserDefaults.standard.string(forKey: Keys.tenantEnvironment)
    else {
      return nil
    }

    return TenantConfig(apiKey: apiKey, environment: environment)
  }

  private func clearTenantConfigInternal() {
    UserDefaults.standard.removeObject(forKey: Keys.tenantApiKey)
    UserDefaults.standard.removeObject(forKey: Keys.tenantEnvironment)
  }

  private func maskApiKey(_ apiKey: String) -> String {
    if apiKey.count <= 8 {
      return "****"
    }

    let start = apiKey.prefix(4)
    let end = apiKey.suffix(4)
    return "\(start)****\(end)"
  }

  private func currentDeviceIdentifier() -> String {
    UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
  }

  private func currentDeviceSuffix() -> String {
    let normalized = currentDeviceIdentifier().replacingOccurrences(
      of: "[^A-Za-z0-9]",
      with: "",
      options: .regularExpression
    )

    if normalized.isEmpty {
      return "-----"
    }

    return String(normalized.suffix(5))
  }

  private func campaignCountFromCurrentPolygons() -> Int {
    GeofenceService.shared.currentPolygons.count
  }

  // MARK: Geofence stream

  private func deriveGeofenceCircle(vertices: [CLLocationCoordinate2D]) -> GeofenceCircle? {
    guard !vertices.isEmpty else { return nil }

    let centerLatitude = vertices.reduce(0.0) { $0 + $1.latitude } / Double(vertices.count)
    let centerLongitude = vertices.reduce(0.0) { $0 + $1.longitude } / Double(vertices.count)

    let centerLocation = CLLocation(latitude: centerLatitude, longitude: centerLongitude)
    var radiusMeters = 0.0

    vertices.forEach { vertex in
      let location = CLLocation(latitude: vertex.latitude, longitude: vertex.longitude)
      radiusMeters = max(radiusMeters, centerLocation.distance(from: location))
    }

    return GeofenceCircle(
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      radiusMeters: radiusMeters
    )
  }

  private func emitGeofenceSnapshot(polygons: [MKPolygon]) {
    guard let sink = geofenceSink else { return }

    let mappedPolygons: [[String: Any]] = polygons.enumerated().map { index, polygon in
      let vertices = polygon.bubblCoordinates.map { coord in
        [
          "latitude": coord.latitude,
          "longitude": coord.longitude,
        ]
      }

      let campaignName = polygon.title ?? "campaign-\(index)"

      return [
        "campaignId": index,
        "campaignName": campaignName,
        "vertices": vertices,
      ]
    }

    let mappedCircles: [[String: Any]] = polygons.enumerated().compactMap { index, polygon in
      guard let circle = deriveGeofenceCircle(vertices: polygon.bubblCoordinates) else { return nil }
      let campaignName = polygon.title ?? "campaign-\(index)"

      return [
        "campaignId": index,
        "campaignName": campaignName,
        "center": [
          "latitude": circle.centerLatitude,
          "longitude": circle.centerLongitude,
        ],
        "radius": circle.radiusMeters,
      ]
    }

    emitEventOnMainThread(sink, payload: [
      "stats": [
        "campaignsTotal": mappedPolygons.count,
        "polygonsTotal": mappedPolygons.count,
      ],
      "polygons": mappedPolygons,
      "circles": mappedCircles,
    ])
  }

  private func startGeofenceUpdatesInternal() {
    guard hasInitialized else { return }
    guard geofenceSubscription == nil else { return }

    geofenceSubscription = GeofenceService.shared.polygonsPublisherPublic
      .receive(on: DispatchQueue.main)
      .sink { [weak self] polygons in
        self?.emitGeofenceSnapshot(polygons: polygons)
      }

    emitGeofenceSnapshot(polygons: GeofenceService.shared.currentPolygons)
  }

  private func stopGeofenceUpdatesInternal() {
    geofenceSubscription?.cancel()
    geofenceSubscription = nil
  }

  // MARK: Device logs

  private func readDeviceLogTail(maxLines: Int) -> [String] {
    let url = Logger.shared.logFileURL

    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
      return []
    }

    let lines = content.split(whereSeparator: \.isNewline).map(String.init)
    if lines.count <= maxLines {
      return lines
    }

    return Array(lines.suffix(maxLines))
  }

  private func emitDeviceLogSnapshot(maxLines: Int, force: Bool) {
    let lines = readDeviceLogTail(maxLines: maxLines)
    let fingerprint = lines.joined(separator: "\n")

    if !force && fingerprint == lastDeviceLogFingerprint {
      return
    }

    lastDeviceLogFingerprint = fingerprint

    guard let sink = deviceLogSink else {
      return
    }

    emitEventOnMainThread(sink, payload: [
      "deviceType": "ios",
      "deviceId": currentDeviceIdentifier(),
      "deviceIdSuffix": currentDeviceSuffix(),
      "timestamp": Date().timeIntervalSince1970 * 1000,
      "lines": lines,
    ])
  }

  private func emitEventOnMainThread(_ sink: @escaping FlutterEventSink, payload: Any?) {
    if Thread.isMainThread {
      sink(payload)
      return
    }

    DispatchQueue.main.async {
      sink(payload)
    }
  }

  private func stopDeviceLogStreamInternal() {
    deviceLogTimer?.setEventHandler {}
    deviceLogTimer?.cancel()
    deviceLogTimer = nil
  }

  // MARK: Method handlers

  private func locationPermissionGranted() -> Bool {
    let status = CLLocationManager.authorizationStatus()
    return status == .authorizedAlways || status == .authorizedWhenInUse
  }

  private func notificationPermissionGranted(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let granted =
        settings.authorizationStatus == .authorized ||
        settings.authorizationStatus == .provisional ||
        settings.authorizationStatus == .ephemeral
      result(granted)
    }
  }

  private func requestPushPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        result(FlutterError(code: "BUBBL_PUSH_PERMISSION_FAILED", message: error.localizedDescription, details: nil))
        return
      }

      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }

      result(granted)
    }
  }

  private func startLocationTracking(result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "startLocationTracking") {
      let initialStatus = CLLocationManager.authorizationStatus()
      if initialStatus == .authorizedAlways {
        triggerGeofenceRefresh(reason: "startLocationTracking")
        result(true)
        return
      }

      if initialStatus == .denied || initialStatus == .restricted {
        result(false)
        return
      }

      BubblPlugin.shared.requestLocationWhenInUse()
      BubblPlugin.shared.requestLocationAlways()
      clearLocationAuthorizationWait()

      var didResolve = false
      let resolveOnce: (Bool) -> Void = { value in
        guard !didResolve else { return }
        didResolve = true
        result(value)
      }

      let timeoutWorkItem = DispatchWorkItem { [weak self] in
        guard let self else {
          resolveOnce(false)
          return
        }

        self.clearLocationAuthorizationWait()
        let status = CLLocationManager.authorizationStatus()
        if status == .authorizedAlways {
          self.triggerGeofenceRefresh(reason: "startLocationTracking")
          resolveOnce(true)
        } else {
          resolveOnce(false)
        }
      }

      locationAuthorizationTimeout = timeoutWorkItem
      DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: timeoutWorkItem)

      locationAuthorizationSubscription = BubblPlugin.locationAuthorizationPublisher
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status in
          guard let self else {
            resolveOnce(false)
            return
          }

          switch status {
          case .authorizedAlways:
            self.clearLocationAuthorizationWait()
            self.triggerGeofenceRefresh(reason: "startLocationTracking")
            resolveOnce(true)
          case .authorizedWhenInUse, .denied, .restricted:
            self.clearLocationAuthorizationWait()
            resolveOnce(false)
          case .notDetermined:
            break
          @unknown default:
            self.clearLocationAuthorizationWait()
            resolveOnce(false)
          }
        }
    }
  }

  private func refreshGeofence(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "refreshGeofence") {
      let args = call.arguments as? [String: Any]
      let latitude = (args?["latitude"] as? NSNumber)?.doubleValue
      let longitude = (args?["longitude"] as? NSNumber)?.doubleValue
      triggerGeofenceRefresh(reason: "refreshGeofence", latitude: latitude, longitude: longitude)
      result(true)
    }
  }

  private func updateSegments(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "updateSegments") {
      let args = call.arguments as? [String: Any]
      let tags = (args?["tags"] as? [String]) ?? []

      BubblPlugin.shared.updateSegments(segmentations: tags) { updateResult in
        switch updateResult {
        case .success:
          result(true)
        case .failure(let error):
          result(FlutterError(code: "BUBBL_SEGMENTS_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func setCorrelationId(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "setCorrelationId") {
      let args = call.arguments as? [String: Any]
      let correlationId = (args?["correlationId"] as? String) ?? ""
      BubblPlugin.shared.setCorrelationId(correlationId)
      result(true)
    }
  }

  private func getCorrelationId(result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "getCorrelationId") {
      result(BubblPlugin.shared.getCorrelationId())
    }
  }

  private func clearCorrelationId(result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "clearCorrelationId") {
      BubblPlugin.shared.clearCorrelationId()
      result(true)
    }
  }

  private func refreshPrivacyText(result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "refreshPrivacyText") {
      BubblPlugin.shared.refreshPrivacyText { refreshResult in
        switch refreshResult {
        case .success(let text):
          result(text)
        case .failure(let error):
          result(FlutterError(code: "BUBBL_PRIVACY_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func getCurrentConfiguration(result: @escaping FlutterResult) {
    guard let config = BubblPlugin.shared.getCurrentConfiguration() else {
      result(nil)
      return
    }

    result([
      "notificationsCount": config.notificationsCount,
      "daysCount": config.daysCount,
      "batteryCount": config.batteryCount,
      "privacyText": config.privacyText,
    ])
  }

  private func sendEvent(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "sendEvent") {
      let args = call.arguments as? [String: Any] ?? [:]

      let curatedNotificationID = (args["curatedNotificationID"] as? String) ?? ""
      let locationID = (args["locationID"] as? String) ?? ""
      let type = (args["type"] as? String) ?? ""
      let activity = (args["activity"] as? String) ?? ""

      let parsedNotificationType = parseNotificationType(type)
      let parsedActivityType = parseActivityType(activity)
      let parsedLocationID = Int(locationID)
      let parsedNotificationID = Int(curatedNotificationID)

      if let notificationType = parsedNotificationType,
         let activityType = parsedActivityType,
         let locationIdInt = parsedLocationID,
         let notificationIdInt = parsedNotificationID
      {
        NotificationManager.shared.reportNotification(
          activity: activityType,
          locationID: locationIdInt,
          curatedNotificationID: notificationIdInt,
          type: notificationType
        )
        result(true)
        return
      }

      BubblPlugin.shared.trackSurveyEvent(
        notificationId: curatedNotificationID,
        locationId: locationID,
        activity: activity
      ) { trackResult in
        switch trackResult {
        case .success(let success):
          result(success)
        case .failure(let error):
          result(FlutterError(code: "BUBBL_SEND_EVENT_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func cta(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "cta") {
      let args = call.arguments as? [String: Any] ?? [:]
      let notificationId = (args["notificationId"] as? NSNumber)?.intValue ?? 0
      let locationId = (args["locationId"] as? String) ?? ""

      if let parsedLocationID = Int(locationId) {
        NotificationManager.shared.trackCTAEngagement(
          notificationID: notificationId,
          locationID: parsedLocationID
        )
        result(true)
        return
      }

      BubblPlugin.shared.trackSurveyEvent(
        notificationId: String(notificationId),
        locationId: locationId,
        activity: "cta_engagement"
      ) { _ in }

      result(true)
    }
  }

  private func trackSurveyEvent(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "trackSurveyEvent") {
      let args = call.arguments as? [String: Any] ?? [:]
      let notificationId = (args["notificationId"] as? String) ?? ""
      let locationId = (args["locationId"] as? String) ?? ""
      let activity = (args["activity"] as? String) ?? ""

      BubblPlugin.shared.trackSurveyEvent(
        notificationId: notificationId,
        locationId: locationId,
        activity: activity
      ) { trackResult in
        switch trackResult {
        case .success(let success):
          result(success)
        case .failure(let error):
          result(FlutterError(code: "BUBBL_SURVEY_EVENT_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func submitSurveyResponse(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guardInitialized(result: result, functionName: "submitSurveyResponse") {
      let args = call.arguments as? [String: Any] ?? [:]
      let notificationId = (args["notificationId"] as? String) ?? ""
      let locationId = (args["locationId"] as? String) ?? ""
      let answers = (args["answers"] as? [NSDictionary]) ?? []

      let parsedAnswers = parseSurveyAnswers(answers as NSArray)

      BubblPlugin.shared.submitSurveyResponse(
        notificationId: notificationId,
        locationId: locationId,
        answers: parsedAnswers
      ) { submitResult in
        switch submitResult {
        case .success(let success):
          result(success)
        case .failure(let error):
          result(FlutterError(code: "BUBBL_SURVEY_SUBMIT_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func startDeviceLogStream(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let options = call.arguments as? [String: Any] ?? [:]

    let intervalRaw = (options["intervalMs"] as? NSNumber)?.doubleValue ?? 2500
    let maxLinesRaw = (options["maxLines"] as? NSNumber)?.intValue ?? 80
    let targetSuffix = ((options["targetDeviceSuffix"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    let intervalMs = max(1000.0, min(30000.0, intervalRaw))
    let maxLines = max(10, min(200, maxLinesRaw))
    let currentSuffix = currentDeviceSuffix().lowercased()

    if !targetSuffix.isEmpty, targetSuffix != currentSuffix {
      result([
        "started": false,
        "reason": "device_suffix_mismatch",
        "deviceIdSuffix": currentDeviceSuffix(),
      ])
      return
    }

    stopDeviceLogStreamInternal()
    lastDeviceLogFingerprint = ""
    emitDeviceLogSnapshot(maxLines: maxLines, force: true)

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(
      deadline: .now() + .milliseconds(Int(intervalMs)),
      repeating: .milliseconds(Int(intervalMs))
    )
    timer.setEventHandler { [weak self] in
      self?.emitDeviceLogSnapshot(maxLines: maxLines, force: false)
    }
    timer.resume()
    deviceLogTimer = timer

    result([
      "started": true,
      "reason": "ok",
      "deviceIdSuffix": currentDeviceSuffix(),
    ])
  }

  private func testNotification(result: @escaping FlutterResult) {
    let id = Int(Date().timeIntervalSince1970)
    let payload: [String: Any] = [
      "id": id,
      "headline": "Test Notification",
      "body": "This is a local test notification from Bubbl Flutter SDK.",
      "locationId": "test-location",
      "postMessage": "Thanks for testing",
    ]

    var emitPayload = payload
    emitPayload["raw"] = serializeJSON(payload) ?? "{}"
    emitNotificationPayload(emitPayload)

    let content = UNMutableNotificationContent()
    content.title = "Test Notification"
    content.body = "This is a local test notification from Bubbl Flutter SDK."
    content.sound = .default
    content.userInfo = ["payload": payload]

    let request = UNNotificationRequest(
      identifier: "bubbl_test_\(id)",
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        result(FlutterError(code: "BUBBL_TEST_NOTIFICATION_FAILED", message: error.localizedDescription, details: nil))
        return
      }

      result(true)
    }
  }

  // MARK: Event mapping helpers

  private func parseNotificationType(_ raw: String) -> NotificationType? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "notification":
      return .notification
    case "location":
      return .location
    case "geofence":
      return .geofence
    default:
      return nil
    }
  }

  private func parseActivityType(_ raw: String) -> ActivityType? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "cta_engagement":
      return .ctaEngagement
    case "notification_sent":
      return .notificationSent
    case "notification_delivered":
      return .notificationDelivered
    case "media_viewed":
      return .mediaViewed
    case "location_update":
      return .location_update
    case "geofence_exit":
      return .geofence_exit
    case "geofence_entry":
      return .geofence_entry
    default:
      return nil
    }
  }

  private func normalizeSurveyType(_ type: String, choiceCount: Int) -> String {
    let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
    let canonical = trimmed
      .lowercased()
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: " ", with: "")

    if canonical.isEmpty {
      return choiceCount > 0 ? "singleChoice" : "openEnded"
    }

    switch canonical {
    case "choice":
      return choiceCount > 1 ? "multipleChoice" : "singleChoice"
    case "singlechoice", "radio":
      return "singleChoice"
    case "multiplechoice", "checkbox", "checkboxes":
      return "multipleChoice"
    case "text", "openended", "openendedtext":
      return "openEnded"
    case "number", "numeric", "integer", "int":
      return "number"
    case "boolean", "bool", "yesno":
      return "boolean"
    case "rating", "star", "stars":
      return "rating"
    case "slider", "range":
      return "slider"
    default:
      return trimmed
    }
  }

  private func parseSurveyAnswers(_ answers: NSArray) -> [SurveyAnswer] {
    var parsed: [SurveyAnswer] = []

    for case let dictionary as NSDictionary in answers {
      let questionIDValue = dictionary["question_id"]
      let questionID: Int
      if let value = questionIDValue as? NSNumber {
        questionID = value.intValue
      } else if let value = questionIDValue as? Int {
        questionID = value
      } else {
        continue
      }

      let rawType = (dictionary["type"] as? String) ?? ""
      let value = (dictionary["value"] as? String) ?? ""

      var selections: [ChoiceSelection]? = nil
      if let choices = dictionary["choice"] as? [NSDictionary] {
        let mappedSelections = choices.compactMap { choice -> ChoiceSelection? in
          if let choiceId = choice["choice_id"] as? NSNumber {
            return ChoiceSelection(choiceId: choiceId.intValue)
          }

          if let choiceId = choice["choice_id"] as? Int {
            return ChoiceSelection(choiceId: choiceId)
          }

          return nil
        }

        if !mappedSelections.isEmpty {
          selections = mappedSelections
        }
      }

      let normalizedType = normalizeSurveyType(rawType, choiceCount: selections?.count ?? 0)

      parsed.append(
        SurveyAnswer(
          questionId: questionID,
          type: normalizedType,
          value: value,
          choice: selections
        )
      )
    }

    return parsed
  }
}

private extension MKPolygon {
  var bubblCoordinates: [CLLocationCoordinate2D] {
    guard pointCount > 0 else { return [] }
    var coordinates = [CLLocationCoordinate2D](
      repeating: kCLLocationCoordinate2DInvalid,
      count: pointCount
    )
    getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
    return coordinates
  }
}
