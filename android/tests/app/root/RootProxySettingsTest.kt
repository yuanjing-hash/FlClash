package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class RootProxySettingsTest {
    private class Settings : RootProxySettings.Command {
        val values = mutableMapOf<String, String>()
        val calls = mutableListOf<List<String>>()
        var denied: String? = null

        override fun run(vararg arguments: String): String {
            calls += arguments.toList()
            check(arguments[1] == "global")
            if (arguments[2] == denied) throw IOException("Settings access denied")
            return when (arguments[0]) {
                "get" -> (values[arguments[2]] ?: "null") + "\n"
                "put" -> {
                    values[arguments[2]] = arguments[3]
                    ""
                }
                else -> error("Unexpected settings operation")
            }
        }
    }

    private val own = RootProxyState.Value("127.0.0.1", 7890, listOf("localhost", "*.local"), "")

    @Test
    fun readsTheReportedStaleProxyWithoutAContentResolver() {
        val command = Settings()
        command.values.putAll(
            mapOf(
                "global_http_proxy_host" to "127.0.0.1",
                "global_http_proxy_port" to "7890",
                "global_http_proxy_exclusion_list" to "LOCALHOST,*.local,localhost",
                "global_proxy_pac_url" to "",
            ),
        )
        assertEquals(own, RootProxySettings(command).read())
        assertEquals(4, command.calls.size)
        assertTrue(command.calls.all { it[0] == "get" && it[1] == "global" })
    }

    @Test
    fun missingSettingsRepresentNoGlobalProxy() {
        assertNull(RootProxySettings(Settings()).read())
    }

    @Test
    fun restorationClearsAllFourStoredProxyKeysAndVerifiesThem() {
        val command = Settings()
        val settings = RootProxySettings(command)
        settings.write(own)
        val backend =
            object : RootProxyState.Backend {
                override fun cached(): RootProxyState.Value? = null

                override fun stored(): RootProxyState.Value? = settings.read()

                override fun request(target: RootProxyState.Value?) = Unit

                override fun repairStored(target: RootProxyState.Value?) = settings.write(target)
            }
        RootProxyState.restore(backend, RootProxyState.plan(null, settings.read(), RootProxyState.Lease(null, own), null))
        assertNull(settings.read())
        assertEquals("", command.values["global_http_proxy_host"])
        assertEquals("0", command.values["global_http_proxy_port"])
        assertEquals("", command.values["global_http_proxy_exclusion_list"])
        assertEquals("", command.values["global_proxy_pac_url"])
    }

    @Test
    fun restoresForeignPacValuesAsLiteralArguments() {
        val command = Settings()
        val settings = RootProxySettings(command)
        val pac = RootProxyState.Value("", 0, emptyList(), "https://proxy.example/pac?one=1&two=2")
        settings.write(pac)
        assertEquals(pac, settings.read())
        assertTrue(command.calls.contains(listOf("put", "global", "global_proxy_pac_url", pac.pac)))
    }

    @Test
    fun failedReadsAndPartialWritesCannotReportSuccessfulRestoration() {
        val command = Settings()
        val settings = RootProxySettings(command)
        settings.write(own)
        command.calls.clear()
        command.denied = "global_http_proxy_host"
        assertTrue(runCatching { settings.read() }.exceptionOrNull() is IOException)
        command.denied = "global_http_proxy_port"
        assertTrue(runCatching { settings.write(null) }.exceptionOrNull() is IOException)
        assertEquals("7890", command.values["global_http_proxy_port"])
        assertFalse(command.calls.any { it == listOf("put", "global", "global_proxy_pac_url", "") })
    }
}
