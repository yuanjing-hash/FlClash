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
    fun onlyAnExplicitPreviousBootReportRequestsCleanupAndAStoppedReportClearsTheOldError() {
        assertFalse(RootReconciliation.requiresBootCleanup(null))
        assertFalse(RootReconciliation.requiresBootCleanup(ShellResult(1, "stopping CLEANUP_FAILED\n", "")))
        assertFalse(RootReconciliation.requiresBootCleanup(ShellResult(0, "running -\nruntime-boot:current\n", "")))
        assertTrue(RootReconciliation.requiresBootCleanup(ShellResult(1, "stopping CLEANUP_FAILED\nruntime-boot:previous\n", "")))
        val stopped =
            RootReconciliation.checked(
                cached.copy(state = TunState.STOPPING, lastErrorCode = RootCode.CLEANUP_FAILED.name, lastErrorAt = 123L),
                granted,
                ShellResult(1, "disabled -\nautostart:no\n", ""),
            )
        assertEquals(TunState.DISABLED, stopped.state)
        assertFalse(stopped.autostartEnabled)
        assertFalse(stopped.stale)
        assertNull(stopped.lastErrorCode)
        assertNull(stopped.lastErrorAt)
    }

    @Test
    fun reattachingAnExistingCorePreservesItsRuntimeAndANewCoreResetsIt() {
        val previous = cached.copy(state = TunState.STARTING, startedAt = 1_000L, warnings = listOf(RootCode.CLEANUP_FAILED.name))
        val attached = RootReconciliation.running(previous, installed = false, status = "running -\nautostart:no", now = 9_000L)
        assertEquals(TunState.RUNNING, attached.state)
        assertEquals(1_000L, attached.startedAt)
        assertTrue(attached.warnings.isEmpty())
        assertFalse(attached.autostartEnabled)
        val restarted = RootReconciliation.running(previous, installed = true, status = "running -\nautostart:yes", now = 9_000L)
        assertEquals(9_000L, restarted.startedAt)
        assertTrue(restarted.autostartEnabled)
        val unknown = RootReconciliation.running(previous.copy(startedAt = null), installed = false, status = "running -", now = 9_000L)
        assertEquals(9_000L, unknown.startedAt)
    }

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
    fun missingFirstReportPreservesStateAndOnlyUnconfirmedActiveRuntimeEscalatesAfterGrace() {
        for (state in TunState.entries) {
            val restored = RootReconciliation.initial(cached.copy(state = state))
            for (status in listOf(null, ShellResult(0, "", ""), ShellResult(1, "", "unavailable"))) {
                val waiting = RootReconciliation.checked(restored, granted, status)
                assertEquals(restored, waiting)
                assertNull(waiting.lastErrorCode)
            }
            val expired = RootReconciliation.missing(restored, graceExpired = true)
            if (state in setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING, TunState.STOPPING)) {
                assertEquals(TunState.STOPPING, expired.state)
                assertEquals(RootCode.CLEANUP_FAILED.name, expired.lastErrorCode)
            } else {
                assertEquals(state, expired.state)
                assertNull(expired.lastErrorCode)
            }
            assertTrue(expired.stale)
        }
        for (code in listOf(RootCode.AUTOSTART_FAILED, RootCode.CORE_RECOVERY_FAILED, RootCode.ROOT_PERMISSION_REVOKED)) {
            val cleaned = cached.copy(state = TunState.FAILED, lastErrorCode = code.name, lastErrorAt = 1234)
            assertEquals(cleaned.copy(stale = true), RootReconciliation.missing(cleaned, graceExpired = true))
        }
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
    fun networkSnapshotDifferencesDoNotFailSuccessfulCleanupAndRealCleanupFailuresRemainVisible() {
        val checked = RootReconciliation.checked(cached, granted, ShellResult(1, "disabled -\nrestore-diff:yes\nautostart:no", ""))
        assertEquals(TunState.DISABLED, checked.state)
        assertNull(checked.lastErrorCode)
        assertFalse(RootCode.CLEANUP_FAILED.name in checked.warnings)
        assertFalse(checked.stale)
        val failed = RootReconciliation.checked(cached, granted, ShellResult(1, "stopping CLEANUP_FAILED\nrestore-diff:yes", ""))
        assertEquals(TunState.STOPPING, failed.state)
        assertEquals(RootCode.CLEANUP_FAILED.name, failed.lastErrorCode)
    }

    @Test
    fun verifiedStopClearsCleanupWarningAndPreservesSelectedModeUntilDisabled() {
        val previous =
            cached.copy(
                state = TunState.STOPPING,
                rootTunEnabled = true,
                mode = "rootTun",
                autostartEnabled = true,
                warnings = listOf(RootCode.CLEANUP_FAILED.name),
                lastErrorCode = RootCode.CLEANUP_FAILED.name,
                lastErrorAt = 123L,
                startedAt = 100L,
                stale = true,
            )
        val stopped = RootReconciliation.stopped(previous, disabled = false, switchedToVpn = false)
        assertEquals(TunState.DISABLED, stopped.state)
        assertEquals(emptyList<String>(), stopped.warnings)
        assertNull(stopped.lastErrorCode)
        assertNull(stopped.lastErrorAt)
        assertNull(stopped.startedAt)
        assertFalse(stopped.stale)
        assertTrue(stopped.rootTunEnabled)
        assertTrue(stopped.autostartEnabled)
        assertEquals("rootTun", stopped.mode)
        val disabled = RootReconciliation.stopped(previous, disabled = true, switchedToVpn = false)
        assertFalse(disabled.rootTunEnabled)
        assertFalse(disabled.autostartEnabled)
        assertEquals("off", disabled.mode)
        assertEquals("vpn", RootReconciliation.stopped(previous, disabled = true, switchedToVpn = true).mode)
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
