package com.follow.clash.root

import com.follow.clash.core.CoreControlState
import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreControlStateTest {
    @Test
    fun pendingNetworkProbesDoNotDelayRootOwnershipHandoff() {
        val state = CoreControlState()
        for (method in listOf("outboundIp", "probe", "serviceCheck", "asyncTestDelay", "getConnections")) {
            assertFalse(state.requiresSettledCore("""{"method":"$method"}"""))
        }
        for (method in listOf("setupConfig", "updateConfig", "changeProxy", "buildProfile", "initClash")) {
            assertTrue(state.requiresSettledCore("""{"method":"$method"}"""))
        }
    }

    @Test
    fun rootLaunchIncludesSettingsAlreadyAppliedBeforeTheModeSwitch() {
        val state = CoreControlState()
        state.capture("""{"method":"setupConfig","arguments":{}}""")
        state.capture("""{"method":"updateConfig","arguments":{"mode":"global","mixed-port":7899,"ipv6":true}}""")
        val selection = """{"method":"changeProxy","arguments":{"group-name":"group","proxy-name":"node-b"}}"""
        state.capture(selection)
        state.complete(selection, """{"result":{"changed":true,"message":""}}""".toByteArray())
        state.beginTransition()
        assertEquals("node-b", JsonParser.parseString(state.currentSelections()).asJsonObject["group"].asString)
        val initial = JsonParser.parseString(state.currentUpdates()).asJsonObject
        assertEquals("global", initial["mode"].asString)
        assertEquals(7899, initial["mixed-port"].asInt)
        assertTrue(initial["ipv6"].asBoolean)
        state.capture("""{"method":"updateConfig","arguments":{"log-level":"debug","mode":null}}""")
        val current = JsonParser.parseString(state.currentUpdates()).asJsonObject
        assertEquals("global", current["mode"].asString)
        assertEquals("debug", current["log-level"].asString)
        assertEquals(1, state.finishTransition().size)
    }

    @Test
    fun profileReplacementResetsOldPatchesAndSubscriptionsSurviveHandoff() {
        val state = CoreControlState()
        state.capture("""{"method":"watchRoute","arguments":true}""")
        state.capture("""{"method":"startLog"}""")
        state.beginTransition()
        state.capture("""{"method":"updateConfig","arguments":{"mode":"direct"}}""")
        state.capture("""{"method":"setupConfig","arguments":{"test-url":"https://probe.example"}}""")
        assertEquals("{}", state.currentUpdates())
        val calls = state.finishTransition().map { JsonParser.parseString(it).asJsonObject["method"].asString }
        assertEquals(listOf("setupConfig", "watchRoute", "startLog"), calls)
        state.capture("""{"method":"stopLog"}""")
        assertEquals(1, state.finishTransition().size)
    }
}
