package com.follow.clash.root

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.follow.clash.common.AccessControlMode
import com.follow.clash.models.SharedState
import com.follow.clash.service.models.VpnOptions
import com.follow.clash.service.models.toCIDR
import com.follow.clash.service.models.tunMtu
import com.google.gson.Gson

internal data class RootPreparedSettings(
    val launch: Map<String, Any>,
    val files: Map<String, String>,
)

internal object RootLaunchConfig {
    private val systemDnsUids = listOf(0, 1051, 1052)

    fun systemDns(context: Context): List<String> {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return emptyList()
        return connectivity.allNetworks
            .flatMap { network ->
                val capabilities = connectivity.getNetworkCapabilities(network)
                if (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) != true ||
                    !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                ) {
                    emptyList()
                } else {
                    connectivity.getLinkProperties(network)?.dnsServers.orEmpty()
                }
            }.map { address ->
                val host = checkNotNull(address.hostAddress)
                if (':' in host) "[$host]:53" else "$host:53"
            }.distinct()
    }

    fun prepare(
        state: SharedState,
        appUid: Int,
        resolve: (String) -> Int?,
        packages: Map<String, String>,
        systemDns: List<String> = emptyList(),
    ): RootPreparedSettings {
        val options = checkNotNull(state.vpnOptions) { "UI VPN options are unavailable" }
        val setup = checkNotNull(state.setupParams) { "UI Core setup parameters are unavailable" }
        val (include, exclude) = uids(options, appUid, resolve)
        val routes = options.routeAddress.ifEmpty { listOf("0.0.0.0/0", "::/0") } + listOf("198.18.0.0/30", "fdfe:dcba:9876::/126")
        val launch =
            mutableMapOf<String, Any>(
                "setup" to setup,
                "tun" to (tun(options, include, exclude) + ("systemDns" to systemDns)),
                "packages" to packages,
            )
        state.updateParams?.let { launch["updates"] = it }
        return RootPreparedSettings(
            launch,
            mapOf(
                "vpn-options.json" to Gson().toJson(options),
                "tun.enabled" to if (options.enable) "1\n" else "0\n",
                "ipv6.enabled" to if (options.ipv6) "1\n" else "0\n",
                "allow-bypass" to if (options.allowBypass) "1\n" else "0\n",
                "dns-hijacking" to if (options.dnsHijacking) "1\n" else "0\n",
                "per-app-dns" to if (options.enable && options.accessControlProps.enable) "1\n" else "0\n",
                "bypass.uids" to bypassUidRanges(include, exclude).joinToString("\n"),
                "routes4" to routes.filterNot { ':' in it }.joinToString("\n", postfix = "\n"),
                "routes6" to routes.filter { ':' in it }.joinToString("\n", postfix = "\n"),
                "system-proxy" to "",
                "proxy-exclusions" to options.bypassDomain.joinToString(","),
            ),
        )
    }

    fun uids(
        options: VpnOptions,
        appUid: Int,
        resolve: (String) -> Int?,
    ): Pair<List<Int>, List<Int>> {
        val access = options.accessControlProps
        if (!access.enable) return emptyList<Int>() to emptyList()

        fun resolveAll(packages: List<String>): List<Int> = packages.mapNotNull(resolve).distinct().sorted()
        return when (access.mode) {
            AccessControlMode.ACCEPT_SELECTED ->
                (resolveAll(access.acceptList) + systemDnsUids + appUid).distinct().sorted() to
                    emptyList()
            AccessControlMode.REJECT_SELECTED -> emptyList<Int>() to resolveAll(access.rejectList).filter { it != appUid }
        }
    }

    fun tun(
        options: VpnOptions,
        include: List<Int>,
        exclude: List<Int>,
    ): Map<String, Any> {
        require(options.stack in setOf("mips", "system", "gvisor", "mixed")) { "Unsupported TUN stack" }
        options.routeAddress.forEach(String::toCIDR)
        return mapOf(
            "enable" to options.enable,
            "perApp" to options.accessControlProps.enable,
            "ipv6" to options.ipv6,
            "dnsHijacking" to options.dnsHijacking,
            "stack" to options.stack,
            "mtu" to options.tunMtu,
            "congestionController" to options.congestionController.orEmpty(),
            "routeAddress" to options.routeAddress,
            "includeUid" to include,
            "excludeUid" to exclude,
        )
    }

    fun bypassUidRanges(
        include: List<Int>,
        exclude: List<Int>,
    ): List<String> {
        if (include.isEmpty()) {
            val ranges = mutableListOf<String>()
            val sorted = exclude.distinct().sorted()
            var index = 0
            while (index < sorted.size) {
                val first = sorted[index]
                require(first >= 0)
                var last = first
                while (++index < sorted.size && sorted[index].toLong() == last.toLong() + 1) last = sorted[index]
                ranges += if (first == last) "$first" else "$first-$last"
            }
            return ranges
        }
        var previous = 0L
        val ranges = mutableListOf<String>()
        for (uid in include.distinct().sorted()) {
            require(uid >= 0)
            if (uid > previous) ranges += "$previous-${uid.toLong() - 1}"
            previous = uid.toLong() + 1
        }
        if (previous <= Int.MAX_VALUE) ranges += "$previous-${Int.MAX_VALUE}"
        return ranges
    }
}
