package com.carriez.flutter_hbb

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.view.Display
import android.view.accessibility.AccessibilityManager
import androidx.core.content.ContextCompat
import java.nio.ByteBuffer
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicInteger

/** User-enabled host mode. Never grants accessibility or bypasses authentication. */
object XixiUnattended {
    const val ACTION = "com.xixi.remote.START_UNATTENDED"
    private const val KEY = "xixi-unattended-v1"
    @Volatile var running = false
    @Volatile var lastFrameAt = 0L
    @Volatile var lastError = ""
    @Volatile var lastInputAt = 0L
    @Volatile var frameProcessingMs = 0L
    @Volatile var captureIntervalMs = 0L
    @Volatile var frequencyErrors = 0L
    private val recoveryPolicy = XixiRecoveryPolicy()
    private val recoveryHandler by lazy { Handler(Looper.getMainLooper()) }
    private var pendingRecovery: Runnable? = null
    private var hostService: MainService? = null

    val recovering: Boolean
        get() = recoveryPolicy.phase == XixiRecoveryPolicy.Phase.WAITING
    val recoveryTimedOut: Boolean
        get() = recoveryPolicy.phase == XixiRecoveryPolicy.Phase.TIMED_OUT

    fun enabled(context: Context): Boolean = context.getSharedPreferences(
        KEY_SHARED_PREFERENCES, Context.MODE_PRIVATE).getBoolean(KEY, false)

    fun setEnabled(context: Context, value: Boolean) {
        context.getSharedPreferences(KEY_SHARED_PREFERENCES, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, value).commit()
        if (!value) {
            cancelRecovery()
            recoveryPolicy.reset()
            running = false
        }
    }

    /** Read the OS setting, not our last remembered grant or a live service pointer. */
    fun accessibilityEnabled(context: Context): Boolean = readAccessibilityEnabled(context) == true

