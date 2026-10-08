package com.carriez.flutter_hbb

/** A bounded wait for a system-owned binding, never a grant of accessibility. */
class XixiRecoveryPolicy(private val timeoutMs: Long = 15_000L) {
    enum class Phase { IDLE, PERMISSION_UNKNOWN, PERMISSION_REQUIRED, WAITING, TIMED_OUT, READY, UNSUPPORTED }

    private var waitingSince: Long? = null
    var phase = Phase.IDLE
        private set

    init { require(timeoutMs > 0) }

    fun reset() {
        waitingSince = null
        phase = Phase.IDLE
    }

    fun evaluate(
        enabled: Boolean,
        permissionEnabled: Boolean?,
        connected: Boolean,
        capable: Boolean,
        nowMs: Long,
        retry: Boolean = false,
    ): Phase {
        phase = when {
            !enabled -> Phase.IDLE
            permissionEnabled == null -> Phase.PERMISSION_UNKNOWN
            !permissionEnabled -> Phase.PERMISSION_REQUIRED
            connected && capable -> Phase.READY
            connected -> Phase.UNSUPPORTED
            else -> {
                if (retry || waitingSince == null) waitingSince = nowMs
                if (nowMs - waitingSince!! >= timeoutMs) Phase.TIMED_OUT else Phase.WAITING
            }
        }
        if (phase != Phase.WAITING && phase != Phase.TIMED_OUT) waitingSince = null
        return phase
    }
}

/** Ephemeral demand from an existing authorized screen session, never persisted. */
class XixiCaptureDemand {
    private var pending = false

    fun needsResume(currentlyCapturing: Boolean): Boolean = pending || currentlyCapturing

    fun pausedAfterStop(wasRequired: Boolean) {
        pending = wasRequired
    }

    fun stopped() {
        pending = false
    }
}
