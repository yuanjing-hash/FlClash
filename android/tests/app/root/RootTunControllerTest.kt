package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RootTunControllerTest {
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