    private fun readAccessibilityEnabled(context: Context): Boolean? {
        val expected = ComponentName(context, InputService::class.java)
        try {
            val providers = Settings.Secure.getString(context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            if (providers != null) {
                return providers.split(':').any {
                    ComponentName.unflattenFromString(it) == expected
                }
            }
        } catch (_: RuntimeException) { /* An unreadable OEM setting may use the public manager. */ }
        return try {
            val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            val found = manager?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                ?.any { info ->
                    val service = info.resolveInfo?.serviceInfo
                    service != null && ComponentName(service.packageName, service.name) == expected
                }
            // AOSP returns bound services here; absence cannot prove a stored grant was revoked.
            if (found == true) true else null
        } catch (_: RuntimeException) { null }
    }

    fun accessibilityConnected(): Boolean = InputService.isOpen

    fun capable(): Boolean = Build.VERSION.SDK_INT >= 30 && ((InputService.ctx?.serviceInfo
        ?.capabilities ?: 0) and AccessibilityServiceInfo.CAPABILITY_CAN_TAKE_SCREENSHOT) != 0 && InputService.isOpen

    fun available(context: Context): Boolean = enabled(context) && accessibilityEnabled(context) && capable()

    fun start(context: Context, retry: Boolean = false): Boolean {
        val phase = recoveryPhase(context, retry)
        if (phase != XixiRecoveryPolicy.Phase.READY && phase != XixiRecoveryPolicy.Phase.WAITING) {
            cancelRecovery()
            running = false
            if (phase != XixiRecoveryPolicy.Phase.TIMED_OUT) hostService?.stopCapture()
            hostService?.checkMediaPermission()
            return false
        }
        hostService?.let {
            restoreHost(it)
            return true
        }
        return try {
            ContextCompat.startForegroundService(context,
                Intent(context, MainService::class.java).setAction(ACTION))
            true
        } catch (_: RuntimeException) {
            cancelRecovery()
            recoveryPolicy.reset()
            lastError = "后台服务启动失败，请打开应用后重试"
            false
        }
    }

    private fun cancelRecovery() {
        pendingRecovery?.let { recoveryHandler.removeCallbacks(it) }
        pendingRecovery = null
    }

    private fun recoveryPhase(context: Context, retry: Boolean = false): XixiRecoveryPolicy.Phase {
        if (Build.VERSION.SDK_INT < 30) {
            recoveryPolicy.reset()
            lastError = "免录屏确认模式需要 Android 11 或更新版本"
            return XixiRecoveryPolicy.Phase.UNSUPPORTED
        }
        val permissionEnabled = readAccessibilityEnabled(context)
        val phase = recoveryPolicy.evaluate(enabled(context), permissionEnabled,
            accessibilityConnected(), capable(), SystemClock.uptimeMillis(), retry)
        lastError = when (phase) {
            XixiRecoveryPolicy.Phase.PERMISSION_UNKNOWN -> "暂时无法读取系统无障碍设置，请重新打开应用检查"
            XixiRecoveryPolicy.Phase.PERMISSION_REQUIRED -> "系统已关闭无障碍授权，请在本机启用西西远程输入"
            XixiRecoveryPolicy.Phase.WAITING -> "授权已保留，正在等待系统恢复无障碍连接"
            XixiRecoveryPolicy.Phase.TIMED_OUT -> "授权仍开启，但系统未恢复无障碍连接；请检查后台限制后重试"
            XixiRecoveryPolicy.Phase.UNSUPPORTED -> "当前无障碍服务不支持截屏，请检查已安装版本"
            else -> ""
        }
        return phase
    }

    /** Called by the already foreground host; waiting never opens a permission activity. */
    fun onHostServiceStarted(service: MainService) {
        hostService = service
        restoreHost(service)
    }

    private fun restoreHost(service: MainService) {
        cancelRecovery()
        when (recoveryPhase(service)) {
            XixiRecoveryPolicy.Phase.READY -> service.resumeXixiHost()
            XixiRecoveryPolicy.Phase.WAITING -> {
                service.pauseXixiCapture()
                running = false
                service.checkMediaPermission()
                val check = Runnable {
                    pendingRecovery = null
                    if (hostService === service) restoreHost(service)
                }
                pendingRecovery = check
                recoveryHandler.postDelayed(check, 500L)
            }
            else -> {
                running = false
                if (recoveryPolicy.phase != XixiRecoveryPolicy.Phase.TIMED_OUT) service.stopCapture()
                service.checkMediaPermission()
            }
        }
    }

    fun onInputDisconnected(context: Context) {
        if (enabled(context)) hostService?.let { restoreHost(it) }
    }

    fun onHostServiceDestroyed(service: MainService) {
        if (hostService !== service) return
        hostService = null
        running = false
        cancelRecovery()
        recoveryPolicy.reset()
    }

    fun state(context: Context): Map<String, Any> {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val permissionState = readAccessibilityEnabled(context)
        val permissionEnabled = permissionState == true
        val connected = accessibilityConnected()
        val liveCapable = capable()
        val hostEnabled = enabled(context)
        return mapOf("supported" to (Build.VERSION.SDK_INT >= 30),
            "enabled" to hostEnabled, "accessibility" to connected,
            "accessibilityEnabled" to permissionEnabled,
            "accessibilityStatusKnown" to (permissionState != null),
            "accessibilityConnected" to connected,
            "recovering" to (recovering && hostEnabled && permissionEnabled && !connected),
            "recoveryTimedOut" to (recoveryTimedOut && hostEnabled && permissionEnabled && !connected),
            "capable" to (permissionEnabled && liveCapable),
            "running" to (running && hostEnabled && permissionEnabled && liveCapable),
            "batteryExempt" to (Build.VERSION.SDK_INT < 23 || power.isIgnoringBatteryOptimizations(context.packageName)),
            "lastFrameAt" to lastFrameAt, "error" to lastError,
            "lastInputAt" to lastInputAt, "frameProcessingMs" to frameProcessingMs,
            "captureIntervalMs" to captureIntervalMs, "frequencyErrors" to frequencyErrors)
    }
}

/** Pixel work is serial and off the UI thread. MainService owns JNI frame references. */
class XixiScreenshotCapture(private val service: MainService) {
    private val thread = HandlerThread("XiXiScreenshot").apply { start() }
    private val handler = Handler(thread.looper)
    private val generation = AtomicInteger()
    @Volatile private var active = false
    @Volatile private var closed = false
    // Android 11's floor is 1000ms; Android 12+ uses 333ms. Leave a small margin.
    private val minimumInterval = if (Build.VERSION.SDK_INT == 30) 1050L else 350L
    private var interval = minimumInterval
    private var lastRequestAt: Long? = null
    private var inFlight = false
    private var scheduled: Runnable? = null
    private val executor = Executor { command ->
        // A late callback must still close its HardwareBuffer after service shutdown.
        if (!handler.post(command)) command.run()
    }

    fun accepts(token: Int): Boolean = active && !closed && token == generation.get()

    fun start() {
        if (closed) return
        val token = generation.incrementAndGet()
        active = true
        handler.post {
            if (!accepts(token)) return@post
            XixiUnattended.lastError = ""
            schedule(token)
        }
    }

    fun stop() {
        // Called under MainService's monitor, before an old callback can submit again.
        active = false
        generation.incrementAndGet()
        handler.post {
            cancelScheduled()
        }
    }

    fun close() {
        closed = true
        stop()
        handler.post {
            if (!inFlight) thread.quitSafely()
            // Otherwise finishRequest drains the callback before quitting.
        }
    }

    private fun cancelScheduled() {
        scheduled?.let { handler.removeCallbacks(it) }
        scheduled = null
    }

    private fun schedule(token: Int, retryDelay: Long = 0) {
        cancelScheduled()
        if (!accepts(token) || inFlight || !MainService.isStart) return
        val elapsed = lastRequestAt?.let { SystemClock.uptimeMillis() - it }
        val delay = maxOf(retryDelay, elapsed?.let { (interval - it).coerceAtLeast(0) } ?: 0)
        scheduled = Runnable { scheduled = null; capture(token) }
        handler.postDelayed(scheduled!!, delay)
    }

