package com.follow.clash.root

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootHealthTest {
    @Test
    fun rejectsTruncationWrongTransactionAndQueries() {
        val response = byteArrayOf(0x46, 0x43, 0x81.toByte(), 0x80.toByte(), 0, 1, 0, 1, 0, 0, 0, 0)
        assertTrue(RootHealth.validResponse(response, 0x4643))
        assertFalse(RootHealth.validResponse(response, 0x4644))
        assertFalse(RootHealth.validResponse(response.copyOf(11), 0x4643))
        response[2] = 1
        assertFalse(RootHealth.validResponse(response, 0x4643))
    }

    @Test
    fun prerequisiteFailureAndWireEnumsFollowContract() {
        val error = failure(RootCode.ROOT_NOT_FOUND, "detectRoot")["error"] as Map<*, *>
        assertFalse(error["retryable"] as Boolean)
        assertTrue(TunState.fromWire("awaitingAuth") == TunState.AWAITING_AUTH)
    }
}
