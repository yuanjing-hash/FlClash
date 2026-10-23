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
        assertNull(RootTunController.monitoredStatus("magisk", null, query))
        val status = "failed ROOT_PERMISSION_REVOKED\nauth:revoked"
        assertEquals(status, RootTunController.monitoredStatus("magisk", status, query)?.stdout)
        val result = ShellResult(0, "running -", "")
        assertEquals(result, RootTunController.monitoredStatus("kernelsu", null) { result })
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

    @Test(expected = IllegalArgumentException::class)
    fun nonUuidRequestIdIsRejectedBeforeDiagnostics() {
        requireRequestId("not-a-uuid")
    }
}
