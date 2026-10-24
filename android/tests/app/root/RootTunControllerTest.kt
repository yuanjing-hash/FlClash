package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RootTunControllerTest {
    @Test
    fun magiskStatusPollingUsesOnlyRootReportedFiles() {
        val query = { error("Magisk background polling must not invoke su") }
        assertNull(RootTunController.monitoredStatus("magisk", null, 1_000, query))
        val status = "failed ROOT_PERMISSION_REVOKED\nauth:revoked\nbootMs:1000"
        assertEquals(status, RootTunController.monitoredStatus("magisk", status, 1_000, query)?.stdout)
        val result = ShellResult(0, "running -", "")
        assertEquals(result, RootTunController.monitoredStatus("kernelsu", null, 1_000) { result })
    }

    @Test
    fun freshReportReconcilesRunningButExpiredAndLegacyReportsRequireInspection() {
        val previous =
            RootSnapshot(state = TunState.RUNNING, rootTunEnabled = true, mode = "rootTun", rootManager = "magisk", authStatus = "granted")
        val raw = "running -\nauth:\nbootMs:1000"
        val query = { error("Magisk background polling must not invoke su") }
        val root = RootStatus("magisk", "granted")
        for (now in listOf(1_000L, 1_000 + RootRuntimeReport.MAX_AGE_MS)) {
            val status = RootTunController.monitoredStatus("magisk", raw, now, query)
            val checked = RootReconciliation.checked(RootTunController.staleRuntime(previous), root, status)
            assertEquals(TunState.RUNNING, checked.state)
            assertFalse(checked.stale)
            assertNull(checked.lastErrorCode)
        }
        for (report in listOf(raw, "running -\nauth:")) {
            assertNull(RootTunController.monitoredStatus("magisk", report, 1_001 + RootRuntimeReport.MAX_AGE_MS, query))
            val stale = RootTunController.staleRuntime(previous)
            assertTrue(stale.stale)
            assertEquals(TunState.STOPPING, stale.state)
            assertEquals(RootCode.CLEANUP_FAILED.name, stale.lastErrorCode)
            assertEquals("granted", stale.authStatus)
        }
    }

    @Test
    fun missingMagiskReportsBackOffAfterThirtySecondsWithoutSuAndResetOnRecovery() {
        val polling = RootTunController.ReconciliationPolling()
        val checks = mutableListOf<Long>()
        var current =
            RootSnapshot(state = TunState.RUNNING, rootTunEnabled = true, mode = "rootTun", rootManager = "magisk", authStatus = "granted")
        var suCalls = 0
        val query = {
            suCalls++
            ShellResult(0, "running -", "")
        }
        polling.missing(0)
        for (now in 0L..95_000L step 1_000L) {
            if (!polling.due(now)) continue
            checks.add(now)
            assertNull(RootTunController.monitoredStatus("magisk", null, now, query))
            current = RootTunController.staleRuntime(current)
            assertFalse(RootTunController.authorizationProbeAllowed(current, runtimeMayExist = true))
        }
        assertEquals((0L..30_000L step 1_000L).toList() + listOf(60_000L, 90_000L), checks)
        assertEquals(0, suCalls)
        assertTrue(current.stale)
        assertEquals(TunState.STOPPING, current.state)
        assertEquals(RootCode.CLEANUP_FAILED.name, current.lastErrorCode)
        polling.reset()
        assertTrue(polling.due(95_000))
        assertFalse(polling.due(95_999))
        assertTrue(polling.due(96_000))
    }

    @Test
    fun backgroundAuthorizationNeverProbesMagiskOrStoppedRuntime() {
        val running =
            RootSnapshot(state = TunState.RUNNING, rootTunEnabled = true, rootManager = "magisk", authStatus = "granted")
        assertFalse(RootTunController.authorizationProbeAllowed(running, runtimeMayExist = true))
        for (manager in listOf("kernelsu", "apatch")) {
            val current = running.copy(rootManager = manager)
            assertTrue(RootTunController.authorizationProbeAllowed(current, runtimeMayExist = true))
            assertFalse(RootTunController.authorizationProbeAllowed(current, runtimeMayExist = false))
            assertFalse(RootTunController.authorizationProbeAllowed(current.copy(state = TunState.DISABLED), runtimeMayExist = true))
            assertFalse(RootTunController.authorizationProbeAllowed(current.copy(authStatus = "revoked"), runtimeMayExist = true))
        }
    }

    @Test
    fun disabledRecheckWithoutGrantHasNoStartIntentOrError() {
        val disabled = RootSnapshot(state = TunState.DISABLED, rootTunEnabled = false)
        val missingGrant = RootStatus("kernelsu", "notGranted", RootCode.ROOT_GRANT_REQUIRED_IN_MANAGER)
        val result = RootTunController.recheckedAuth(disabled, missingGrant, desiredRunning = false)
        assertEquals(TunState.DISABLED, result.state)
        assertEquals("notGranted", result.authStatus)
        assertNull(result.lastErrorCode)
        assertFalse(result.rootTunEnabled)
        assertFalse(result.stale)
    }

    @Test
    fun pendingStartStillWaitsForGrantAndCancelledStartReturnsDisabled() {
        val missingGrant = RootStatus("kernelsu", "notGranted")
        val pending = RootSnapshot(state = TunState.AWAITING_AUTH, rootTunEnabled = true)
        assertEquals(TunState.AWAITING_AUTH, RootTunController.recheckedAuth(pending, missingGrant, desiredRunning = true).state)
        assertEquals(TunState.DISABLED, RootTunController.recheckedAuth(pending, missingGrant, desiredRunning = false).state)
    }

    @Test
    fun recheckRetriesRevokedRootIntentButDoesNotRestartDisabledOrAcknowledgedFailure() {
        val revoked =
            RootSnapshot(
                state = TunState.FAILED,
                rootTunEnabled = true,
                authStatus = "revoked",
                lastErrorCode = RootCode.ROOT_PERMISSION_REVOKED.name,
            )
        assertTrue(RootTunController.retryRevoked(revoked))
        assertFalse(RootTunController.retryRevoked(revoked.copy(rootTunEnabled = false)))
        assertFalse(RootTunController.retryRevoked(revoked.copy(lastErrorCode = null)))
        assertFalse(RootTunController.retryRevoked(RootSnapshot()))
    }

    @Test
    fun lostSuWaitsForSignedRootCleanupWithoutReportingCleanupFailure() {
        for (manager in listOf("kernelsu", "apatch")) {
            val previous = RootSnapshot(state = TunState.RUNNING, rootTunEnabled = true, rootManager = manager, authStatus = "granted")
            for (failure in listOf(
                ShellResult(127, "", "Executable unavailable"),
                ShellResult(1, "", "Permission denied"),
                ShellResult(-1, "", "", true),
            )) {
                assertNull(RootTunController.monitoredStatus(manager, null, 1000) { failure })
                val pending = RootTunController.unavailableAuthorization(previous)
                assertEquals(TunState.RUNNING, pending.state)
                assertTrue(pending.stale)
                assertNull(pending.lastErrorCode)
                val raw = "failed ROOT_PERMISSION_REVOKED\nauth:revoked\nautostart:no\nbootMs:1000"
                val reported = RootTunController.monitoredStatus(manager, raw, 1000) { error("signed report must avoid su") }
                val checked = RootReconciliation.checked(pending, RootStatus(manager, "notGranted"), reported)
                assertEquals(TunState.FAILED, checked.state)
                assertEquals("revoked", checked.authStatus)
                assertFalse(checked.autostartEnabled)
                assertFalse(checked.stale)
                assertEquals(RootCode.ROOT_PERMISSION_REVOKED.name, checked.lastErrorCode)
                val completed = RootTunController.cleanedRevocation(previous)
                assertEquals(previous.intentRevision + 1, completed.intentRevision)
                assertEquals(TunState.FAILED, completed.state)
                assertEquals("revoked", completed.authStatus)
                assertFalse(completed.autostartEnabled)
            }
        }
    }

    @Test
    fun repeatedErrorKeepsOneOccurrenceAcrossStatusRefreshesAndResetsForNewSession() {
        val occurrences = RootTunController.ErrorOccurrences()
        val code = RootCode.CLEANUP_FAILED
        assertEquals(1000L, occurrences.observe(code, 1000).at)
        assertEquals(1000L, occurrences.observe(code, 2000).at)
        assertEquals(3000L, occurrences.observe(RootCode.ROOT_PERMISSION_REVOKED, 3000).at)
        assertEquals(1000L, occurrences.observe(code, 4000).at)
        assertFalse(occurrences.observe(code, 4000).first)
        occurrences.reset()
        assertEquals(5000L, occurrences.observe(code, 5000).at)
    }

    @Test
    fun processReopenRequiresMatchingRootSessionAndVerifiedNetworkBeforeAbnormalBanner() {
        val directory =
            java.nio.file.Files
                .createTempDirectory("root-session")
                .toFile()
        try {
            val marker = java.io.File(directory, "session")
            val running = RootSnapshot(state = TunState.RUNNING, rootTunEnabled = true)
            val raw = "running -\nsession:boot-session-1\nstop:active"
            assertFalse(RootPreviousSession(marker).observe(raw, running))
            val reopened = RootPreviousSession(marker)
            assertFalse(reopened.observe(raw, running.copy(stale = true)))
            assertTrue(reopened.observe(raw, running))
            assertFalse(reopened.observe(raw, running))
            val failed = running.copy(state = TunState.FAILED, lastErrorCode = RootCode.CORE_RECOVERY_FAILED.name)
            assertTrue(RootPreviousSession(marker).observe(raw.replace("stop:active", "stop:abnormal"), failed))
            assertFalse(marker.exists())
            marker.writeText("boot-session-1")
            assertFalse(
                RootPreviousSession(marker).observe(raw.replace("stop:active", "stop:normal"), running.copy(state = TunState.DISABLED)),
            )
            marker.writeText("boot-session-1")
            assertFalse(RootPreviousSession(marker).observe(raw.replace("session-1", "session-2"), running))
            val normalStop = RootPreviousSession(marker)
            normalStop.clear()
            assertFalse(normalStop.observe(raw, running))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun nonUuidRequestIdIsRejectedBeforeDiagnostics() {
        requireRequestId("not-a-uuid")
    }
}
