package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class RootDnsCacheTest {
    private class Backend :
        RootDnsCache.Resolver,
        RootDnsCache.Command {
        val networks = mutableListOf<Int>()
        val commands = mutableListOf<List<String>>()
        var failedNetwork: Int? = null
        var broadcast = ShellResult(0, "Broadcast completed: result=0\n", "")

        override fun flush(networkId: Int) {
            networks += networkId
            if (networkId == failedNetwork) throw IOException("Network cache no longer exists")
        }

        override fun run(arguments: List<String>): ShellResult {
            commands += arguments
            return broadcast
        }
    }

    @Test
    fun refreshesEveryNetworkAndNotifiesRunningAppsThroughTheSystemCommand() {
        val backend = Backend()
        RootDnsCache(backend, backend).flush(intArrayOf(101, 102))
        assertEquals(listOf(101, 102), backend.networks)
        assertEquals(
            listOf(
                "/system/bin/cmd",
                "activity",
                "broadcast",
                "--user",
                "all",
                "-a",
                "android.intent.action.CLEAR_DNS_CACHE",
                "--receiver-registered-only",
            ),
            backend.commands.single(),
        )
    }

    @Test
    fun aDisappearingNetworkCannotPreventOtherNetworksOrApplicationCachesFromRefreshing() {
        val backend = Backend().apply { failedNetwork = 101 }
        val error = runCatching { RootDnsCache(backend, backend).flush(intArrayOf(101, 102)) }.exceptionOrNull()
        assertNotNull(error)
        assertEquals(listOf(101, 102), backend.networks)
        assertEquals(1, backend.commands.size)
        assertEquals(1, error!!.suppressed.size)
    }

    @Test
    fun missingAcknowledgementPermissionErrorsAndTimeoutsCannotReportSuccessfulRefresh() {
        for (result in listOf(
            ShellResult(0, "Broadcasting: clear DNS\n", ""),
            ShellResult(1, "", "Permission denied"),
            ShellResult(0, "Broadcast completed: result=0\n", "", true),
        )) {
            val backend = Backend().apply { broadcast = result }
            val error = runCatching { RootDnsCache(backend, backend).flush(intArrayOf(101)) }.exceptionOrNull()
            assertTrue(error is IOException)
            assertEquals(listOf(101), backend.networks)
            assertFalse(backend.commands.isEmpty())
        }
    }
}
