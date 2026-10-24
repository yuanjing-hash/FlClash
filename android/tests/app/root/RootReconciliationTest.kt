package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RootReconciliationTest {
    private val cached = RootSnapshot(state = TunState.RUNNING, mode = "rootTun", rootTunEnabled = true, autostartEnabled = true)
    private val granted = RootStatus("kernelsu", "granted")

    @Test
    fun freshInstallAllowsCommandsAndPersistedStateRequiresReconciliation() {
        assertFalse(RootReconciliation.initial(null).stale)
        val restored = RootReconciliation.initial(cached)
        assertTrue(restored.stale)
        assertEquals(0L, restored.seq)
        assertNotEquals(cached.epoch, restored.epoch)
    }

    @Test
    fun verifiedRunningClearsStaleAndReadsAutostartFromRuntime() {
        val restored = RootReconciliation.initial(cached)
        val checked = RootReconciliation.checked(restored, granted, ShellResult(0, "running -\nautostart:no\n", ""))
        assertEquals(TunState.RUNNING, checked.state)
        assertFalse(checked.stale)
        assertFalse(checked.autostartEnabled)
        assertEquals("granted", checked.authStatus)
    }

    @Test
    fun stoppedRuntimeClearsCachedRunningAndKeepsRealAutostartSetting() {
        val checked = RootReconciliation.checked(cached, granted, ShellResult(1, "disabled -\nautostart:yes\n", ""))
        assertEquals(TunState.DISABLED, checked.state)
        assertFalse(checked.stale)
        assertTrue(checked.autostartEnabled)
        assertNull(checked.startedAt)
    }

    @Test
    fun missingGrantLeavesAwaitingAuthWithNoStaleLock() {
        val checked = RootReconciliation.checked(cached, RootStatus("kernelsu", "notGranted"), null)
        assertEquals(TunState.AWAITING_AUTH, checked.state)
        assertFalse(checked.stale)
        assertEquals("notGranted", checked.authStatus)
        assertNull(checked.authDeadlineAt)
    }

    @Test
    fun missingGrantWithoutStartIntentStaysDisabledAndOnlyUpdatesAuth() {
        val idle = RootSnapshot(state = TunState.DISABLED, rootTunEnabled = false)
        val checked =
            RootReconciliation.checked(
                idle,
                RootStatus("kernelsu", "notGranted"),
                ShellResult(0, "disabled -\nautostart:no\n", ""),
            )
        assertEquals(TunState.DISABLED, checked.state)
        assertEquals("notGranted", checked.authStatus)
        assertNull(checked.lastErrorCode)
        assertFalse(checked.stale)
    }

    @Test
    fun missingRootDegradesAndUnverifiableRuntimeRequiresCleanup() {
        val degraded = RootReconciliation.checked(cached, RootStatus("none", "unknown", RootCode.ROOT_NOT_FOUND), null)
        assertEquals(TunState.DEGRADED, degraded.state)
        assertFalse(degraded.stale)
        assertEquals(RootCode.ROOT_NOT_FOUND.name, degraded.lastErrorCode)
        val inconsistent = RootReconciliation.checked(cached, granted, ShellResult(1, "running -", ""))
        assertEquals(TunState.STOPPING, inconsistent.state)
        assertEquals(RootCode.CLEANUP_FAILED.name, inconsistent.lastErrorCode)
        assertFalse(inconsistent.stale)
        val unavailable = RootReconciliation.checked(cached, granted, ShellResult(-1, "", "", timedOut = true))
        assertEquals(cached.state, unavailable.state)
        assertTrue(unavailable.stale)
        assertNull(unavailable.lastErrorCode)
    }

    @Test
    fun restorationDifferenceRemainsVisibleAfterReconciliation() {
        val checked = RootReconciliation.checked(cached, granted, ShellResult(1, "disabled -\nrestore-diff:yes\nautostart:no", ""))
        assertTrue(RootCode.CLEANUP_FAILED.name in checked.warnings)
        assertFalse(checked.stale)
    }

    @Test
    fun rootStoppingRevocationIsNotCleanupFailureAndAutostartFailureSurvivesMissingAppGrant() {
        val missing = RootStatus("kernelsu", "notGranted")
        val stopping = RootReconciliation.checked(cached, missing, ShellResult(0, "stopping ROOT_PERMISSION_REVOKED\nbootMs:1000", ""))
        assertEquals(TunState.STOPPING, stopping.state)
        assertNull(stopping.lastErrorCode)
        val failed = RootReconciliation.checked(cached, missing, ShellResult(0, "failed AUTOSTART_FAILED\nbootMs:1000", ""))
        assertEquals(TunState.FAILED, failed.state)
        assertEquals(RootCode.AUTOSTART_FAILED.name, failed.lastErrorCode)
        assertFalse(failed.stale)
    }

    @Test
    fun safeModeFailureIsNotRetryable() {
        val result = failure(RootCode.CORE_START_FAILED, "start", retryable = false, reason = "SAFE_MODE")
        assertFalse(result["ok"] as Boolean)
        val error = result["error"] as Map<*, *>
        assertEquals("CORE_START_FAILED", error["code"])
        assertFalse(error["retryable"] as Boolean)
        assertEquals("SAFE_MODE", (error["details"] as Map<*, *>)["reason"])
    }
}