    private fun finishRequest(retryDelay: Long = 0) {
        inFlight = false
        if (closed) thread.quitSafely()
        else schedule(generation.get(), retryDelay)
    }

    private fun capture(token: Int) {
        if (!accepts(token) || inFlight || !MainService.isStart) return
        if (Build.VERSION.SDK_INT < 30 || !XixiUnattended.available(service)) {
            if (Build.VERSION.SDK_INT >= 30 && XixiUnattended.enabled(service) &&
                XixiUnattended.accessibilityEnabled(service) && !XixiUnattended.accessibilityConnected()) {
                XixiUnattended.lastError = "授权已保留，正在恢复无障碍连接"
                service.pauseXixiCapture()
            } else {
                XixiUnattended.lastError = "无障碍截屏暂不可用，请查看后台接入状态"
                service.stopCapture()
            }
            service.checkMediaPermission()
            return
        }
        val input = InputService.ctx ?: return
        inFlight = true
        lastRequestAt = SystemClock.uptimeMillis()
        XixiUnattended.captureIntervalMs = interval
        try {
            input.takeScreenshot(Display.DEFAULT_DISPLAY, executor,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                        val hardware = result.hardwareBuffer
                        var wrapped: Bitmap? = null
                        var software: Bitmap? = null
                        var scaled: Bitmap? = null
                        val processingStarted = SystemClock.uptimeMillis()
                        try {
                            if (!accepts(token) || !MainService.isStart) return
                            wrapped = Bitmap.wrapHardwareBuffer(hardware, result.colorSpace)
                            software = wrapped?.copy(Bitmap.Config.ARGB_8888, false)
                                ?: throw IllegalStateException("No screenshot bitmap")
                            // Drop a frame during rotation; never distort portrait into landscape.
                            val width = SCREEN_INFO.width
                            val height = SCREEN_INFO.height
                            if ((software.width > software.height) != (width > height)) {
                                return
                            }
                            scaled = Bitmap.createScaledBitmap(software, width, height, true)
                            val buffer = ByteBuffer.allocateDirect(scaled.byteCount)
                            scaled.copyPixelsToBuffer(buffer)
                            buffer.rewind()
                            if (service.submitXixiFrame(buffer, token)) {
                                XixiUnattended.lastFrameAt = System.currentTimeMillis()
                                XixiUnattended.lastError = ""
                                XixiUnattended.frameProcessingMs = SystemClock.uptimeMillis() - processingStarted
                            }
                        } catch (_: RuntimeException) {
                            if (accepts(token)) XixiUnattended.lastError = "截屏失败，正在重试"
                        } finally {
                            if (scaled !== software) scaled?.recycle()
                            software?.recycle()
                            wrapped?.recycle()
                            hardware.close()
                            finishRequest()
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        var retryDelay = 0L
                        try {
                            if (!accepts(token)) return
                            if (errorCode == AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT) {
                                // OEMs may impose a larger floor. Never replace valid pixels for a timing error.
                                interval = (interval + 100).coerceAtMost(3000)
                                XixiUnattended.frequencyErrors++
                                XixiUnattended.captureIntervalMs = interval
                                XixiUnattended.lastError = "系统限制截屏频率，已降低刷新频率"
                            } else {
                                XixiUnattended.lastError = when (errorCode) {
                                    AccessibilityService.ERROR_TAKE_SCREENSHOT_NO_ACCESSIBILITY_ACCESS -> "无障碍截屏权限不可用"
                                    else -> "当前画面暂不可截取（系统代码 $errorCode）"
                                }
                                // Replace sensitive/stale pixels only for a real capture restriction.
                                retryDelay = 1000
                                showUnavailableFrame(token)
                            }
                        } catch (_: RuntimeException) {
                            if (accepts(token)) XixiUnattended.lastError = "截屏提示画面生成失败，正在重试"
                            retryDelay = 1000
                        } finally {
                            finishRequest(retryDelay)
                        }
                    }
                })
        } catch (_: RuntimeException) {
            if (accepts(token)) XixiUnattended.lastError = "截屏请求失败，正在重试"
            finishRequest(1000)
        }
    }

    private fun showUnavailableFrame(token: Int) {
        val bitmap = Bitmap.createBitmap(SCREEN_INFO.width, SCREEN_INFO.height, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.rgb(246, 247, 250))
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(34, 44, 64)
                textSize = (SCREEN_INFO.width / 24f).coerceAtLeast(16f)
            }
            canvas.drawText("当前画面暂不可截取", 24f, SCREEN_INFO.height / 2f, paint)
            val buffer = ByteBuffer.allocateDirect(bitmap.byteCount)
            bitmap.copyPixelsToBuffer(buffer)
            buffer.rewind()
            service.submitXixiFrame(buffer, token)
        } finally { bitmap.recycle() }
    }
}
