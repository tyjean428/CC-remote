package com.carriez.flutter_hbb

private fun XixiRecoveryPolicy.waiting(now: Long, retry: Boolean = false) =
    evaluate(true, true, false, false, now, retry)

fun main() {
    val policy = XixiRecoveryPolicy(15_000L)
    check(policy.waiting(10_000L) == XixiRecoveryPolicy.Phase.WAITING)
    check(policy.waiting(24_999L) == XixiRecoveryPolicy.Phase.WAITING)
    check(policy.waiting(25_000L) == XixiRecoveryPolicy.Phase.TIMED_OUT)
    check(policy.waiting(26_000L) == XixiRecoveryPolicy.Phase.TIMED_OUT)
    println("PASS repeated status/recovery calls cannot extend the 15-second binding window")

    check(policy.evaluate(true, true, true, true, 26_001L) == XixiRecoveryPolicy.Phase.READY)
    check(policy.waiting(30_000L) == XixiRecoveryPolicy.Phase.WAITING)
    check(policy.waiting(45_000L) == XixiRecoveryPolicy.Phase.TIMED_OUT)
    println("PASS a late real system binding can recover after timeout; a new disconnect has its own window")

    check(policy.waiting(50_000L, retry = true) == XixiRecoveryPolicy.Phase.WAITING)
    check(policy.waiting(65_000L) == XixiRecoveryPolicy.Phase.TIMED_OUT)
    println("PASS an explicit foreground retry opens one bounded new recovery window")

    check(policy.evaluate(false, true, true, true, 65_001L) == XixiRecoveryPolicy.Phase.IDLE)
    check(policy.evaluate(false, true, false, false, 65_002L) == XixiRecoveryPolicy.Phase.IDLE)
    check(policy.waiting(70_000L) == XixiRecoveryPolicy.Phase.WAITING)
    println("PASS explicit host stop vetoes stale connection/capture status and clears old waiting state")

    check(policy.evaluate(true, false, true, true, 70_001L) == XixiRecoveryPolicy.Phase.PERMISSION_REQUIRED)
    check(policy.evaluate(true, false, false, false, 70_002L, retry = true) == XixiRecoveryPolicy.Phase.PERMISSION_REQUIRED)
    check(policy.waiting(80_000L) == XixiRecoveryPolicy.Phase.WAITING)
    println("PASS a real revoked OS permission vetoes stale runtime pointers and retry cannot manufacture a grant")

    check(policy.evaluate(true, true, true, false, 80_001L) == XixiRecoveryPolicy.Phase.UNSUPPORTED)
    check(policy.evaluate(true, true, true, true, 80_002L) == XixiRecoveryPolicy.Phase.READY)
    policy.reset()
    check(policy.phase == XixiRecoveryPolicy.Phase.IDLE)
    println("PASS connected without screenshot capability is not ready; service destruction resets transient state only")

    check(policy.evaluate(true, null, true, true, 90_000L) == XixiRecoveryPolicy.Phase.PERMISSION_UNKNOWN)
    check(policy.evaluate(true, false, true, true, 90_001L) == XixiRecoveryPolicy.Phase.PERMISSION_REQUIRED)
    check(policy.evaluate(true, true, true, true, 90_002L) == XixiRecoveryPolicy.Phase.READY)
    println("PASS unreadable permission is distinct from a known revoked permission and never reports ready")

    val capture = XixiCaptureDemand()
    check(!capture.needsResume(false))
    capture.pausedAfterStop(capture.needsResume(true))
    check(capture.needsResume(false))
    capture.pausedAfterStop(capture.needsResume(false))
    check(capture.needsResume(false))
    println("PASS active authorized screen demand survives repeated temporary pauses after the live capture flag is cleared")

    capture.stopped()
    check(!capture.needsResume(false))
    capture.pausedAfterStop(capture.needsResume(false))
    check(!capture.needsResume(false))
    println("PASS stop_capture while paused cancels demand; a subsequent binding cannot restart a closed session")

    val idleCapture = XixiCaptureDemand()
    idleCapture.pausedAfterStop(idleCapture.needsResume(false))
    check(!idleCapture.needsResume(false))
    check(idleCapture.needsResume(true))
    idleCapture.stopped()
    check(!idleCapture.needsResume(false))
    println("PASS a new or destroyed service has no capture demand; readiness alone cannot begin screenshots")
}
