package com.follow.clash.service.modules

import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkObservationTest {
    private val wifi = NetworkLink(10, "wlan0", listOf("192.168.2.10/24"), listOf("default via 192.168.2.1"), listOf("192.168.2.1:53"))
    private val mobile = NetworkLink(20, "rmnet_data0", listOf("10.0.0.2/30"), listOf("default via 10.0.0.1"), listOf("218.2.2.2:53"))

    @Test
    fun wifiToCellularRefreshesDnsAndReconnectsWithoutRestartingTheService() {
        val events = mutableListOf<String>()
        val observer = NetworkObservation({ events += "dns:$it" }, { events += "capture:$it" }, { events += "reset" })
        observer.update(wifi, wifi.dns + mobile.dns)
        assertEquals(0, events.count { it == "reset" })
        observer.update(mobile, mobile.dns)
        assertEquals(1, events.count { it == "reset" })
        assertEquals("dns:218.2.2.2:53", events.filter { it.startsWith("dns:") }.last())
        assertEquals("capture:218.2.2.2:53", events.last())
    }

    @Test
    fun mobileAddressOrRouteChangesReconnectEvenWhenHandleAndDnsStayTheSame() {
        var resets = 0
        val dns = mutableListOf<String>()
        val observer = NetworkObservation(dns::add, null) { resets++ }
        observer.update(mobile, mobile.dns)
        val renewed = mobile.copy(addresses = listOf("10.2.0.2/30"))
        observer.update(renewed, mobile.dns)
        observer.update(renewed.copy(routes = listOf("default via 10.2.0.1")), mobile.dns)
        assertEquals(2, resets)
        assertEquals(listOf("218.2.2.2:53"), dns)
    }

    @Test
    fun duplicateLinkAndReorderedCaptureUpdatesLeaveLiveConnectionsAlone() {
        var resets = 0
        val capture = mutableListOf<String>()
        val observer = NetworkObservation({}, capture::add) { resets++ }
        observer.update(wifi, wifi.dns + mobile.dns)
        repeat(5) { observer.update(wifi.copy(), mobile.dns + wifi.dns + wifi.dns) }
        assertEquals(0, resets)
        assertEquals(1, capture.size)
    }

    @Test
    fun networkLossClosesOldConnectionsOnceAndRecoveryPublishesTheNewDns() {
        var resets = 0
        val dns = mutableListOf<String>()
        val observer = NetworkObservation(dns::add, null) { resets++ }
        observer.update(wifi, wifi.dns)
        observer.update(null, emptyList())
        observer.update(null, emptyList())
        observer.update(mobile, mobile.dns)
        assertEquals(1, resets)
        assertEquals(listOf("192.168.2.1:53", "", "218.2.2.2:53"), dns)
    }

    @Test
    fun observerDisposalPreservesStandaloneCoreDnsAndNewSessionResendsItsSnapshot() {
        val events = mutableListOf<String>()
        val observer = NetworkObservation({ events += "dns:$it" }, { events += "capture:$it" }, { events += "reset" })
        observer.update(wifi, wifi.dns)
        val before = events.toList()
        observer.clear()
        assertEquals(before, events)
        observer.update(mobile, mobile.dns)
        assertEquals(0, events.count { it == "reset" })
        assertEquals("capture:218.2.2.2:53", events.last())
    }
}
