package com.follow.clash.root

import com.follow.clash.common.AccessControlMode
import com.follow.clash.models.SetupParams
import com.follow.clash.models.SharedState
import com.follow.clash.service.models.AccessControlProps
import com.follow.clash.service.models.VpnOptions
import com.google.gson.Gson
import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootLaunchConfigTest {
    private fun options() =
        VpnOptions(
            true,
            7890,
            true,
            false,
            AccessControlProps(true, AccessControlMode.ACCEPT_SELECTED, listOf("app", "removed"), emptyList()),
            true,
            true,
            listOf("*.example"),
            "mips",
            listOf("8.0.0.0/8", "2001:db8::/32"),
            8192,
            "bbr",
        )

    @Test
    fun carriesUiTunnelSettingsAndResolvesApplicationAccessControl() {
        val options = options()
        val (include, exclude) = RootLaunchConfig.uids(options, 10190) { if (it == "app") 10200 else null }
        assertEquals(listOf(0, 1051, 1052, 10190, 10200), include)
        assertEquals(emptyList<Int>(), exclude)
        val tun = RootLaunchConfig.tun(options, include, exclude)
        assertEquals("mips", tun["stack"])
        assertEquals(8192, tun["mtu"])
        assertEquals("bbr", tun["congestionController"])
        assertEquals(true, tun["ipv6"])
        assertEquals(true, tun["perApp"])
        assertEquals(false, tun["dnsHijacking"])
        assertEquals(options.routeAddress, tun["routeAddress"])
        assertEquals(include, tun["includeUid"])
        assertEquals(listOf("1-1050", "1053-10189", "10191-10199", "10201-2147483647"), RootLaunchConfig.bypassUidRanges(include, exclude))
    }

    @Test
    fun blacklistKeepsAppControllableAndRootCaptureRunsWithVpnDisabled() {
        val options =
            options().copy(
                enable = false,
                accessControlProps =
                    AccessControlProps(true, AccessControlMode.REJECT_SELECTED, emptyList(), listOf("self", "other", "removed")),
            )
        val (include, exclude) =
            RootLaunchConfig.uids(options, 10190) {
                when (it) {
                    "self" -> 10190
                    "other" -> 10200
                    else -> null
                }
            }
        assertEquals(emptyList<Int>(), include)
        assertEquals(listOf(10200), exclude)
        assertEquals(listOf("10200"), RootLaunchConfig.bypassUidRanges(include, exclude))
        assertEquals(
            false,
            RootLaunchConfig.tun(
                options.copy(accessControlProps = options.accessControlProps.copy(enable = false)),
                include,
                exclude,
            )["perApp"],
        )
        assertTrue(RootLaunchConfig.tun(options, include, exclude)["enable"] as Boolean)
    }

    @Test
    fun excludedBankAndIncludedChatgptUseBlacklistUidsEvenWhenVpnIsOff() {
        val options =
            options().copy(
                enable = false,
                accessControlProps =
                    AccessControlProps(
                        true,
                        AccessControlMode.REJECT_SELECTED,
                        listOf("com.openai.chatgpt"),
                        listOf("com.android.bankabc"),
                    ),
            )
        val packages = mapOf("com.android.bankabc" to 10314, "com.openai.chatgpt" to 10527)
        val prepared =
            RootLaunchConfig.prepare(
                SharedState(vpnOptions = options, setupParams = SetupParams("https://example.test/ping", emptyMap(), true)),
                10190,
                packages::get,
                emptyMap(),
            )
        val tun = prepared.launch.getValue("tun") as Map<*, *>
        assertEquals(true, tun["enable"])
        assertEquals(true, tun["perApp"])
        assertEquals(emptyList<Int>(), tun["includeUid"])
        assertEquals(listOf(10314), tun["excludeUid"])
        assertEquals("10314", prepared.files["bypass.uids"])
        assertEquals("1\n", prepared.files["tun.enabled"])
        assertEquals("1\n", prepared.files["per-app-dns"])
        assertEquals(options, Gson().fromJson(prepared.files["vpn-options.json"], VpnOptions::class.java))
    }

    @Test
    fun vpnHttpProxyPreferencesCannotChangeRootTunRouting() {
        val state =
            SharedState(vpnOptions = options().copy(port = 0), setupParams = SetupParams("https://example.test/ping", emptyMap(), true))
        val enabled = RootLaunchConfig.prepare(state, 10190, { 10200 }, emptyMap())
        val disabled =
            RootLaunchConfig.prepare(
                state.copy(vpnOptions = state.vpnOptions!!.copy(systemProxy = false)),
                10190,
                { 10200 },
                emptyMap(),
            )
        assertEquals(enabled.launch, disabled.launch)
        assertEquals("", enabled.files["system-proxy"])
        assertEquals("", disabled.files["system-proxy"])
        assertEquals(state.vpnOptions, Gson().fromJson(enabled.files["vpn-options.json"], VpnOptions::class.java))
    }

    @Test
    fun manualAndBootPreparationUseTheSavedUiStateIncludingLiveCoreSettings() {
        val state =
            SharedState(
                vpnOptions = options(),
                setupParams = SetupParams("https://example.test/ping", mapOf("select" to "node-b"), true),
                updateParams = JsonParser.parseString("""{"mode":"global","mixed-port":7890,"dns":{"enable":false}}""").asJsonObject,
            )
        val dns = listOf("192.168.2.1:53", "218.2.2.2:53", "[2001:db8::53]:53")
        val prepared = RootLaunchConfig.prepare(state, 10190, { 10200 }, mapOf("10200" to "app"), dns)
        assertEquals(dns, (prepared.launch["tun"] as Map<*, *>)["systemDns"])
        assertEquals(state.setupParams, prepared.launch["setup"])
        assertEquals(state.updateParams, prepared.launch["updates"])
        assertEquals(state.vpnOptions, Gson().fromJson(prepared.files["vpn-options.json"], VpnOptions::class.java))
        assertEquals("", prepared.files["system-proxy"])
        assertEquals("*.example", prepared.files["proxy-exclusions"])
        assertEquals("1\n", prepared.files["allow-bypass"])
        assertEquals("0\n", prepared.files["dns-hijacking"])
        assertEquals("1\n", prepared.files["per-app-dns"])
        assertEquals("8.0.0.0/8\n198.18.0.0/30\n", prepared.files["routes4"])
        assertEquals("2001:db8::/32\nfdfe:dcba:9876::/126\n", prepared.files["routes6"])
        val changed =
            RootLaunchConfig.prepare(state.copy(vpnOptions = options().copy(enable = false, systemProxy = false)), 10190, {
                null
            }, emptyMap())
        assertEquals("1\n", changed.files["tun.enabled"])
        assertEquals("1\n", changed.files["per-app-dns"])
        assertEquals("", changed.files["system-proxy"])
        assertFalse(prepared.files["vpn-options.json"] == changed.files["vpn-options.json"])
        assertEquals(listOf("10000-10002", "10100"), RootLaunchConfig.bypassUidRanges(emptyList(), listOf(10002, 10000, 10100, 10001)))
    }
}
