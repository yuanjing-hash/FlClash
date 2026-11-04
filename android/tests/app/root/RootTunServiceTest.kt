package com.follow.clash.root

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootTunServiceTest {
    @Test
    fun systemRestartKeepsAnExistingRootSessionIncludingReconciliationAndCleanup() {
        val session = RootSnapshot(mode = "rootTun", rootTunEnabled = true, state = TunState.RUNNING)
        assertTrue(session.needsForegroundService)
        assertTrue(session.copy(stale = true).needsForegroundService)
        assertTrue(session.copy(state = TunState.STARTING).needsForegroundService)
        assertTrue(session.copy(state = TunState.RECOVERING).needsForegroundService)
        assertTrue(session.copy(state = TunState.STOPPING).needsForegroundService)
    }

    @Test
    fun systemRestartCannotStartAStoppedRootSessionOrSwitchAwayFromVpn() {
        val session = RootSnapshot(mode = "rootTun", rootTunEnabled = true, state = TunState.RUNNING)
        assertFalse(session.copy(rootTunEnabled = false).needsForegroundService)
        assertFalse(session.copy(mode = "vpn").needsForegroundService)
        for (state in listOf(TunState.DISABLED, TunState.FAILED, TunState.DEGRADED, TunState.AWAITING_AUTH)) {
            assertFalse(session.copy(state = state).needsForegroundService)
            assertFalse(session.copy(state = state, stale = true).needsForegroundService)
        }
    }
}
