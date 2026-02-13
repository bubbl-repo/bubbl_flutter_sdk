package tech.bubbl.bubbl_flutter_sdk

import android.Manifest
import android.app.Activity
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.google.firebase.FirebaseApp
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import tech.bubbl.sdk.BubblSdk
import tech.bubbl.sdk.config.BubblConfig
import tech.bubbl.sdk.config.Environment
import tech.bubbl.sdk.models.ChoiceSelection
import tech.bubbl.sdk.models.SurveyAnswer
import tech.bubbl.sdk.notifications.NotificationRouter
import tech.bubbl.sdk.utils.Logger
import java.util.Locale

private const val METHOD_CHANNEL_NAME = "tech.bubbl.sdk/methods"
private const val NOTIFICATION_EVENT_CHANNEL_NAME = "tech.bubbl.sdk/events/notification"
private const val GEOFENCE_EVENT_CHANNEL_NAME = "tech.bubbl.sdk/events/geofence"
private const val DEVICE_LOG_EVENT_CHANNEL_NAME = "tech.bubbl.sdk/events/device_log"
private const val REQUEST_POST_NOTIFICATIONS = 24891

private object BubblInitState {
    @Volatile
    var initialized: Boolean = false
}

class BubblFlutterSdkPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel

    private lateinit var notificationEventChannel: EventChannel
    private lateinit var geofenceEventChannel: EventChannel
    private lateinit var deviceLogEventChannel: EventChannel

    private var notificationSink: EventChannel.EventSink? = null
    private var geofenceSink: EventChannel.EventSink? = null
    private var deviceLogSink: EventChannel.EventSink? = null

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var geofenceJob: Job? = null
    private var deviceLogJob: Job? = null

    @Volatile
    private var lastDeviceLogFingerprint: String = ""

    private var notificationBridgeRegistered = false
    private var pendingPushPermissionResult: MethodChannel.Result? = null

    private var deviceLogIntervalMs: Long = 2500L
    private var deviceLogMaxLines: Int = 80

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val json = intent?.getStringExtra("payload") ?: return
            emitNotification(json)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        notificationEventChannel = EventChannel(binding.binaryMessenger, NOTIFICATION_EVENT_CHANNEL_NAME)
        notificationEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    notificationSink = events
                    ensureNotificationBridge()
                }

                override fun onCancel(arguments: Any?) {
                    notificationSink = null
                }
            },
        )

        geofenceEventChannel = EventChannel(binding.binaryMessenger, GEOFENCE_EVENT_CHANNEL_NAME)
        geofenceEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    geofenceSink = events
                    startGeofenceCollectionIfPossible()
                }

                override fun onCancel(arguments: Any?) {
                    geofenceSink = null
                    stopGeofenceCollection()
                }
            },
        )

        deviceLogEventChannel = EventChannel(binding.binaryMessenger, DEVICE_LOG_EVENT_CHANNEL_NAME)
        deviceLogEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    deviceLogSink = events

                    if (arguments is Map<*, *>) {
                        configureDeviceLogStream(arguments)
                    }

                    emitDeviceLogSnapshot(force = true)
                }

                override fun onCancel(arguments: Any?) {
                    deviceLogSink = null
                }
            },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopGeofenceCollection()
        stopDeviceLogStream()
        unregisterNotificationBridge()

        methodChannel.setMethodCallHandler(null)
        notificationEventChannel.setStreamHandler(null)
        geofenceEventChannel.setStreamHandler(null)
        deviceLogEventChannel.setStreamHandler(null)

        pendingPushPermissionResult = null
        scope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachFromActivity()
    }

    private fun detachFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> handleBoot(call, result)
            "boot" -> handleBoot(call, result)
            "requiredPermissions" -> result.success(requiredPermissions())
            "locationGranted" -> result.success(locationGranted())
            "notificationGranted" -> result.success(notificationGranted())
            "requestPushPermission" -> requestPushPermission(result)
            "startLocationTracking" -> startLocationTracking(result)
            "refreshGeofence" -> refreshGeofence(call, result)
            "updateSegments" -> updateSegments(call, result)
            "setCorrelationId" -> setCorrelationId(call, result)
            "getCorrelationId" -> getCorrelationId(result)
            "clearCorrelationId" -> clearCorrelationId(result)
            "getPrivacyText" -> result.success(BubblSdk.getPrivacyText())
            "refreshPrivacyText" -> refreshPrivacyText(result)
            "getCurrentConfiguration" -> getCurrentConfiguration(result)
            "hasCampaigns" -> guarded(result, "hasCampaigns") { result.success(BubblSdk.hasCampaigns()) }
            "getCampaignCount" -> guarded(result, "getCampaignCount") { result.success(BubblSdk.getCampaignCount()) }
            "forceRefreshCampaigns" -> guarded(result, "forceRefreshCampaigns") {
                BubblSdk.forceRefreshCampaigns()
                result.success(true)
            }
            "clearCachedCampaigns" -> guarded(result, "clearCachedCampaigns") {
                BubblSdk.clearCachedCampaigns()
                result.success(true)
            }
            "getApiKey" -> result.success(BubblSdk.getApiKey)
            "sayHello" -> result.success(BubblSdk.sayHello())
            "sendEvent" -> sendEvent(call, result)
            "cta" -> cta(call, result)
            "trackSurveyEvent" -> trackSurveyEvent(call, result)
            "submitSurveyResponse" -> submitSurveyResponse(call, result)
            "getTenantConfig" -> getTenantConfig(result)
            "setTenantConfig" -> setTenantConfig(call, result)
            "clearTenantConfig" -> {
                TenantConfigStore.clear(applicationContext)
                result.success(true)
            }
            "clearStoredConfig" -> {
                TenantConfigStore.clear(applicationContext)
                BubblInitState.initialized = false
                stopGeofenceCollection()
                result.success(true)
            }
            "getDeviceLogStreamInfo" -> result.success(
                mapOf(
                    "deviceType" to "android",
                    "deviceId" to currentDeviceId(),
                    "deviceIdSuffix" to currentDeviceSuffix(),
                ),
            )
            "getDeviceLogTail" -> {
                val maxLines = (call.argument<Number>("maxLines")?.toInt() ?: 80).coerceIn(10, 200)
                result.success(readDeviceLogTail(maxLines))
            }
            "startDeviceLogStream" -> startDeviceLogStream(call, result)
            "stopDeviceLogStream" -> {
                stopDeviceLogStream()
                result.success(true)
            }
            "startGeofenceUpdates" -> {
                startGeofenceCollectionIfPossible()
                result.success(true)
            }
            "stopGeofenceUpdates" -> {
                stopGeofenceCollection()
                result.success(true)
            }
            "testNotification" -> testNotification(result)
            else -> result.notImplemented()
        }
    }

    private fun handleBoot(call: MethodCall, result: MethodChannel.Result) {
        val apiKey = call.argument<String>("apiKey")?.trim().orEmpty()
        if (apiKey.isEmpty()) {
            result.error("BUBBL_BOOT_FAILED", "apiKey is required.", null)
            return
        }

        val env = parseEnvironment(call.argument<String>("environment"))
        val segmentationTags =
            (call.argument<List<Any?>>("segmentationTags") ?: emptyList())
                .mapNotNull { it as? String }
                .map { it.trim() }
                .filter { it.isNotEmpty() }

        val pollMs = (call.argument<Number>("geoPollIntervalMs")?.toLong() ?: 300_000L).coerceAtLeast(60_000L)
        val defaultDistance = (call.argument<Number>("defaultDistance")?.toInt() ?: 25).coerceAtLeast(1)

        val previousTenant = TenantConfigStore.load(applicationContext)
        val tenantChanged =
            previousTenant == null ||
                previousTenant.apiKey != apiKey ||
                previousTenant.environment != env

        TenantConfigStore.save(applicationContext, apiKey, env)

        if (BubblInitState.initialized && tenantChanged) {
            result.success(
                mapOf(
                    "initializedNow" to false,
                    "alreadyInitialized" to true,
                    "restartRequiredForTenantChange" to true,
                ),
            )
            return
        }

        if (!ensureFirebaseInitialized()) {
            result.error(
                "BUBBL_FIREBASE_NOT_INITIALIZED",
                "FirebaseApp is not initialized. Add android/app/google-services.json configured for package ${applicationContext.packageName}, then rebuild.",
                null,
            )
            return
        }

        val initializedNow = if (!BubblInitState.initialized) {
            try {
                BubblSdk.init(
                    applicationContext.applicationContext as Application,
                    BubblConfig(
                        apiKey = apiKey,
                        environment = env,
                        segmentationTags = segmentationTags,
                        geoPollInterval = pollMs,
                        defaultDistance = defaultDistance,
                    ),
                )
            } catch (error: Exception) {
                if (error.message?.contains("Default FirebaseApp is not initialized") == true) {
                    result.error(
                        "BUBBL_FIREBASE_NOT_INITIALIZED",
                        "FirebaseApp is not initialized for package ${applicationContext.packageName}. Add google-services.json for this package and rebuild.",
                        null,
                    )
                } else {
                    result.error("BUBBL_BOOT_FAILED", error.message, null)
                }
                return
            }
            BubblInitState.initialized = true
            true
        } else {
            false
        }

        ensureNotificationBridge()
        startGeofenceCollectionIfPossible()

        result.success(
            mapOf(
                "initializedNow" to initializedNow,
                "alreadyInitialized" to !initializedNow,
                "restartRequiredForTenantChange" to false,
            ),
        )
    }

    private fun ensureFirebaseInitialized(): Boolean {
        if (runCatching { FirebaseApp.getApps(applicationContext).isNotEmpty() }.getOrDefault(false)) {
            return true
        }

        val initialized = runCatching { FirebaseApp.initializeApp(applicationContext) }.getOrNull()
        if (initialized != null) {
            return true
        }

        return runCatching { FirebaseApp.getApps(applicationContext).isNotEmpty() }.getOrDefault(false)
    }

    private fun requiredPermissions(): List<String> {
        val out = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            out.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        return out
    }

    private fun locationGranted(): Boolean {
        val fine =
            ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val coarse =
            ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun notificationGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }

        return ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPushPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        if (notificationGranted()) {
            result.success(true)
            return
        }

        val hostActivity = activity
        if (hostActivity == null) {
            result.error(
                "BUBBL_PUSH_PERMISSION_FAILED",
                "requestPushPermission requires an attached Activity.",
                null,
            )
            return
        }

        if (pendingPushPermissionResult != null) {
            result.error(
                "BUBBL_PUSH_PERMISSION_FAILED",
                "A push permission request is already in progress.",
                null,
            )
            return
        }

        pendingPushPermissionResult = result
        ActivityCompat.requestPermissions(
            hostActivity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_POST_NOTIFICATIONS) {
            return false
        }

        val pending = pendingPushPermissionResult ?: return false
        pendingPushPermissionResult = null

        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending.success(granted)
        return true
    }

    private fun startLocationTracking(result: MethodChannel.Result) {
        guarded(result, "startLocationTracking") {
            try {
                BubblSdk.startLocationTracking(applicationContext)
                result.success(true)
            } catch (t: Throwable) {
                result.error("BUBBL_START_LOCATION_FAILED", t.message, null)
            }
        }
    }

    private fun refreshGeofence(call: MethodCall, result: MethodChannel.Result) {
        guarded(result, "refreshGeofence") {
            val latitude = call.argument<Number>("latitude")?.toDouble() ?: 0.0
            val longitude = call.argument<Number>("longitude")?.toDouble() ?: 0.0
            BubblSdk.refreshGeofence(latitude, longitude)
            result.success(true)
        }
    }

    private fun updateSegments(call: MethodCall, result: MethodChannel.Result) {
        guarded(result, "updateSegments") {
            val tags =
                (call.argument<List<Any?>>("tags") ?: emptyList())
                    .mapNotNull { it as? String }
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }

            BubblSdk.updateSegments(tags) { ok ->
                if (ok) {
                    result.success(true)
                } else {
                    result.error("BUBBL_SEGMENTS_FAILED", "updateSegments failed", null)
                }
            }
        }
    }

    private fun setCorrelationId(call: MethodCall, result: MethodChannel.Result) {
        guarded(result, "setCorrelationId") {
            val correlationId = call.argument<String>("correlationId")?.trim().orEmpty()
            BubblSdk.setCorrelationId(correlationId) { ok ->
                if (ok) {
                    result.success(true)
                } else {
                    result.error("BUBBL_CORRELATION_ID_FAILED", "setCorrelationId failed", null)
                }
            }
        }
    }

    private fun getCorrelationId(result: MethodChannel.Result) {
        guarded(result, "getCorrelationId") {
            result.success(BubblSdk.getCorrelationId())
        }
    }

    private fun clearCorrelationId(result: MethodChannel.Result) {
        guarded(result, "clearCorrelationId") {
            BubblSdk.clearCorrelationId { ok ->
                if (ok) {
                    result.success(true)
                } else {
                    result.error("BUBBL_CORRELATION_ID_FAILED", "clearCorrelationId failed", null)
                }
            }
        }
    }

    private fun refreshPrivacyText(result: MethodChannel.Result) {
        guarded(result, "refreshPrivacyText") {
            BubblSdk.refreshPrivacyText { text ->
                if (text != null) {
                    result.success(text)
                } else {
                    result.error("BUBBL_PRIVACY_FAILED", "refreshPrivacyText failed", null)
                }
            }
        }
    }

    private fun getCurrentConfiguration(result: MethodChannel.Result) {
        guarded(result, "getCurrentConfiguration") {
            val cfg = BubblSdk.getCurrentConfiguration()
            if (cfg == null) {
                result.success(null)
                return@guarded
            }

            result.success(
                mapOf(
                    "notificationsCount" to cfg.notificationsCount,
                    "daysCount" to cfg.daysCount,
                    "batteryCount" to cfg.batteryCount,
                    "privacyText" to cfg.privacyText,
                ),
            )
        }
    }

    private fun sendEvent(call: MethodCall, result: MethodChannel.Result) {
        guarded(result, "sendEvent") {
            val payload = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()

            val curatedNotificationID = payload["curatedNotificationID"]?.toString() ?: ""
            val locationID = payload["locationID"]?.toString() ?: ""
            val type = payload["type"]?.toString() ?: ""
            val activityName = payload["activity"]?.toString() ?: ""
            val latitude = (payload["latitude"] as? Number)?.toDouble() ?: 0.0
            val longitude = (payload["longitude"] as? Number)?.toDouble() ?: 0.0

            BubblSdk.sendEvent(
                curatedNotificationID = curatedNotificationID,
                locationID = locationID,
                type = type,
                activity = activityName,
                latitude = latitude,
                longitude = longitude,
            ) { ok ->
                result.success(ok)
            }
        }
    }

    private fun cta(call: MethodCall, result: MethodChannel.Result) {
        guarded(result, "cta") {
            val notificationId = (call.argument<Number>("notificationId")?.toInt() ?: 0)
            val locationId = call.argument<String>("locationId").orEmpty()
            BubblSdk.cta(notificationId, locationId)
            result.success(true)
        }
    }

    private fun trackSurveyEvent(call: MethodCall, result: MethodChannel.Result) {
        guarded(result, "trackSurveyEvent") {
            val notificationId = call.argument<String>("notificationId") ?: ""
            val locationId = call.argument<String>("locationId") ?: ""
            val activityName = call.argument<String>("activity") ?: ""

            BubblSdk.trackSurveyEvent(
                notificationId = notificationId,
                locationId = locationId,
                activity = activityName,
            ) { success ->
                result.success(success)
            }
        }
    }

    private fun submitSurveyResponse(call: MethodCall, result: MethodChannel.Result) {
        guarded(result, "submitSurveyResponse") {
            try {
                val notificationId = call.argument<String>("notificationId") ?: ""
                val locationId = call.argument<String>("locationId") ?: ""
                val rawAnswers = call.argument<List<Any?>>("answers") ?: emptyList()

                val answers = mutableListOf<SurveyAnswer>()
                rawAnswers.forEach { item ->
                    val answerMap = item as? Map<*, *> ?: return@forEach
                    val questionId = (answerMap["question_id"] as? Number)?.toInt() ?: return@forEach
                    val type = answerMap["type"]?.toString().orEmpty()
                    val value = answerMap["value"]?.toString().orEmpty()

                    val rawChoices = answerMap["choice"] as? List<Any?>
                    val choices =
                        rawChoices
                            ?.mapNotNull { choiceAny ->
                                val choiceMap = choiceAny as? Map<*, *> ?: return@mapNotNull null
                                val choiceId = (choiceMap["choice_id"] as? Number)?.toInt() ?: return@mapNotNull null
                                ChoiceSelection(choice_id = choiceId)
                            }
                            ?.takeIf { it.isNotEmpty() }

                    answers.add(
                        SurveyAnswer(
                            question_id = questionId,
                            type = type,
                            value = value,
                            choice = choices,
                        ),
                    )
                }

                BubblSdk.submitSurveyResponse(
                    notificationId = notificationId,
                    locationId = locationId,
                    answers = answers,
                ) { success ->
                    result.success(success)
                }
            } catch (t: Throwable) {
                result.error("BUBBL_SURVEY_SUBMIT_FAILED", t.message, null)
            }
        }
    }

    private fun getTenantConfig(result: MethodChannel.Result) {
        val cfg = TenantConfigStore.load(applicationContext)
        if (cfg == null) {
            result.success(null)
            return
        }

        result.success(
            mapOf(
                "apiKeyMasked" to maskApiKey(cfg.apiKey),
                "environment" to cfg.environment.name,
            ),
        )
    }

    private fun setTenantConfig(call: MethodCall, result: MethodChannel.Result) {
        val apiKey = call.argument<String>("apiKey")?.trim().orEmpty()
        if (apiKey.isEmpty()) {
            result.error("BUBBL_TENANT_SET_FAILED", "apiKey is required.", null)
            return
        }

        val environment = parseEnvironment(call.argument<String>("environment"))
        TenantConfigStore.save(applicationContext, apiKey, environment)
        result.success(true)
    }

    private fun startDeviceLogStream(call: MethodCall, result: MethodChannel.Result) {
        val options = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        configureDeviceLogStream(options)

        val targetSuffix = (options["targetDeviceSuffix"] as? String)?.trim()?.lowercase(Locale.US).orEmpty()
        val deviceSuffix = currentDeviceSuffix().lowercase(Locale.US)
        if (targetSuffix.isNotEmpty() && targetSuffix != deviceSuffix) {
            result.success(
                mapOf(
                    "started" to false,
                    "reason" to "device_suffix_mismatch",
                    "deviceIdSuffix" to currentDeviceSuffix(),
                ),
            )
            return
        }

        stopDeviceLogStream()
        lastDeviceLogFingerprint = ""
        deviceLogJob =
            scope.launch {
                emitDeviceLogSnapshot(force = true)
                while (isActive) {
                    delay(deviceLogIntervalMs)
                    emitDeviceLogSnapshot(force = false)
                }
            }

        result.success(
            mapOf(
                "started" to true,
                "reason" to "ok",
                "deviceIdSuffix" to currentDeviceSuffix(),
            ),
        )
    }

    private fun stopDeviceLogStream() {
        deviceLogJob?.cancel()
        deviceLogJob = null
    }

    private fun configureDeviceLogStream(options: Map<*, *>) {
        val interval = (options["intervalMs"] as? Number)?.toLong() ?: 2500L
        val maxLines = (options["maxLines"] as? Number)?.toInt() ?: 80

        deviceLogIntervalMs = interval.coerceIn(1000L, 30_000L)
        deviceLogMaxLines = maxLines.coerceIn(10, 200)
    }

    private fun emitDeviceLogSnapshot(force: Boolean) {
        val sink = deviceLogSink ?: return

        val lines = readDeviceLogTail(deviceLogMaxLines)
        val fingerprint = lines.joinToString("\n")
        if (!force && fingerprint == lastDeviceLogFingerprint) {
            return
        }

        lastDeviceLogFingerprint = fingerprint

        emitEventOnMainThread(
            sink,
            mapOf(
                "deviceType" to "android",
                "deviceId" to currentDeviceId(),
                "deviceIdSuffix" to currentDeviceSuffix(),
                "timestamp" to System.currentTimeMillis().toDouble(),
                "lines" to lines,
            ),
        )
    }

    private fun readDeviceLogTail(maxLines: Int): List<String> {
        val file = Logger.getLogFile() ?: return emptyList()
        if (!file.exists()) {
            return emptyList()
        }

        return runCatching {
            file.readLines().takeLast(maxLines)
        }.getOrDefault(emptyList())
    }

    private fun startGeofenceCollectionIfPossible() {
        if (!BubblInitState.initialized) {
            return
        }

        if (geofenceSink == null) {
            return
        }

        if (geofenceJob != null) {
            return
        }

        geofenceJob =
            scope.launch {
                BubblSdk.geofenceFlow.collect { snapshot ->
                    val sink = geofenceSink ?: return@collect
                    val snap = snapshot ?: return@collect

                    val polygons = mutableListOf<Map<String, Any>>()
                    val circles = mutableListOf<Map<String, Any>>()

                    snap.polygons.forEach { polygon ->
                        val vertices =
                            polygon.vertices.map { point ->
                                mapOf(
                                    "latitude" to point.latitude,
                                    "longitude" to point.longitude,
                                )
                            }

                        polygons.add(
                            mapOf(
                                "campaignId" to polygon.campaignId,
                                "campaignName" to polygon.campaignName,
                                "vertices" to vertices,
                            ),
                        )

                        deriveGeofenceCircle(polygon.vertices)?.let { circle ->
                            circles.add(
                                mapOf(
                                    "campaignId" to polygon.campaignId,
                                    "campaignName" to polygon.campaignName,
                                    "center" to
                                        mapOf(
                                            "latitude" to circle.centerLatitude,
                                            "longitude" to circle.centerLongitude,
                                        ),
                                    "radius" to circle.radiusMeters,
                                ),
                            )
                        }
                    }

                    emitEventOnMainThread(
                        sink,
                        mapOf(
                            "stats" to
                                mapOf(
                                    "campaignsTotal" to snap.stats.campaignsTotal,
                                    "polygonsTotal" to snap.stats.polygonsTotal,
                                ),
                            "polygons" to polygons,
                            "circles" to circles,
                        ),
                    )
                }
            }
    }

    private fun stopGeofenceCollection() {
        geofenceJob?.cancel()
        geofenceJob = null
    }

    private data class GeofenceCircle(
        val centerLatitude: Double,
        val centerLongitude: Double,
        val radiusMeters: Double,
    )

    private fun deriveGeofenceCircle(vertices: List<com.google.android.gms.maps.model.LatLng>): GeofenceCircle? {
        if (vertices.isEmpty()) {
            return null
        }

        val centerLat = vertices.sumOf { it.latitude } / vertices.size
        val centerLng = vertices.sumOf { it.longitude } / vertices.size

        var radiusMeters = 0.0
        vertices.forEach { point ->
            val distances = FloatArray(1)
            Location.distanceBetween(centerLat, centerLng, point.latitude, point.longitude, distances)
            radiusMeters = maxOf(radiusMeters, distances[0].toDouble())
        }

        return GeofenceCircle(centerLatitude = centerLat, centerLongitude = centerLng, radiusMeters = radiusMeters)
    }

    private fun ensureNotificationBridge() {
        if (notificationBridgeRegistered) {
            return
        }

        LocalBroadcastManager
            .getInstance(applicationContext)
            .registerReceiver(notificationReceiver, IntentFilter(NotificationRouter.BROADCAST))
        notificationBridgeRegistered = true

        val coldStartPayload = activity?.intent?.getStringExtra("payload")
        if (!coldStartPayload.isNullOrEmpty()) {
            emitNotification(coldStartPayload)
        }
    }

    private fun unregisterNotificationBridge() {
        if (!notificationBridgeRegistered) {
            return
        }

        runCatching {
            LocalBroadcastManager.getInstance(applicationContext).unregisterReceiver(notificationReceiver)
        }
        notificationBridgeRegistered = false
    }

    private fun emitNotification(json: String) {
        val sink = notificationSink ?: return

        val payload =
            runCatching {
                val jsonObject = JSONObject(json)
                val map = mutableMapOf<String, Any?>()

                map["id"] = if (jsonObject.has("id") && !jsonObject.isNull("id")) jsonObject.optInt("id") else null
                map["headline"] = jsonObject.optNullableString("headline")
                map["body"] = jsonObject.optNullableString("body")
                map["mediaUrl"] = jsonObject.optNullableString("mediaUrl")
                map["mediaType"] = jsonObject.optNullableString("mediaType")
                map["activation"] = jsonObject.optNullableString("activation")
                map["ctaLabel"] = jsonObject.optNullableString("ctaLabel")
                map["ctaUrl"] = jsonObject.optNullableString("ctaUrl")
                map["locationId"] = jsonObject.optNullableString("locationId")
                map["postMessage"] = jsonObject.optNullableString("postMessage")
                map["questions"] =
                    jsonObject.optJSONArray("questions")?.let(::jsonQuestionsToList) ?: emptyList<Map<String, Any?>>()
                map["raw"] = json
                map
            }.getOrElse {
                mutableMapOf<String, Any?>("raw" to json)
            }

        emitEventOnMainThread(sink, payload)
    }

    private fun emitEventOnMainThread(sink: EventChannel.EventSink, payload: Any?) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runCatching { sink.success(payload) }
            return
        }

        mainHandler.post {
            runCatching { sink.success(payload) }
        }
    }

    private fun JSONObject.optNullableString(key: String): String? {
        return if (!has(key) || isNull(key)) null else optString(key)
    }

    private fun jsonQuestionsToList(array: JSONArray): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()

        for (i in 0 until array.length()) {
            val question = array.optJSONObject(i) ?: continue

            val choices = mutableListOf<Map<String, Any?>>()
            val rawChoices = question.optJSONArray("choices")
            if (rawChoices != null) {
                for (j in 0 until rawChoices.length()) {
                    val choice = rawChoices.optJSONObject(j) ?: continue
                    choices.add(
                        mapOf(
                            "id" to if (choice.has("id") && !choice.isNull("id")) choice.optInt("id") else null,
                            "choice" to choice.optNullableString("choice"),
                            "position" to if (choice.has("position") && !choice.isNull("position")) choice.optInt("position") else null,
                        ),
                    )
                }
            }

            out.add(
                mapOf(
                    "id" to if (question.has("id") && !question.isNull("id")) question.optInt("id") else null,
                    "question" to question.optNullableString("question"),
                    "question_type" to question.optNullableString("question_type"),
                    "has_choices" to question.optBoolean("has_choices", false),
                    "position" to if (question.has("position") && !question.isNull("position")) question.optInt("position") else null,
                    "choices" to choices,
                ),
            )
        }

        return out
    }

    private fun testNotification(result: MethodChannel.Result) {
        val id = (System.currentTimeMillis() / 1000L).toInt()
        val payload =
            JSONObject()
                .put("id", id)
                .put("headline", "Test Notification")
                .put("body", "This is a local test notification from Bubbl Flutter SDK.")
                .put("locationId", "test-location")
                .put("postMessage", "Thanks for testing")

        emitNotification(payload.toString())

        val manager =
            applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "bubbl_test"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Bubbl Test", NotificationManager.IMPORTANCE_DEFAULT)
            manager.createNotificationChannel(channel)
        }

        val launchIntent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)
        val pendingIntent =
            PendingIntent.getActivity(
                applicationContext,
                id,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0,
            )

        val notification =
            NotificationCompat
                .Builder(applicationContext, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Test Notification")
                .setContentText("This is a local test notification from Bubbl Flutter SDK.")
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()

        manager.notify(id, notification)
        result.success(true)
    }

    private fun guarded(
        result: MethodChannel.Result,
        functionName: String,
        block: () -> Unit,
    ) {
        if (!BubblInitState.initialized) {
            result.error(
                "BUBBL_NOT_INITIALIZED",
                "Call Bubbl.boot(...) before calling $functionName().",
                null,
            )
            return
        }

        block()
    }

    private fun parseEnvironment(raw: String?): Environment {
        return when (raw?.trim()?.uppercase(Locale.US)) {
            "PRODUCTION" -> Environment.PRODUCTION
            else -> Environment.STAGING
        }
    }

    private fun currentDeviceId(): String {
        return Settings.Secure.getString(applicationContext.contentResolver, Settings.Secure.ANDROID_ID)
            ?: "unknown"
    }

    private fun currentDeviceSuffix(): String {
        val normalized = currentDeviceId().replace(Regex("[^A-Za-z0-9]"), "")
        if (normalized.isEmpty()) {
            return "-----"
        }
        return normalized.takeLast(5)
    }

    private fun maskApiKey(apiKey: String): String {
        if (apiKey.length <= 8) {
            return "****"
        }

        val start = apiKey.take(4)
        val end = apiKey.takeLast(4)
        return "$start****$end"
    }
}

private object TenantConfigStore {
    private const val PREFS_NAME = "bubbl_tenant_config"
    private const val KEY_API = "bubbl_api_key"
    private const val KEY_ENV = "bubbl_environment"

    data class TenantConfig(
        val apiKey: String,
        val environment: Environment,
    )

    fun load(context: Context): TenantConfig? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val apiKey = prefs.getString(KEY_API, null)?.trim().orEmpty()
        if (apiKey.isEmpty()) {
            return null
        }

        val envRaw = prefs.getString(KEY_ENV, Environment.STAGING.name)
        val environment =
            runCatching { Environment.valueOf(envRaw ?: Environment.STAGING.name) }
                .getOrElse { Environment.STAGING }

        return TenantConfig(apiKey = apiKey, environment = environment)
    }

    fun save(
        context: Context,
        apiKey: String,
        environment: Environment,
    ) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_API, apiKey)
            .putString(KEY_ENV, environment.name)
            .apply()
    }

    fun clear(context: Context) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }
}
