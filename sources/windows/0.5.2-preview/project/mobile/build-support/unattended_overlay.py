"""Reproducible native overlay against the pinned Android source."""
import shutil


def apply_unattended(project, source, replace_once):
    root = source / 'flutter/android/app/src/main'
    kotlin = root / 'kotlin/com/carriez/flutter_hbb'
    shutil.copy2(project / 'mobile/android/XixiUnattended.kt', kotlin / 'XixiUnattended.kt')
    def edit(name, changes):
        path = kotlin / name
        text = path.read_text(encoding='utf-8')
        for old, new in changes:
            text = replace_once(text, old, new, name + ' unattended overlay')
        path.write_text(text, encoding='utf-8', newline='\n')
    edit('MainService.kt', [
        ('get() = _isReady', 'get() = _isReady || XixiUnattended.running && XixiUnattended.capable()'),
        ('    private var serviceLooper: Looper? = null', '''    private val xixiCapture = XixiScreenshotCapture(this)
    @Synchronized
    fun submitXixiFrame(buffer: ByteBuffer): Boolean {
        if (!isStart || !XixiUnattended.available(this)) return false
        FFI.onVideoFrameUpdate(buffer)
        return true
    }

    private var serviceLooper: Looper? = null'''),
        ('        super.onStartCommand(intent, flags, startId)', '''        super.onStartCommand(intent, flags, startId)
        if (intent?.action == XixiUnattended.ACTION || intent == null && XixiUnattended.available(this)) {
            if (!XixiUnattended.available(this)) { stopSelf(); return START_NOT_STICKY }
            val resumeCapture = isStart
            stopCapture()
            virtualDisplay?.release()
            virtualDisplay = null
            releaseMediaProjection()
            setMediaProjectionForegroundService(false)
            _isReady = false
            XixiUnattended.running = true
            FFI.startService()
            checkMediaPermission()
            if (resumeCapture) startCapture()
            return START_STICKY
        }'''),
        ('        if (mediaProjection == null) {\n            Log.w', '''        if (XixiUnattended.available(this)) {
            updateScreenInfo(resources.configuration.orientation)
            _isStart = true
            FFI.setFrameRawEnable("video", true)
            MainActivity.rdClipboardManager?.setCaptureStarted(true)
            if (!powerManager.isInteractive) wakeLock.acquire(5000)
            xixiCapture.start()
            checkMediaPermission()
            return true
        }
        if (mediaProjection == null) {
            Log.w'''),
        ('        _isStart = false\n        MainActivity.rdClipboardManager', '        _isStart = false\n        xixiCapture.stop()\n        MainActivity.rdClipboardManager'),
        ('        Log.d(logTag, "destroy service")', '''        Log.d(logTag, "destroy service")
        XixiUnattended.setEnabled(this, false)
        XixiUnattended.running = false'''),
        ('    override fun onDestroy() {\n        checkMediaPermission()', '''    override fun onDestroy() {
        XixiUnattended.running = false
        _isReady = false
        stopCapture()
        serviceLooper?.quitSafely()
        checkMediaPermission()'''),
        ('            if (SCREEN_INFO.width != w) {', '            if (SCREEN_INFO.width != w || SCREEN_INFO.height != h || SCREEN_INFO.scale != scale) {'),
    ])
    edit('InputService.kt', [
        ('        val info = AccessibilityServiceInfo()', '        val info = serviceInfo'),
        ('        setServiceInfo(info)', '''        setServiceInfo(info)
        if (XixiUnattended.enabled(this)) XixiUnattended.start(this)'''),
    ])
    edit('BootReceiver.kt', [
        ('            // check SharedPreferences config', '''            if (XixiUnattended.enabled(context)) {
                // Accessibility may bind after this receiver; its callback retries host startup.
                XixiUnattended.start(context)
                return
            }
            // check SharedPreferences config'''),
    ])
    edit('MainActivity.kt', [
        ('                    Log.d(logTag, "Stop service")', '''                    Log.d(logTag, "Stop service")
                    XixiUnattended.setEnabled(this, false)'''),
        ('            when (call.method) {', '''            when (call.method) {
                "xixi_unattended_state" -> result.success(XixiUnattended.state(this))
                "xixi_enable_unattended" -> {
                    val enabled = call.arguments == true
                    if (enabled && !XixiUnattended.capable()) {
                        result.success(false)
                    } else {
                        XixiUnattended.setEnabled(this, enabled)
                        val started = !enabled || XixiUnattended.start(this)
                        if (!started) XixiUnattended.setEnabled(this, false)
                        if (enabled && started) {
                            bindService(Intent(this, MainService::class.java), serviceConnection, Context.BIND_AUTO_CREATE)
                        }
                        result.success(started)
                    }
                }
                "xixi_battery_settings" -> {
                    startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(true)
                }'''),
        ('                    requestMediaProjection()\n                    result.success(true)', '''                    if (XixiUnattended.enabled(this)) XixiUnattended.start(this)
                    else requestMediaProjection()
                    result.success(true)'''),
    ])
    xml = root / 'res/xml/accessibility_service_config.xml'
    text = xml.read_text(encoding='utf-8')
    text = replace_once(text, 'android:canPerformGestures="true"',
                        'android:canPerformGestures="true"\n    android:canTakeScreenshot="true"', 'screenshot capability')
    xml.write_text(text, encoding='utf-8')
    return [kotlin / n for n in ('XixiUnattended.kt', 'MainService.kt', 'MainActivity.kt', 'InputService.kt', 'BootReceiver.kt')] + [xml]
